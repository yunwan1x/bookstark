package com.bookstark.bookstark_flutter

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.View
import android.view.WindowManager
import android.webkit.*
import android.widget.EditText
import android.widget.FrameLayout
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.atomic.AtomicBoolean

class ArticleWebFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        var current: Context = context
        while (current !is Activity && current is ContextWrapper) current = current.baseContext
        check(current is Activity)
        return ArticleWebView(current, context, viewId, messenger, args)
    }
}

/** Full Go article UI; no account tokens or arbitrary native methods are exposed to JS. */
class ArticleWebView(
    private val activity: Activity, context: Context, id: Int,
    messenger: BinaryMessenger, args: Any?
) : PlatformView {
    companion object {
        private val live = mutableSetOf<ArticleWebView>()
        fun find(lease: String): ArticleWebView? = live.firstOrNull { it.lease == lease && !it.retired }
        fun pauseAll() { live.toList().forEach { it.pauseOwned() } }
        fun retireLease(lease: String) { live.toList().filter { it.lease == lease }.forEach { it.retire() } }
        private const val chooserCode = 0x4152
        private data class Pick(val owner: ArticleWebView, var callback: ValueCallback<Array<Uri>>?)
        private var pick: Pick? = null
        fun onActivityResult(code: Int, result: Int, data: Intent?): Boolean {
            if (code != chooserCode) return false
            val request = pick ?: return true
            pick = null
            val callback = request.callback ?: return true
            val items = mutableListOf<Uri>()
            if (result == Activity.RESULT_OK && request.owner.current()) {
                val clip = data?.clipData
                if (clip != null && clip.itemCount <= 16) {
                    for (i in 0 until clip.itemCount) items.add(clip.getItemAt(i).uri)
                } else data?.data?.let { items.add(it) }
            }
            val valid = items.distinct().takeIf { values ->
                values.isNotEmpty() && values.size <= 16 && values.all {
                    it.scheme == "content" && !it.authority.isNullOrEmpty() && it.userInfo == null
                }
            }
            request.owner.selectedContent.addAll(valid?.map { it.toString() } ?: emptyList())
            callback.onReceiveValue(valid?.toTypedArray())
            return true
        }
    }
    private val container = FrameLayout(context)
    private val events = MethodChannel(messenger, "bookstark/article_web_view/$id")
    private val handler = Handler(Looper.getMainLooper())
    private val lease = (args as? Map<*, *>)?.get("lease") as? String ?: ""
    private val state = ArticleWebSessionChannel.session(lease)
    private val english = state?.english == true
    private var browser: WebView? = null
    @Volatile private var retired = false
    private var paused = false
    private var failed = false
    private var lastUrl = state?.entry ?: ""
    private val selectedContent = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val dialogs = mutableSetOf<AlertDialog>()
    private val popups = mutableSetOf<WebView>()
    private var routes: ArticleWebRoutes? = null

    init {
        try {
            val session = checkNotNull(state)
            check(current())
            check(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT))
            val policy = ArticleWebRoutes(session.server, session.cookiePath)
            routes = policy
            val view = WebView(context)
            // Must precede settings, navigation and getProfile on this WebView.
            WebViewCompat.setProfile(view, session.profileName)
            browser = view
            live.add(this)
            view.setBackgroundColor(Color.WHITE)
            view.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = false
                allowContentAccess = true // Only explicit SAF FileChooser results.
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                javaScriptCanOpenWindowsAutomatically = true
                setSupportMultipleWindows(true)
                mediaPlaybackRequiresUserGesture = true
                setGeolocationEnabled(false)
                builtInZoomControls = false
                displayZoomControls = false
            }
            session.profile.cookieManager.setAcceptThirdPartyCookies(view, false)
            view.addJavascriptInterface(DownloadBridge(), "BookstarkArticleDownload")
            WebViewCompat.addDocumentStartJavaScript(view, policy.bootstrap(), setOf(policy.origin))
            view.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    if (!current()) return true
                    if (!request.isForMainFrame) return false
                    return navigate(request.url.toString())
                }
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    if (!current()) return policy.denied()
                    if (request.url.scheme == "content" && selectedContent.contains(request.url.toString())) return null
                    return policy.resource(request, session.profile.cookieManager, { current() })
                }
                override fun onPageStarted(view: WebView, url: String?, icon: android.graphics.Bitmap?) {
                    if (!current()) return
                    failed = false
                    if (url != null) lastUrl = url
                    emit("loading", mapOf("url" to lastUrl))
                }
                override fun onPageFinished(view: WebView, url: String?) {
                    if (!current() || failed) return
                    if (url != null) lastUrl = url
                    if (!paused) view.visibility = View.VISIBLE
                    emit("ready", mapOf("url" to lastUrl, "canGoBack" to view.canGoBack()))
                }
                override fun doUpdateVisitedHistory(view: WebView, url: String?, reload: Boolean) {
                    if (!current() || url == null) return
                    lastUrl = url
                    emit("history", mapOf("url" to url, "canGoBack" to view.canGoBack()))
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if ((request.isForMainFrame || policy.isBodySource(request.url)) && current()) {
                        failed = true
                        view.visibility = View.INVISIBLE
                        emit("error", mapOf("reason" to "network"))
                    }
                }
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                    if (!current()) return
                    if (request.isForMainFrame) {
                        failed = true
                        view.visibility = View.INVISIBLE
                        emit("error", mapOf("reason" to if (response.statusCode == 401) "session" else "http",
                            "status" to response.statusCode))
                    } else if (policy.isBodySource(request.url)) {
                        failed = true
                        view.visibility = View.INVISIBLE
                        emit("error", mapOf("reason" to "content"))
                    }
                }
                override fun onReceivedSslError(view: WebView, result: SslErrorHandler, error: android.net.http.SslError) {
                    result.cancel()
                    failed = true
                    view.visibility = View.INVISIBLE
                    if (current()) emit("error", mapOf("reason" to "tls"))
                }
                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                    emit("error", mapOf("reason" to "renderer")); retire(); return true
                }
            }
            view.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback?) {
                    callback?.invoke(origin, false, false)
                }
                override fun onJsAlert(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
                    dialog(message, false, null) { accepted, _ -> if (accepted) result.confirm() else result.cancel() }
                    return true
                }
                override fun onJsConfirm(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
                    dialog(message, true, null) { accepted, _ -> if (accepted) result.confirm() else result.cancel() }
                    return true
                }
                override fun onJsPrompt(view: WebView, url: String?, message: String?, defaultValue: String?, result: JsPromptResult): Boolean {
                    dialog(message, true, defaultValue ?: "") { accepted, text ->
                        if (accepted) result.confirm(text ?: "") else result.cancel()
                    }
                    return true
                }
                override fun onJsBeforeUnload(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
                    confirmLeave { accepted -> if (accepted) result.confirm() else result.cancel() }
                    return true
                }
                override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                    if (!current() || pick != null) { callback.onReceiveValue(null); return true }
                    pick = Pick(this@ArticleWebView, callback)
                    try {
                        val mimes = params.acceptTypes.flatMap { it.split(',') }.map { it.trim() }
                            .filter { it.matches(Regex("^[A-Za-z0-9*.+-]+/[A-Za-z0-9*.+-]+$")) }.distinct().take(16)
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = if (mimes.size == 1) mimes[0] else "*/*"
                            if (mimes.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, mimes.toTypedArray())
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.mode == FileChooserParams.MODE_OPEN_MULTIPLE)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        @Suppress("DEPRECATION")
                        activity.startActivityForResult(intent, chooserCode)
                    } catch (_: Exception) {
                        pick = null; callback.onReceiveValue(null)
                        emit("operationError", mapOf("reason" to "file-picker"))
                    }
                    return true
                }
                override fun onCreateWindow(view: WebView, isDialog: Boolean, userGesture: Boolean, result: Message): Boolean {
                    if (!current() || popups.size >= 2) return false
                    val popup = WebView(context)
                    WebViewCompat.setProfile(popup, session.profileName)
                    popups.add(popup)
                    val delivered = AtomicBoolean(false)
                    fun deliver(url: String) {
                        if (url == "about:blank" || !delivered.compareAndSet(false, true)) return
                        navigate(url, true)
                        handler.post { popups.remove(popup); popup.destroy() }
                    }
                    popup.webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean {
                            deliver(request.url.toString())
                            return true
                        }
                        override fun onPageStarted(v: WebView, url: String?, icon: android.graphics.Bitmap?) {
                            if (url != null) deliver(url)
                        }
                    }
                    (result.obj as WebView.WebViewTransport).webView = popup
                    result.sendToTarget()
                    return true
                }
            }
            view.setDownloadListener { url, _, disposition, mime, _ ->
                if (current()) ArticleWebDownloads.start(this, url, disposition, mime)
            }
            container.addView(view, FrameLayout.LayoutParams(-1, -1))
            view.loadUrl(session.entry)
            if ((args as? Map<*, *>)?.get("paused") == true) pauseOwned()
        } catch (_: Exception) {
            emit("error", mapOf("reason" to "webview"))
        }
    }

    fun ownedLease(): String = lease
    fun current(): Boolean = !retired && ArticleWebSessionChannel.owns(lease)
    fun profileSession(): ArticleWebSessionChannel.Session? = state?.takeIf { current() }
    fun hostActivity(): Activity = activity
    fun event(method: String, values: Map<String, Any?>) = emit(method, values)
    fun evaluate(script: String) {
        if (current()) browser?.evaluateJavascript(script, null)
    }
    private fun emit(method: String, values: Map<String, Any?>) {
        if (!retired || method == "error") handler.post {
            events.invokeMethod(method, values + ("lease" to lease))
        }
    }
    private fun navigate(url: String, forceLoad: Boolean = false): Boolean {
        if (!current()) return true
        if (url == "about:blank") return false
        val policy = routes ?: return true
        val target = policy.normalized(url, true)
        if (target != null && policy.isArticle(target)) {
            if (forceLoad || target.toString() != url) { browser?.loadUrl(target.toString()); return true }
            return false
        }
        emit("navigation", mapOf("url" to url))
        return true
    }
    private fun secure(dialog: AlertDialog) {
        if (activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0) {
            dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
    private fun dialog(message: String?, cancel: Boolean, initial: String?, complete: (Boolean, String?) -> Unit) {
        if (!current()) { complete(false, null); return }
        val once = AtomicBoolean(false)
        val input = if (initial != null) EditText(activity).apply { setText(initial.take(4096)) } else null
        val builder = AlertDialog.Builder(activity).setMessage((message ?: "").take(4096))
            .setPositiveButton(if (english) "Confirm" else "确认") { _, _ ->
                if (once.compareAndSet(false, true)) complete(true, input?.text?.toString())
            }
        if (input != null) builder.setView(input)
        if (cancel) builder.setNegativeButton(if (english) "Cancel" else "取消") { _, _ ->
            if (once.compareAndSet(false, true)) complete(false, null)
        }
        val box = builder.create()
        box.setOnCancelListener { if (once.compareAndSet(false, true)) complete(false, null) }
        box.setOnDismissListener {
            dialogs.remove(box)
            if (once.compareAndSet(false, true)) complete(false, null)
        }
        dialogs.add(box); secure(box); box.show()
    }
    private fun confirmLeave(complete: (Boolean) -> Unit) {
        dialog(if (english) "Leave this editor? Unsaved changes may remain in the web draft."
            else "离开文章编辑器？未保存的修改可能需要从网页草稿恢复。", true, null) { ok, _ -> complete(ok) }
    }
    private fun pauseOwned() {
        paused = true
        browser?.apply { visibility = View.INVISIBLE; onPause(); pauseTimers() }
    }
    fun command(method: String, result: MethodChannel.Result) {
        val view = browser
        if (!current() || view == null) { result.error("article_scope_retired", "Article page ended", null); return }
        when (method) {
            "pause" -> {
                pauseOwned(); result.success(null)
            }
            "resume" -> {
                paused = false; view.resumeTimers(); view.onResume(); view.visibility = if (failed) View.INVISIBLE else View.VISIBLE; result.success(null)
            }
            "back" -> if (view.canGoBack()) { view.goBack(); result.success(true) } else result.success(false)
            "reload" -> { view.visibility = View.VISIBLE; view.reload(); result.success(null) }
            "prepareLeave" -> if (routes?.isEditor(runCatching { URI(lastUrl) }.getOrNull() ?: URI("about:blank")) == true) {
                view.evaluateJavascript("(function(){var s=document.getElementById('save-status');return !s||!s.classList.contains('text-green-600');})()") { dirty ->
                    if (!current()) result.success(false)
                    else if (dirty == "false") result.success(true)
                    else confirmLeave { result.success(it && current()) }
                }
            } else result.success(true)
            "state" -> result.success(mapOf("format" to 1, "url" to lastUrl,
                "canGoBack" to view.canGoBack(), "paused" to paused))
            else -> result.notImplemented()
        }
    }
    private inner class DownloadBridge {
        @JavascriptInterface fun postMessage(value: String) {
            if (value.length <= 128 * 1024) ArticleWebDownloads.message(this@ArticleWebView, value)
        }
    }
    override fun getView(): View = container
    fun retire() {
        if (retired) return
        retired = true
        selectedContent.clear()
        if (pick?.owner === this) { pick?.callback?.onReceiveValue(null); pick?.callback = null }
        dialogs.toList().forEach { it.cancel() }; dialogs.clear()
        popups.toList().forEach { it.destroy() }; popups.clear()
        ArticleWebDownloads.retire(this)
        routes?.close()
        browser?.apply {
            visibility = View.INVISIBLE
            resumeTimers()
            stopLoading()
            removeJavascriptInterface("BookstarkArticleDownload")
            settings.javaScriptEnabled = false
            loadUrl("about:blank")
            removeAllViews()
            destroy()
        }
        browser = null
        container.removeAllViews()
        live.remove(this)
    }
    override fun dispose() {
        retire()
        ArticleWebSessionChannel.retire(lease)
    }
}
