package com.bookstark.bookstark_flutter

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import android.webkit.GeolocationPermissions
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.UUID

class LocalHtmlPreviewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        LocalHtmlPreviewView(context, viewId, messenger, args)
}

class PublicHtmlPreviewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        LocalHtmlPreviewView(context, viewId, messenger, args, publicMode = true)
}

/** In-memory, instance-origin resources only. No file paths or JS interfaces. */
class LocalHtmlPreviewView(
    context: Context,
    id: Int,
    messenger: BinaryMessenger,
    args: Any?,
    private val publicMode: Boolean = false
) : PlatformView {
    companion object {
        private val live = mutableSetOf<LocalHtmlPreviewView>()
        fun retireAll() { live.toList().forEach { it.retire() } }
        private val mimes = setOf("text/html", "text/css", "text/plain", "application/javascript",
            "application/json", "image/png", "image/jpeg", "image/gif", "image/webp", "image/svg+xml",
            "font/woff", "font/woff2", "font/ttf", "audio/mpeg", "audio/ogg", "video/mp4")
        private fun validPath(path: String): Boolean = path.isNotEmpty() && path.length <= 1024 &&
            !path.startsWith('/') && !path.endsWith('/') && !path.contains('\\') &&
            path.none { it.code < 32 || it.code == 127 } &&
            path.split('/').none { it.isEmpty() || it == "." || it == ".." }
    }
    private data class Asset(val bytes: ByteArray, val mime: String)
    private val container = FrameLayout(context)
    private val channel = MethodChannel(messenger, "bookstark/${if (publicMode) "public_html_preview" else "local_html_preview"}/$id")
    private val host = UUID.randomUUID().toString().replace("-", "") + ".bookstark-local.invalid"
    private val origin = "https://$host"
    private var lease = ""
    private var english = false
    private var attachmentBaseBytes = 0L
    private var attachmentBaseCount = 0
    private var localAttachmentRaster = false
    private var dynamicRaster = false
    private var scriptsEnabled = true
    private var browser: WebView? = null
    private val assets = mutableMapOf<String, Asset>()
    @Volatile private var retired = false
    private var disposed = false
    private var csp = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' $origin; " +
        "style-src 'unsafe-inline' $origin; img-src data: blob: $origin; font-src data: $origin; " +
        "media-src data: blob: $origin; connect-src $origin; frame-src $origin; child-src $origin; " +
        "worker-src 'none'; base-uri $origin; form-action 'none'; object-src 'none'"
    private var publicServer: URI? = null
    private val networkAssets = mutableMapOf<String, Asset>()
    private val requestedAssets = mutableSetOf<String>()
    private val failedAssets = mutableSetOf<String>()
    private var networkBytes = 0L
    private val waitingResources = mutableSetOf<CountDownLatch>()
    private val publicMimes = setOf("text/css", "application/javascript", "image/png", "image/jpeg",
        "image/gif", "image/webp", "image/svg+xml", "image/x-icon", "image/vnd.microsoft.icon",
        "font/woff", "font/woff2", "font/ttf", "font/otf", "application/font-woff", "application/vnd.ms-fontobject")
    private fun authorized(): Boolean = if (publicMode) HtmlPreviewSessionChannel.ownsPublicLease(lease)
        else HtmlPreviewSessionChannel.ownsLocalLease(lease)
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "retire") { retire(); result.success(null) }
            else result.notImplemented()
        }
        try {
            val params = args as? Map<*, *> ?: error("Missing preview arguments")
            lease = params["lease"] as? String ?: error("Missing local lease")
            english = params["english"] == true
            localAttachmentRaster = params["localAttachmentRaster"] == true
            check(!localAttachmentRaster || !publicMode)
            dynamicRaster = params["dynamicRaster"] == true
            check(!localAttachmentRaster || !dynamicRaster)
            scriptsEnabled = params["scriptsEnabled"] != false
            check(!dynamicRaster || (!publicMode && !scriptsEnabled))
            if (dynamicRaster) {
                csp = "default-src 'none'; script-src 'none'; " +
                    "style-src 'unsafe-inline'; img-src data: $origin; " +
                    "connect-src 'none'; frame-src 'none'; child-src 'none'; " +
                    "worker-src 'none'; form-action 'none'; base-uri $origin; object-src 'none'"
            }
            if (publicMode) {
                val server = URI(params["server"] as? String ?: error("Missing public server"))
                check(server.scheme in listOf("http", "https") && !server.host.isNullOrEmpty() &&
                    server.rawUserInfo == null && server.rawQuery == null && server.rawFragment == null &&
                    (server.port == -1 || server.port in 1..65535))
                publicServer = server
                val resourceOrigin = "${server.scheme}://${server.rawAuthority}"
                csp = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' $origin $resourceOrigin; " +
                    "style-src 'unsafe-inline' $origin $resourceOrigin; img-src data: blob: $origin $resourceOrigin; " +
                    "font-src data: $origin $resourceOrigin; media-src 'none'; connect-src 'none'; " +
                    "frame-src 'none'; child-src 'none'; worker-src 'none'; form-action 'none'; " +
                    "base-uri $resourceOrigin; object-src 'none'"
            }
            if (localAttachmentRaster) csp = csp.replace("img-src data: blob: $origin;", "img-src data: blob: $origin bookstark-attachment:;")
            check(authorized())
            val source = params["source"] as? String ?: error("Missing local HTML")
            val sourceBytes = source.toByteArray(Charsets.UTF_8)
            check(sourceBytes.size <= 5 * 1024 * 1024 + 16 * 1024) // Preview wrapper allowance; raw source stays <= 5 MiB.
            assets["index.html"] = Asset(sourceBytes, "text/html")
            val resources = params["resources"] as? List<*> ?: emptyList<Any>()
            check(!dynamicRaster || resources.isEmpty())
            check(resources.size <= 32)
            var total = 0L
            for (entry in resources) {
                val row = entry as? Map<*, *> ?: error("Invalid resource")
                val path = row["path"] as? String ?: error("Invalid resource path")
                val mime = row["mime"] as? String ?: error("Invalid resource type")
                val bytes = row["bytes"] as? ByteArray ?: error("Invalid resource bytes")
                check(validPath(path) && path != "index.html" && !assets.containsKey(path))
                check(mime in mimes && bytes.size <= 5 * 1024 * 1024)
                total += bytes.size
                check(total <= 20 * 1024 * 1024)
                assets[path] = Asset(bytes.copyOf(), mime)
            }
            if (localAttachmentRaster) {
                attachmentBaseBytes = total
                attachmentBaseCount = resources.size
            }
            live.add(this)
            val view = WebView(context)
            browser = view
            view.setBackgroundColor(Color.WHITE)
            view.settings.apply {
                javaScriptEnabled = false
                allowFileAccess = false
                allowContentAccess = false
                blockNetworkLoads = true
                domStorageEnabled = false
                databaseEnabled = false
                cacheMode = WebSettings.LOAD_NO_CACHE
                mixedContentMode = if (publicMode) WebSettings.MIXED_CONTENT_ALWAYS_ALLOW else WebSettings.MIXED_CONTENT_NEVER_ALLOW
                javaScriptCanOpenWindowsAutomatically = false
                setSupportMultipleWindows(false)
                mediaPlaybackRequiresUserGesture = true
                setGeolocationEnabled(false)
                textZoom = (context.resources.configuration.fontScale * 100).toInt().coerceIn(50, 300)
                useWideViewPort = true
                loadWithOverviewMode = true
                builtInZoomControls = true
                displayZoomControls = false
            }
            view.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback) {
                    callback.invoke(origin, false, false)
                }
            }
            view.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest): WebResourceResponse {
                    if (retired || !authorized() || request.method != "GET") return denied()
                    if (request.url.scheme == "bookstark-attachment") {
                        return if (localAttachmentRaster && !request.isForMainFrame) attachmentRaster(request.url) else denied()
                    }
                    if (!own(request.url)) return if (publicMode) publicResource(request.url) else denied()
                    val path = request.url.path?.removePrefix("/") ?: return denied()
                    val resource = synchronized(assets) { assets[path] }
                    if (resource != null) return response(resource)
                    return if (dynamicRaster) localRaster(request.url) else denied()
                }
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest): Boolean {
                    if (retired || !authorized()) return true
                    if (request.url.scheme == "bookstark-attachment") {
                        if (localAttachmentRaster && !publicMode && request.isForMainFrame &&
                            request.hasGesture() && validAttachmentUri(request.url)) {
                            channel.invokeMethod("localAttachmentLink",
                                mapOf("lease" to lease, "url" to request.url.toString()))
                        }
                        return true
                    }
                    if (own(request.url)) return false
                    if (request.isForMainFrame && request.hasGesture() &&
                        request.url.scheme in setOf("https", "http") &&
                        !request.url.host.isNullOrEmpty() && request.url.userInfo == null) {
                        channel.invokeMethod("externalLink", mapOf("lease" to lease, "url" to request.url.toString()))
                    }
                    return true
                }
            }
            view.setDownloadListener { _, _, _, _, _ -> /* No automatic writes or native downloads. */ }
            container.addView(view, FrameLayout.LayoutParams(-1, -1))
            check(authorized())
            view.settings.javaScriptEnabled = scriptsEnabled
            view.loadUrl("$origin/index.html")
        } catch (_: Exception) { retire() }
    }
    private fun response(resource: Asset): WebResourceResponse {
        val encoding = if (resource.mime.startsWith("text/") || resource.mime in
            setOf("application/javascript", "application/json", "image/svg+xml")) "UTF-8" else null
        return WebResourceResponse(resource.mime, encoding, 200, "OK", mapOf(
            "Content-Security-Policy" to csp, "Cache-Control" to "no-store",
            "X-Content-Type-Options" to "nosniff", "Referrer-Policy" to "no-referrer",
            "Access-Control-Allow-Origin" to "*"
        ), resource.bytes.inputStream())
    }
    private fun publicResource(uri: Uri): WebResourceResponse {
        val server = publicServer ?: return denied()
        fun port(scheme: String?, value: Int): Int = if (value >= 0) value else if (scheme == "https") 443 else 80
        val root = server.path.orEmpty().trimEnd('/')
        if (uri.scheme != server.scheme || !uri.host.orEmpty().equals(server.host, ignoreCase = true) ||
            port(uri.scheme, uri.port) != port(server.scheme, server.port) || uri.userInfo != null ||
            uri.fragment != null || !(uri.path.orEmpty().startsWith("$root/static/") ||
                uri.path.orEmpty().startsWith("$root/upload-files/") ||
                (root.isNotEmpty() && (uri.path.orEmpty().startsWith("/static/") ||
                    uri.path.orEmpty().startsWith("/upload-files/"))))) return denied()
        return requestResource(uri.toString(), "resource", publicMimes)
    }
    private fun requestResource(key: String, method: String, allowedMimes: Set<String>): WebResourceResponse {
        synchronized(networkAssets) {
            if (retired || !authorized() || key in failedAssets) return denied()
            networkAssets[key]?.let { return response(it) }
            if (key !in requestedAssets && requestedAssets.size + attachmentBaseCount >= 32) return denied()
            requestedAssets.add(key)
        }
        if (Looper.myLooper() == Looper.getMainLooper()) return denied()
        val ready = CountDownLatch(1)
        synchronized(waitingResources) { if (retired) return denied(); waitingResources.add(ready) }
        var value: Asset? = null
        Handler(Looper.getMainLooper()).post {
            if (retired || !authorized()) ready.countDown()
            else channel.invokeMethod(method, mapOf("lease" to lease, "url" to key), object : MethodChannel.Result {
                override fun success(result: Any?) {
                    try {
                        val row = result as? Map<*, *> ?: error("Missing public resource")
                        val bytes = row["bytes"] as? ByteArray ?: error("Missing public bytes")
                        val mime = row["mime"] as? String ?: error("Missing public media")
                        check(bytes.size <= 5 * 1024 * 1024 && mime in allowedMimes)
                        synchronized(networkAssets) {
                            if (!retired && authorized()) {
                                val cached = networkAssets[key]
                                if (cached != null) value = cached
                                else if (networkBytes + attachmentBaseBytes + bytes.size <= 20 * 1024 * 1024) {
                                    value = Asset(bytes, mime)
                                    networkAssets[key] = value!!
                                    networkBytes += bytes.size
                                }
                            }
                        }
                    } catch (_: Exception) { synchronized(networkAssets) { failedAssets.add(key) } }
                    finally { ready.countDown() }
                }
                override fun error(code: String, message: String?, details: Any?) {
                    synchronized(networkAssets) { failedAssets.add(key) }; ready.countDown()
                }
                override fun notImplemented() { synchronized(networkAssets) { failedAssets.add(key) }; ready.countDown() }
            })
        }
        return try {
            if (!ready.await(15, TimeUnit.SECONDS) || retired || !authorized()) denied()
            else value?.let { response(it) } ?: denied()
        } catch (_: InterruptedException) { Thread.currentThread().interrupt(); denied() }
        finally { synchronized(waitingResources) { waitingResources.remove(ready) } }
    }
    private fun validAttachmentUri(uri: Uri): Boolean {
        if (uri.scheme != "bookstark-attachment" ||
            !uri.host.isNullOrEmpty() || uri.userInfo != null || uri.port != -1 ||
            uri.query != null || uri.fragment != null || uri.toString().length > 2048) return false
        val segments = uri.pathSegments
        if (segments.size != 2 || !Regex("^[a-f0-9]{32}$").matches(segments[0])) return false
        val name = segments[1]
        return name.isNotEmpty() && name.length <= 255 && name != "." && name != ".." &&
            !name.contains('/') && !name.contains('\\') &&
            name.none { it.code < 32 || it.code == 127 }
    }
    private fun attachmentRaster(uri: Uri): WebResourceResponse {
        if (!localAttachmentRaster || publicMode || !validAttachmentUri(uri)) return denied()
        return requestResource(uri.toString(), "localAttachmentRaster",
            setOf("image/png", "image/jpeg", "image/gif", "image/webp"))
    }
    private fun localRaster(uri: Uri): WebResourceResponse {
        if (!dynamicRaster || publicMode || !own(uri) || uri.fragment != null) return denied()
        val path = uri.encodedPath ?: return denied()
        if (!path.startsWith("/upload-files/") || path.length > 4096) return denied()
        val key = path + (uri.encodedQuery?.let { "?$it" } ?: "")
        return requestResource(key, "raster", setOf("image/png", "image/jpeg", "image/gif", "image/webp"))
    }
    private fun own(uri: Uri): Boolean = uri.scheme == "https" && uri.host == host && uri.port == -1 && uri.userInfo == null
    private fun denied() = WebResourceResponse("text/plain", "UTF-8", 403, "Blocked",
        mapOf("Cache-Control" to "no-store", "Content-Security-Policy" to "default-src 'none'"), byteArrayOf().inputStream())
    fun retire() {
        if (retired) return
        retired = true
        synchronized(waitingResources) { waitingResources.forEach { it.countDown() }; waitingResources.clear() }
        browser?.apply {
            settings.javaScriptEnabled = false
            stopLoading()
            loadUrl("about:blank")
            clearHistory()
            clearCache(true)
            removeAllViews()
            destroy()
        }
        browser = null
        synchronized(assets) { assets.clear() }
        synchronized(networkAssets) { networkAssets.clear(); requestedAssets.clear(); failedAssets.clear(); networkBytes = 0 }
        live.remove(this)
        container.removeAllViews()
        container.addView(TextView(container.context).apply {
            text = if (english) "Interactive preview closed. Reload to continue." else "交互预览已关闭，请重新加载。"
            setTextColor(Color.DKGRAY)
            setPadding(24, 24, 24, 24)
        })
    }
    override fun getView(): android.view.View = container
    override fun dispose() {
        if (disposed) return
        disposed = true
        retire()
        channel.setMethodCallHandler(null)
    }
}
