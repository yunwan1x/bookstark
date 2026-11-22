package com.bookstark.bookstark_flutter

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.webkit.*
import android.widget.FrameLayout
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.util.UUID

class AdminFileEditorFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        AdminFileEditorView(context, viewId, messenger, args)
}

/** Packaged existing CodeMirror: text only, no account cookies/network/file APIs. */
class AdminFileEditorView(private val context: Context, id: Int,
    messenger: BinaryMessenger, args: Any?) : PlatformView {
    companion object {
        private val live = mutableSetOf<AdminFileEditorView>()
        fun retireAll() { live.toList().forEach { it.retire() } }
        private const val MAX = 2 * 1024 * 1024
        private val assets = mapOf(
            "/host.html" to "flutter_assets/assets/admin_files/host.html",
            "/host.js" to "flutter_assets/assets/admin_files/host.js",
            "/codemirror.js" to "flutter_assets/assets/complex_editors/static/js/codemirror-html.min.js")
    }
    private val container = FrameLayout(context)
    private val channel = MethodChannel(messenger, "bookstark/admin_file_editor/$id")
    private val host = UUID.randomUUID().toString().replace("-", "") + ".bookstark-files.invalid"
    private val origin = "https://$host"
    private val handler = Handler(Looper.getMainLooper())
    private var browser: WebView? = null
    private var reply: JavaScriptReplyProxy? = null
    private var lease = ""
    private var generation = -1
    @Volatile private var retired = false
    private var disposed = false
    private var ready = false
    private var enabled = false
    private var pending: MethodChannel.Result? = null
    private var pendingId: String? = null
    private var timeout: Runnable? = null
    private fun own(uri: Uri) = uri.scheme == "https" && uri.host == host &&
        uri.port == -1 && uri.userInfo == null && uri.query == null && uri.fragment == null
    private val csp = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; " +
        "connect-src 'none'; img-src 'none'; font-src 'none'; frame-src 'none'; worker-src 'none'; " +
        "object-src 'none'; base-uri 'none'; form-action 'none'"
    private fun valid(text: String): Boolean {
        if (text.indexOf('\u0000') >= 0 || text.toByteArray(Charsets.UTF_8).size > MAX) return false
        var i = 0
        while (i < text.length) {
            val unit = text[i++]
            if (Character.isHighSurrogate(unit)) {
                if (i >= text.length || !Character.isLowSurrogate(text[i++])) return false
            } else if (Character.isLowSurrogate(unit)) return false
        }
        return true
    }
    private fun failed() {
        if (retired) return
        retire()
        channel.invokeMethod("failed", mapOf("lease" to lease, "generation" to generation))
    }
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "retire") { retire(); result.success(null) }
            else if (call.method != "command") result.notImplemented()
            else if (retired || !ready || call.argument<String>("lease") != lease ||
                call.argument<Int>("generation") != generation) result.error("editor_closed", "Editor closed", null)
            else {
                try {
                    val type = call.argument<String>("type")
                    check(type in setOf("snapshot", "enabled", "focus", "insert", "zoom"))
                    val message = JSONObject().put("type",type).put("lease",lease).put("generation",generation)
                    when(type) {
                        "zoom" -> {
                            val zoom=call.argument<Int>("value") ?: error("No zoom")
                            check(zoom in 50..300)
                            browser?.settings?.textZoom=zoom
                            result.success(null);return@setMethodCallHandler
                        }

                        "snapshot" -> {
                            check(pending == null)
                            val commandId = UUID.randomUUID().toString()
                            pending=result;pendingId=commandId
                            message.put("id",commandId)
                            timeout=Runnable { failed() }.also { handler.postDelayed(it,10000) }
                        }
                        "enabled" -> {
                            enabled=call.argument<Boolean>("value")==true
                            message.put("value",enabled)
                        }
                        "focus" -> { check(enabled);browser?.requestFocus() }
                        "insert" -> {
                            check(enabled)
                            val text=call.argument<String>("content") ?: error("Missing text")
                            check(valid(text));message.put("content",text)
                        }
                    }
                    reply?.postMessage(message.toString()) ?: error("No bridge")
                    if(type!="snapshot") result.success(null)
                } catch(_: Exception) {
                    if(pending === result) failPending()
                    else result.error("editor_protocol","Editor command unavailable",null)
                }
            }
        }
        try {
            val parameters=args as? Map<*,*> ?: error("Missing parameters")
            lease=parameters["lease"] as? String ?: error("No lease")
            generation=parameters["generation"] as? Int ?: error("No generation")
            var initialText: String?=parameters["content"] as? String ?: error("No source")
            check(lease.matches(Regex("[a-f0-9]{64}")) && generation>=0 && valid(initialText!!))
            check(WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER))
            val view=object : WebView(context) {
                override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? {
                    val connection=super.onCreateInputConnection(outAttrs)
                    outAttrs.imeOptions=outAttrs.imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING or EditorInfo.IME_FLAG_NO_EXTRACT_UI
                    outAttrs.inputType=android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE or android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                    return connection
                }
            }
            enabled=parameters["enabled"]!=false
            browser=view;live.add(this)
            view.setBackgroundColor(Color.WHITE)
            view.isLongClickable=false;view.setOnLongClickListener { true }
            view.importantForAutofill=View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            view.settings.apply {
                javaScriptEnabled=true;allowFileAccess=false;allowContentAccess=false
                blockNetworkLoads=true;domStorageEnabled=false;databaseEnabled=false
                cacheMode=WebSettings.LOAD_NO_CACHE;mixedContentMode=WebSettings.MIXED_CONTENT_NEVER_ALLOW
                javaScriptCanOpenWindowsAutomatically=false;setSupportMultipleWindows(false)
                setGeolocationEnabled(false);mediaPlaybackRequiresUserGesture=true;textZoom=(parameters["textZoom"] as? Int ?: 100).coerceIn(50,300);saveFormData=false
            }
            CookieManager.getInstance().setAcceptThirdPartyCookies(view,false)
            WebViewCompat.addWebMessageListener(view,"BookStarkFileMessages",setOf(origin)) {
                _,message,source,mainFrame,proxy ->
                if(!retired && mainFrame && source.toString()==origin) {
                    try {
                        val raw=message.data ?: error("Empty")
                        check(raw.length<=13*1024*1024)
                        val json=JSONObject(raw)
                        if(json.optString("type")=="boot") {
                            check(reply==null && initialText!=null)
                            reply=proxy
                            proxy.postMessage(JSONObject().put("type","configure").put("lease",lease)
                                .put("generation",generation).put("content",initialText).put("enabled",enabled)
                                .put("english",parameters["english"]==true).toString())
                            initialText=null
                        } else if(json.optString("lease")==lease && json.optInt("generation",-1)==generation) {
                            when(json.optString("type")) {
                                "ready" -> {
                                    check(!ready);ready=true
                                    channel.invokeMethod("ready",mapOf("lease" to lease,"generation" to generation))
                                }
                                "changed" -> {
                                    check(ready && enabled)
                                    val bytes=json.getInt("bytes");check(bytes in 0..MAX)
                                    channel.invokeMethod("changed",mapOf("lease" to lease,"generation" to generation,
                                        "dirty" to json.getBoolean("dirty"),"bytes" to bytes))
                                }
                                "limit" -> channel.invokeMethod("limit",mapOf("lease" to lease,"generation" to generation))
                                "snapshot" -> if(json.optString("id")==pendingId) {
                                    val content=json.getString("content");check(valid(content))
                                    val held=pending;pending=null;pendingId=null
                                    timeout?.let { handler.removeCallbacks(it) };timeout=null
                                    held?.success(JSONObject().put("content",content).toString())
                                }
                                "focused" -> {
                                    val current=browser
                                    if(ready && enabled && current!=null) {
                                        current.requestFocus();current.post {
                                            if(!retired && enabled && browser===current) {
                                                val imm=context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                                                imm.restartInput(current);imm.showSoftInput(current,InputMethodManager.SHOW_IMPLICIT)
                                            }
                                        }
                                    }
                                }
                                else -> failed()
                            }
                        }
                    } catch(_: Exception) { failed() }
                }
            }
            view.webChromeClient=object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onConsoleMessage(message: ConsoleMessage?): Boolean=true
                override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback) { callback.invoke(origin,false,false) }
                override fun onShowFileChooser(view: WebView?, callback: ValueCallback<Array<Uri>>?, params: FileChooserParams?): Boolean { callback?.onReceiveValue(null);return true }
            }
            view.webViewClient=object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest): Boolean=true
                override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest): WebResourceResponse {
                    try {
                        check(!retired && own(request.url) && request.method=="GET")
                        val path=request.url.path ?: error("No path")
                        check(!request.isForMainFrame || path=="/host.html")
                        val asset=assets[path] ?: error("Blocked")
                        val bytes=context.assets.open(asset).use { it.readBytes() }
                        check(bytes.size<=MAX)
                        return WebResourceResponse(if(path.endsWith(".html"))"text/html" else "application/javascript","UTF-8",200,"OK",
                            mapOf("Content-Security-Policy" to csp,"Cache-Control" to "no-store",
                                "Referrer-Policy" to "no-referrer","X-Content-Type-Options" to "nosniff"),bytes.inputStream())
                    } catch(_: Exception) {
                        return WebResourceResponse("text/plain","UTF-8",403,"Forbidden",mapOf("Cache-Control" to "no-store"),byteArrayOf().inputStream())
                    }
                }
                override fun onReceivedSslError(view: WebView?, callback: SslErrorHandler, error: android.net.http.SslError?) { callback.cancel() }
            }
            view.setDownloadListener { _,_,_,_,_ -> }
            container.addView(view,FrameLayout.LayoutParams(-1,-1));view.loadUrl("$origin/host.html")
        } catch(_: Exception) { failed() }
    }
    private fun failPending() {
        val held=pending;pending=null;pendingId=null
        timeout?.let { handler.removeCallbacks(it) };timeout=null
        held?.error("editor_closed","Editor closed",null)
    }
    private fun retire() {
        if(retired) return
        retired=true;ready=false;enabled=false;reply=null;live.remove(this);failPending()
        browser?.let { view ->
            view.settings.javaScriptEnabled=false;view.stopLoading()
            WebViewCompat.removeWebMessageListener(view,"BookStarkFileMessages")
            container.removeView(view);view.destroy()
        }
        browser=null
    }
    override fun getView()=container
    override fun dispose() {
        if(disposed)return
        disposed=true;retire();channel.setMethodCallHandler(null)
    }
}
