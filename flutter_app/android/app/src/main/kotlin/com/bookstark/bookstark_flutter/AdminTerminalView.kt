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

class AdminTerminalFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        AdminTerminalView(context, viewId, messenger, args)
}

/** Dedicated packaged xterm, no account network, storage, clipboard or file API. */
class AdminTerminalView(private val context: Context, id: Int,
    messenger: BinaryMessenger, args: Any?) : PlatformView {
    companion object {
        private val live = mutableSetOf<AdminTerminalView>()
        fun retireAll() { live.toList().forEach { it.retire() } }
        private const val VENDOR = "flutter_assets/assets/complex_editors/static/"
        private val assets = mapOf(
            "/host.html" to "flutter_assets/assets/admin_terminal/host.html",
            "/host.js" to "flutter_assets/assets/admin_terminal/host.js",
            "/xterm.js" to VENDOR + "js/xterm/xterm.js",
            "/addon-fit.js" to VENDOR + "js/xterm/addon-fit.js",
            "/xterm.css" to VENDOR + "css/xterm/xterm.css")
    }
    private val container = FrameLayout(context)
    private val channel = MethodChannel(messenger, "bookstark/admin_terminal/$id")
    private val host = UUID.randomUUID().toString().replace("-", "") + ".bookstark-terminal.invalid"
    private val origin = "https://$host"
    private val handler = Handler(Looper.getMainLooper())
    private var browser: WebView? = null
    private var reply: JavaScriptReplyProxy? = null
    private var lease = ""
    private var generation = -1
    @Volatile private var retired = false
    private var disposed = false
    private var ready = false
    private var terminalEnabled = false
    private var pending: MethodChannel.Result? = null
    private var pendingId: String? = null
    private var timeout: Runnable? = null
    private fun own(uri: Uri) = uri.scheme == "https" && uri.host == host &&
        uri.port == -1 && uri.userInfo == null && uri.query == null && uri.fragment == null
    private val csp = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; " +
        "connect-src 'none'; img-src 'none'; font-src 'none'; frame-src 'none'; worker-src 'none'; " +
        "object-src 'none'; base-uri 'none'; form-action 'none'"

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "retire") { retire(); result.success(null) }
            else if (call.method != "command") result.notImplemented()
            else if (retired || !ready || call.argument<String>("lease") != lease ||
                call.argument<Int>("generation") != generation) result.error("terminal_closed", "Terminal closed", null)
            else {
                try {
                    val type = call.argument<String>("type")
                    check(type in setOf("output", "enabled", "focus", "shortcut"))
                    val message = JSONObject().put("type", type).put("lease", lease).put("generation", generation)
                    when (type) {
                        "output" -> {
                            val data = call.argument<String>("data") ?: error("No output")
                            check(data.toByteArray(Charsets.UTF_8).size <= 65536 && pending == null)
                            val commandId = UUID.randomUUID().toString()
                            message.put("data", data).put("id", commandId)
                            pending = result; pendingId = commandId
                            timeout = Runnable { failPending(); retire() }.also { handler.postDelayed(it, 10000) }
                        }
                        "enabled" -> {
                            terminalEnabled = call.argument<Boolean>("value") == true
                            message.put("value", terminalEnabled)
                        }
                        "focus" -> {
                            check(terminalEnabled)
                            browser?.requestFocus()
                        }
                        "shortcut" -> {
                            val key = call.argument<String>("key")
                            check(key in setOf("escape","tab","interrupt","up","down","left","right"))
                            message.put("key", key)
                        }
                    }
                    reply?.postMessage(message.toString()) ?: error("No bridge")
                    if (type != "output") result.success(null)
                } catch (_: Exception) {
                    if (pending === result) failPending()
                    else result.error("terminal_protocol", "Terminal command unavailable", null)
                }
            }
        }
        try {
            val parameters = args as? Map<*, *> ?: error("No parameters")
            lease = parameters["lease"] as? String ?: error("No lease")
            generation = parameters["generation"] as? Int ?: error("No generation")
            check(lease.matches(Regex("[a-f0-9]{64}")) && generation >= 0)
            check(WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER))
            val view = object : WebView(context) {
                override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? {
                    val connection = super.onCreateInputConnection(outAttrs)
                    outAttrs.imeOptions = outAttrs.imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING or EditorInfo.IME_FLAG_NO_EXTRACT_UI
                    outAttrs.inputType = android.text.InputType.TYPE_CLASS_TEXT or
                        android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                        android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                    return connection
                }
            }
            browser = view
            live.add(this)
            view.setBackgroundColor(Color.rgb(8,11,16))
            view.isLongClickable = false
            view.setOnLongClickListener { true }
            view.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            view.settings.apply {
                javaScriptEnabled = true
                allowFileAccess = false; allowContentAccess = false
                blockNetworkLoads = true; domStorageEnabled = false; databaseEnabled = false
                cacheMode = WebSettings.LOAD_NO_CACHE
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                javaScriptCanOpenWindowsAutomatically = false
                setSupportMultipleWindows(false); setGeolocationEnabled(false)
                mediaPlaybackRequiresUserGesture = true; textZoom = 100
                saveFormData = false
            }
            CookieManager.getInstance().setAcceptThirdPartyCookies(view, false)
            WebViewCompat.addWebMessageListener(view, "BookStarkTerminalMessages", setOf(origin)) {
                _, message, source, mainFrame, proxy ->
                if (!retired && mainFrame && source.toString() == origin) {
                    try {
                        val raw = message.data ?: error("Empty")
                        check(raw.length <= 400000)
                        val json = JSONObject(raw)
                        if (json.optString("type") == "boot") {
                            check(reply == null)
                            reply = proxy
                            proxy.postMessage(JSONObject().put("type","configure").put("lease",lease)
                                .put("generation",generation).put("scrollback",(parameters["scrollback"] as? Int ?: 5000).coerceIn(500,50000))
                                .put("english",parameters["english"] == true).toString())
                        } else if (json.optString("lease") == lease && json.optInt("generation", -1) == generation) {
                            when (json.optString("type")) {
                                "ready" -> { ready = true; channel.invokeMethod("ready", mapOf("lease" to lease,"generation" to generation)) }
                                "focused" -> {
                                    // DOM focus alone from a Flutter toolbar is not an Android
                                    // user gesture. Establish the actual WebView input target,
                                    // then ask IMM after the DOM has acknowledged textarea focus.
                                    val view = browser
                                    if (ready && terminalEnabled && view != null) {
                                        view.requestFocus()
                                        view.post {
                                            if (!retired && terminalEnabled && browser === view) {
                                                val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                                                imm.restartInput(view)
                                                imm.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT)
                                            }
                                        }
                                    }
                                }
                                "input" -> {
                                    val data = json.getString("data")
                                    check(data.toByteArray(Charsets.UTF_8).size <= 65536)
                                    channel.invokeMethod("input", mapOf("lease" to lease,"generation" to generation,"data" to data))
                                }
                                "resize" -> {
                                    val cols = json.getInt("cols"); val rows = json.getInt("rows")
                                    check(cols in 1..500 && rows in 1..300)
                                    channel.invokeMethod("resize", mapOf("lease" to lease,"generation" to generation,"cols" to cols,"rows" to rows))
                                }
                                "written" -> if (json.optString("id") == pendingId) {
                                    val held = pending
                                    pending = null; pendingId = null
                                    timeout?.let { handler.removeCallbacks(it) }; timeout = null
                                    held?.success(null)
                                }
                                else -> { retire(); channel.invokeMethod("failed", mapOf("lease" to lease,"generation" to generation)) }
                            }
                        }
                    } catch (_: Exception) { retire() }
                }
            }
            view.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onConsoleMessage(message: ConsoleMessage?): Boolean = true
                override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback) { callback.invoke(origin,false,false) }
                override fun onShowFileChooser(view: WebView?, callback: ValueCallback<Array<Uri>>?, params: FileChooserParams?): Boolean { callback?.onReceiveValue(null); return true }
            }
            view.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest): Boolean = true
                override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest): WebResourceResponse {
                    try {
                        check(!retired && own(request.url) && request.method == "GET")
                        val path = request.url.path ?: error("No path")
                        check(!request.isForMainFrame || path == "/host.html")
                        val asset = assets[path] ?: error("Blocked")
                        val bytes = context.assets.open(asset).use { it.readBytes() }
                        check(bytes.size <= 2*1024*1024)
                        val mime = when(path.substringAfterLast('.')) { "html" -> "text/html"; "css" -> "text/css"; else -> "application/javascript" }
                        return WebResourceResponse(mime,"UTF-8",200,"OK",
                            mapOf("Content-Security-Policy" to csp,"Cache-Control" to "no-store",
                                "Referrer-Policy" to "no-referrer","X-Content-Type-Options" to "nosniff"),bytes.inputStream())
                    } catch (_: Exception) {
                        return WebResourceResponse("text/plain","UTF-8",403,"Forbidden",mapOf("Cache-Control" to "no-store"),byteArrayOf().inputStream())
                    }
                }
                override fun onReceivedSslError(view: WebView?, callback: SslErrorHandler, error: android.net.http.SslError?) { callback.cancel() }
            }
            view.setDownloadListener { _,_,_,_,_ -> }
            container.addView(view, FrameLayout.LayoutParams(-1,-1))
            view.loadUrl("$origin/host.html")
        } catch (_: Exception) { retire() }
    }
    private fun failPending() {
        val held = pending
        pending = null; pendingId = null
        timeout?.let { handler.removeCallbacks(it) }; timeout = null
        held?.error("terminal_closed","Terminal closed",null)
    }
    private fun retire() {
        if (retired) return
        retired = true; ready = false; terminalEnabled = false; reply = null; live.remove(this)
        failPending()
        browser?.let { view ->
            view.settings.javaScriptEnabled = false; view.stopLoading()
            WebViewCompat.removeWebMessageListener(view,"BookStarkTerminalMessages")
            container.removeView(view); view.destroy()
        }
        browser = null
    }
    override fun getView() = container
    override fun dispose() {
        if (disposed) return
        disposed = true; retire(); channel.setMethodCallHandler(null)
    }
}
