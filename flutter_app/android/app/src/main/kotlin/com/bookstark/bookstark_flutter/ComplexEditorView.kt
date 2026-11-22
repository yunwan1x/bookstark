package com.bookstark.bookstark_flutter

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.*
import android.widget.FrameLayout
import android.widget.TextView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.security.MessageDigest
import java.util.UUID

/** Separate account-owned document capability, still anonymous resource reads. */
class Owned15GenerationFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, generationResourceMode = true)
}

class OwnedComplexFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, ownedResourceMode = true)
}

class ComplexEditorFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args)
}

/** Separate read-only typed mode. Does not widen SharedMarkdownFactory. */
class PublicComplexReadOnlyFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, publicMode = true, publicComplexReadOnly = true)
}

class PublicMarkdownFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, publicMode = true)
}

/** Packaged trusted engines, opaque sandboxed HTML previews, and no network or
 * filesystem API. A main-frame, exact-origin message listener carries bounded
 * commands. User content is transferred in memory after the host is ready. */
class SharedMarkdownFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, publicMode = true, sharedEditing = true)
}

class SharedComplexFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, publicMode = true, sharedEditing = true, sharedComplexEditing = true)
}

class LocalMarkdownFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, localMarkdownImages = true)
}

class LocalRichdocFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, localRichdocImages = true)
}

class LocalMindmapFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, localMindmapImages = true)
}

class LocalDrawingFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, localDrawingImages = true)
}

class LocalPresentationFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ComplexEditorView(context, viewId, messenger, args, localPresentationImages = true)
}

class ComplexEditorView(private val context: Context, id: Int,
    messenger: BinaryMessenger, args: Any?, private val publicMode: Boolean = false, private val sharedEditing: Boolean = false, private val publicComplexReadOnly: Boolean = false, private val sharedComplexEditing: Boolean = false, private val localMarkdownImages: Boolean = false, private val ownedResourceMode: Boolean = false, private val generationResourceMode: Boolean = false, private val localRichdocImages: Boolean = false, private val localMindmapImages: Boolean = false, private val localDrawingImages: Boolean = false, private val localPresentationImages: Boolean = false) : PlatformView {
    companion object {
        private val live = mutableSetOf<ComplexEditorView>()
        fun retireAll() { live.toList().forEach { it.retire() } }
        fun sourceIoAuthorization(lease: String, generation: Int, exportHash: String? = null, exportBytes: Long? = null): (() -> Boolean)? {
            val view = live.firstOrNull { it.lease == lease &&
                (it.sourceIoAllowed(generation) || exportHash != null && it.reviewExportAllowed(generation, exportHash, exportBytes)) } ?: return null
            return { view.sourceIoAllowed(generation) ||
                exportHash != null && view.reviewExportAllowed(generation, exportHash, exportBytes) }
        }
        fun ownsReviewExport(lease: String, generation: Int, hash: String, bytes: Long) =
            live.any { it.lease == lease && it.reviewExportAllowed(generation, hash, bytes) }
        private const val ROOT = "flutter_assets/assets/complex_editors/"
        private val hostFiles = setOf("host.html", "host.js", "local-drawing.js", "local-presentation.js", "reading13.js", "host-merge.js", "markdown-editor.js", "markdown-preview.js",
            "memory-storage.js", "memory-indexeddb.js")
        private val commands = setOf("bindPublicSelection", "capturePublicSelection", "bindReading", "captureReading", "restoreReading", "beginLoad", "appendLoad", "abortLoad", "commitLoad", "state",
            "beginSnapshot", "readSnapshot", "endSnapshot", "insertImageSnapshot", "authorizeLocalHtmlAttachments", "insertLocalHtmlAttachmentSnapshot", "insertLocalRichdocImageSnapshot", "insertLocalMindmapImageSnapshot", "insertLocalDrawingImageSnapshot", "insertLocalPresentationImageSnapshot", "insertMarkdownSnapshot", "acknowledgeSnapshot", "setInputLocked", "setMarkdownByteLimit")
    }
    private data class Pending(val result: MethodChannel.Result, val timeout: Runnable)
    private val container = FrameLayout(context)
    private val channel = MethodChannel(messenger, "bookstark/${if(generationResourceMode) "owned15_generation_view" else if(ownedResourceMode) "owned_complex_view" else if(sharedComplexEditing) "shared_complex_view" else if(publicComplexReadOnly) "public_complex_readonly_view" else if(localPresentationImages) "local_presentation_view" else if(localDrawingImages) "local_drawing_view" else if(localMindmapImages) "local_mindmap_view" else if(localRichdocImages) "local_richdoc_view" else if(localMarkdownImages) "local_markdown_view" else if(sharedEditing) "shared_markdown_view" else if(publicMode) "public_markdown_view" else "complex_editor_view"}/$id")
    private val host = UUID.randomUUID().toString().replace("-", "") + ".bookstark-editor.invalid"
    private val origin = "https://$host"
    private val handler = Handler(Looper.getMainLooper())
    private val pending = mutableMapOf<String, Pending>()
    private var ownedResources: OwnedComplexResources? = null
    private var generationResources: Owned15GenerationResources? = null
    private var ownedServer: URI? = null
    private var browser: WebView? = null
    private var lease = ""
    @Volatile private var retired = false
    private var disposed = false
    private var readingGeneration = -1
    private var readingKind = ""
    private var readingReadOnly = false
    private var booted = false
    private var localHtmlAttachmentScope: String? = null
    private var localHtmlAttachmentEpoch = -1L
    private var localHtmlAttachmentGeneration = -1
    private var localHtmlAttachmentIdentity: String? = null
    private var localHtmlAttachmentSnapshot: String? = null
    private var localHtmlAttachmentSource: String? = null
    private fun clearLocalHtmlAttachmentGrant() {
        localHtmlAttachmentScope = null
        localHtmlAttachmentEpoch = -1L
        localHtmlAttachmentGeneration = -1
        localHtmlAttachmentIdentity = null
        localHtmlAttachmentSnapshot = null
        localHtmlAttachmentSource = null
    }
    @Volatile private var ioGeneration = -1
    @Volatile private var ioEditable = false
    @Volatile private var ownedMarkdownIoRequested = false
    private fun sourceIoAllowed(generation: Int) = (sharedComplexEditing || !publicMode && !publicComplexReadOnly && !sharedEditing) && (!localMarkdownImages || ownedMarkdownIoRequested) &&
        !retired && !disposed && ioEditable && generation > 0 && ioGeneration == generation && authorized()
    private var reviewExportHash: String? = null
    private var reviewExportBytes: Long? = null
    private var reviewCommitCommandId: String? = null
    private var reviewReadyGeneration = -1
    private fun reviewExportAllowed(generation: Int, hash: String, bytes: Long?) =
        !publicMode && !publicComplexReadOnly && !sharedEditing && !sharedComplexEditing &&
        !retired && !disposed && authorized() && readingReadOnly &&
        readingKind == "markdown" && generation > 0 && readingGeneration == generation &&
        reviewReadyGeneration == generation &&
        reviewExportHash == hash && bytes != null && reviewExportBytes == bytes && hash.matches(Regex("[a-f0-9]{64}"))
    private var publicLinkChecking = false
    private var publicLinkSequence = 0L
    private var manifest = JSONObject()
    private var publicServer: URI? = null
    private var publicResources: PublicMarkdownResources? = null
    private var localImages: LocalMarkdownImageResources? = null
    private var localRichdocResources: LocalRichdocImageResources? = null
    private var localRichdocScope: String? = null
    private var localRichdocSource: String? = null
    private var localDrawingResources: LocalDrawingImageResources? = null
    private var localDrawingScope: String? = null
    private var localDrawingSource: String? = null
    private var localPresentationResources: LocalPresentationImageResources? = null
    private var localPresentationScope: String? = null
    private var localPresentationSource: String? = null
    private var localMindmapResources: LocalMindmapImageResources? = null
    private var localMindmapScope: String? = null
    private var localMindmapSource: String? = null
    private var csp = "default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; " +
        "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; " +
        "connect-src 'self'; frame-src 'self' blob:; worker-src 'self' blob:; " +
        "base-uri 'none'; form-action 'none'; object-src 'none'"
    private fun debugStage(stage: String) {
        if ((context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            android.util.Log.d("BookStarkComplex", stage)
        }
    }
    private fun authorized() = !retired && (if(publicMode) HtmlPreviewSessionChannel.ownsPublicLease(lease)
        else HtmlPreviewSessionChannel.ownsLocalLease(lease))
    private fun own(uri: Uri) = uri.scheme == "https" && uri.host == host &&
        uri.port == -1 && uri.userInfo == null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "retire" -> { retire(); result.success(null) }
                "command" -> {
                    val name = call.argument<String>("name")
                    val arguments = call.argument<List<Any?>>("arguments")
                    if (name == "reviewExportIdentity") {
                        val hash = arguments?.getOrNull(0) as? String
                        val bytes = (arguments?.getOrNull(1) as? Number)?.toLong()
                        if (hash != null && arguments?.size == 2 && reviewExportAllowed(readingGeneration, hash, bytes)) {
                            result.success(mapOf("lease" to lease, "generation" to readingGeneration, "sha256" to hash, "bytes" to bytes))
                        } else result.error("review_export_denied", "Owned review export unavailable", null)
                    }
                    else if (name == "sourceIoIdentity") {
                        if (sourceIoAllowed(ioGeneration) && arguments?.isEmpty() == true) {
                            result.success(mapOf("lease" to lease, "generation" to ioGeneration))
                        } else result.error("source_io_denied", "Source file I/O is unavailable", null)
                    }
                    else if (name == "retire") { retire(); result.success(null) }
                    else if (!authorized() || !booted || name !in commands || arguments == null ||
                        arguments.size > 5 || pending.size >= 4 || !publicCommand(name, arguments)) {
                        val safeCode = if (name == "insertLocalMindmapImageSnapshot") {
                            when {
                                !authorized() || !booted -> "mindmap_preflight_context"
                                name !in commands || arguments == null || arguments.size > 5 ->
                                    "mindmap_preflight_args"
                                pending.size >= 4 -> "mindmap_preflight_queue"
                                else -> mindmapImagePreflight(arguments) ?: "mindmap_preflight_gate"
                            }
                        } else null
                        result.error("editor_unavailable", "Editor command unavailable", safeCode)
                    } else dispatch(name!!, arguments, result)
                }
                else -> result.notImplemented()
            }
        }
        try {
            val params = args as? Map<*, *> ?: error("Missing editor arguments")
            lease = params["lease"] as? String ?: error("Missing lease")
            if(localDrawingImages) {
                check(!publicMode && !publicComplexReadOnly && !sharedEditing &&
                    !sharedComplexEditing && !localMarkdownImages &&
                    !ownedResourceMode && !generationResourceMode &&
                    !localRichdocImages && !localMindmapImages && !localPresentationImages)
                check(params.keys == setOf("lease", "resourceScope", "sourceDigest"))
                val scope = params["resourceScope"] as? String ?: error("Missing local scope")
                val source = params["sourceDigest"] as? String ?: error("Missing local source")
                check(scope.matches(Regex("[a-f0-9]{64}")) &&
                    source.matches(Regex("[a-f0-9]{64}")))
                localDrawingScope = scope
                localDrawingSource = source
                localDrawingResources = LocalDrawingImageResources(
                    channel, lease, scope, source, host, ::authorized)
            }
            if(localPresentationImages) {
                check(!publicMode && !publicComplexReadOnly && !sharedEditing &&
                    !sharedComplexEditing && !localMarkdownImages &&
                    !ownedResourceMode && !generationResourceMode &&
                    !localRichdocImages && !localMindmapImages && !localDrawingImages)
                check(params.keys == setOf("lease", "resourceScope", "sourceDigest"))
                val scope = params["resourceScope"] as? String ?: error("Missing local scope")
                val source = params["sourceDigest"] as? String ?: error("Missing local source")
                check(scope.matches(Regex("[a-f0-9]{64}")) &&
                    source.matches(Regex("[a-f0-9]{64}")))
                localPresentationScope = scope
                localPresentationSource = source
                localPresentationResources = LocalPresentationImageResources(
                    channel, lease, scope, source, host, ::authorized)
            }
            if(localRichdocImages) {
                check(!publicMode && !publicComplexReadOnly && !sharedEditing &&
                    !sharedComplexEditing && !localMarkdownImages &&
                    !ownedResourceMode && !generationResourceMode && !localMindmapImages && !localDrawingImages && !localPresentationImages)
                check(params.keys == setOf("lease", "resourceScope", "sourceDigest"))
                val scope = params["resourceScope"] as? String ?: error("Missing local scope")
                val source = params["sourceDigest"] as? String ?: error("Missing local source")
                check(scope.matches(Regex("[a-f0-9]{64}")) &&
                    source.matches(Regex("[a-f0-9]{64}")))
                localRichdocScope = scope
                localRichdocSource = source
                localRichdocResources = LocalRichdocImageResources(
                    channel, lease, scope, source, ::authorized)
                csp = csp.replace("img-src 'self' data: blob:;",
                    "img-src 'self' data: blob: bookstark-attachment:;")
            }
            if(localMindmapImages) {
                check(!publicMode && !publicComplexReadOnly && !sharedEditing &&
                    !sharedComplexEditing && !localMarkdownImages &&
                    !ownedResourceMode && !generationResourceMode && !localRichdocImages && !localDrawingImages && !localPresentationImages)
                check(params.keys == setOf("lease", "resourceScope", "sourceDigest"))
                val scope = params["resourceScope"] as? String ?: error("Missing local scope")
                val source = params["sourceDigest"] as? String ?: error("Missing local source")
                check(scope.matches(Regex("[a-f0-9]{64}")) &&
                    source.matches(Regex("[a-f0-9]{64}")))
                localMindmapScope = scope
                localMindmapSource = source
                localMindmapResources = LocalMindmapImageResources(
                    channel, lease, scope, source, ::authorized)
                csp = csp.replace("img-src 'self' data: blob:;",
                    "img-src 'self' data: blob: bookstark-attachment:;")
            }
            if(generationResourceMode) {
                check(!publicMode && !sharedEditing && !publicComplexReadOnly &&
                    !sharedComplexEditing && !localMarkdownImages && !ownedResourceMode)
                check(params.keys == setOf("lease", "resourceScope"))
                val scope = params["resourceScope"] as? String ?: error("Missing resource scope")
                check(scope.matches(Regex("[a-f0-9]{64}")))
                generationResources = Owned15GenerationResources(channel, lease, scope, ::authorized)
            }
            if(ownedResourceMode) {
                check(!publicMode && !sharedEditing && !sharedComplexEditing && !localMarkdownImages)
                check(params.keys == setOf("lease", "server", "resourceScope"))
                val server = URI(params["server"] as? String ?: error("Missing resource server"))
                val scope = params["resourceScope"] as? String ?: error("Missing resource scope")
                check(server.scheme in setOf("http", "https") && !server.host.isNullOrEmpty() &&
                    server.rawUserInfo == null && server.rawQuery == null && server.rawFragment == null &&
                    (server.port == -1 || server.port in 1..65535) && scope.matches(Regex("[a-f0-9]{64}")))
                ownedServer = server
                val resourceOrigin = "${server.scheme}://${server.rawAuthority}"
                csp = csp.replace("img-src 'self' data: blob:;", "img-src 'self' data: blob: $resourceOrigin;")
                    .replace("font-src 'self' data:;", "font-src 'self' data: $resourceOrigin;")
                    .replace("style-src 'self' 'unsafe-inline';", "style-src 'self' 'unsafe-inline' $resourceOrigin;")
                ownedResources = OwnedComplexResources(server, channel, lease, scope, ::authorized)
            }
            if(publicMode) {
                check(params.keys == setOf("lease", "server"))
                val server = URI(params["server"] as? String ?: error("Missing public server"))
                check(server.scheme in setOf("http", "https") && !server.host.isNullOrEmpty() &&
                    server.rawUserInfo == null && server.rawQuery == null && server.rawFragment == null &&
                    (server.port == -1 || server.port in 1..65535))
                publicServer = server
                val resources = "${server.scheme}://${server.rawAuthority}"
                csp = "default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; " +
                    "style-src 'self' 'unsafe-inline' $resources; img-src 'self' data: blob: $resources; " +
                    "font-src 'self' data: $resources; connect-src 'self'; frame-src 'self' blob:; " +
                    "worker-src 'none'; base-uri $resources; form-action 'none'; object-src 'none'"
                if(sharedComplexEditing) csp = csp.replace("worker-src 'none';", "worker-src 'self' blob:;")
                publicResources = PublicMarkdownResources(server, channel, lease, ::authorized)
            }
            if(localMarkdownImages) {
                check(!publicMode && !sharedEditing && params.keys == setOf("lease"))
                csp = csp.replace("worker-src 'self' blob:;", "worker-src 'none';")
                localImages = LocalMarkdownImageResources(channel, lease, ::authorized)
            }
            check(lease.length in 1..128 && authorized())
            check(WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER))
            manifest = JSONObject(context.assets.open(ROOT + "source-manifest.json").bufferedReader().use { it.readText() }).getJSONObject("files")
            // Debug APK inspection only; release apps retain WebView's default.
            if ((context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
                WebView.setWebContentsDebuggingEnabled(true)
            }
            val view = WebView(context)
            browser = view
            live.add(this)
            view.setBackgroundColor(Color.WHITE)
            view.settings.apply {
                javaScriptEnabled = true
                allowFileAccess = false
                allowContentAccess = false
                blockNetworkLoads = true
                domStorageEnabled = false
                databaseEnabled = false
                cacheMode = WebSettings.LOAD_NO_CACHE
                mixedContentMode = if(publicMode || ownedResourceMode) WebSettings.MIXED_CONTENT_ALWAYS_ALLOW else WebSettings.MIXED_CONTENT_NEVER_ALLOW
                javaScriptCanOpenWindowsAutomatically = false
                setSupportMultipleWindows(false)
                setGeolocationEnabled(false)
                mediaPlaybackRequiresUserGesture = true
                textZoom = (context.resources.configuration.fontScale * 100).toInt().coerceIn(50, 300)
            }
            CookieManager.getInstance().setAcceptThirdPartyCookies(view, false)
            WebViewCompat.addWebMessageListener(view, "BookStarkEditorMessages", setOf(origin)) {
                _, message, sourceOrigin, isMainFrame, _ ->
                if (isMainFrame && sourceOrigin.toString() == origin && authorized()) {
                    receive(message.data)
                }
            }
            view.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback) {
                    callback.invoke(origin, false, false)
                }
                override fun onConsoleMessage(message: ConsoleMessage?): Boolean {
                    if (message?.messageLevel() == ConsoleMessage.MessageLevel.ERROR) {
                        val uri = runCatching { Uri.parse(message.sourceId()) }.getOrNull()
                        val path = uri?.path?.removePrefix("/")
                        if (uri != null && own(uri) && path != null && (path in hostFiles || manifest.has(path))) {
                            debugStage("packaged_js_error:" + path + ":" + message.lineNumber())
                        }
                    }
                    return true
                }
                override fun onShowFileChooser(view: WebView?, callback: android.webkit.ValueCallback<Array<Uri>>?, params: FileChooserParams?): Boolean {
                    callback?.onReceiveValue(null)
                    return true
                }
            }
            view.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest): WebResourceResponse = asset(request)
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest): Boolean {
                    if (!authorized()) return true
                    if (own(request.url)) {
                        return if (request.isForMainFrame) request.url.toString() != "$origin/host.html"
                        else request.url.path != "/static/pptist/app.html"
                    }
                    if ((publicMode || request.isForMainFrame) && request.hasGesture() &&
                        request.url.scheme in setOf("http", "https") && request.url.userInfo == null &&
                        !request.url.host.isNullOrEmpty() && request.url.toString().length <= 8192) {
                        channel.invokeMethod("externalLink", mapOf("lease" to lease, "url" to request.url.toString()))
                    }
                    return true
                }
                override fun onPageFinished(view: WebView, url: String?) {
                    if (!authorized() || url != "$origin/host.html" || booted) return
                    debugStage("page_finished")
                    view.evaluateJavascript("Boolean(window.BookStarkEditorHost && window.__BookStarkMemoryOnly === true && window.__BookStarkMemoryIndexedDB === true)") { ready ->
                        if (!authorized()) return@evaluateJavascript
                        if (ready == "true") { debugStage("host_check_ok"); booted = true; channel.invokeMethod("hostReady", mapOf("lease" to lease)) }
                        else { debugStage("host_check_failed"); channel.invokeMethod("hostFailed", mapOf("lease" to lease)); retire() }
                    }
                }
                override fun onReceivedSslError(view: WebView?, callback: SslErrorHandler, error: android.net.http.SslError?) { callback.cancel() }
            }
            view.setDownloadListener { _, _, _, _, _ -> /* Explicit export bridge is separate. */ }
            container.addView(view, FrameLayout.LayoutParams(-1, -1))
            view.loadUrl("$origin/host.html")
        } catch (error: Exception) { debugStage("native_init_error:" + error.javaClass.simpleName); retire() }
    }

    private fun localHtmlAttachmentMode(): Boolean =
        !publicMode && !publicComplexReadOnly && !sharedEditing && !sharedComplexEditing &&
        !ownedResourceMode && !generationResourceMode && !localMarkdownImages &&
        readingKind == "html" && !readingReadOnly && ioEditable &&
        ioGeneration > 0 && ioGeneration == readingGeneration && authorized()

    private fun localHtmlAttachmentOptions(reference: String, options: Map<*, *>): Boolean {
        val uri = try { Uri.parse(reference) } catch (_: Exception) { return false }
        if (reference.length !in 1..2048 || uri.scheme != "bookstark-attachment" ||
            !uri.host.isNullOrEmpty() || uri.userInfo != null || uri.port != -1 ||
            uri.query != null || uri.fragment != null) return false
        val parts = uri.pathSegments
        if (parts.size != 2 || !Regex("^[a-f0-9]{32}$").matches(parts[0])) return false
        val name = parts[1]
        if (name.isEmpty() || name.length > 255 || name == "." || name == ".." ||
            name.contains('/') || name.contains('\\') ||
            name.any { it.code < 32 || it.code == 127 } || options["name"] != name) return false
        return when (options["kind"]) {
            "file" -> options.keys == setOf("kind", "name")
            "image" -> {
                val width = options["width"]
                val height = options["height"]
                if ((width !is Int && width !is Long) || (height !is Int && height !is Long)) false
                else {
                    val w = (width as Number).toLong()
                    val h = (height as Number).toLong()
                    options.keys == setOf("kind", "name", "width", "height") &&
                        w in 1L..16384L && h in 1L..16384L && w*h <= 32L*1024*1024
                }
            }
            else -> false
        }
    }

    private fun mindmapImagePreflight(args: List<Any?>): String? {
        if(!localMindmapImages || publicMode || sharedEditing ||
            sharedComplexEditing || publicComplexReadOnly || ownedResourceMode ||
            generationResourceMode || localMarkdownImages || localRichdocImages)
            return "mindmap_preflight_mode"
        if(!authorized() || readingKind != "mindmap" || readingReadOnly || !ioEditable ||
            ioGeneration < 1 || ioGeneration != readingGeneration)
            return "mindmap_preflight_context"
        if(args.size != 3) return "mindmap_preflight_args"
        val id = args[0] as? String ?: return "mindmap_preflight_args"
        val reference = args[1] as? String ?: return "mindmap_preflight_args"
        val options = args[2] as? Map<*, *> ?: return "mindmap_preflight_args"
        if(options.keys != setOf("width","height","scope","scopeEpoch",
            "identityDigest","sourceDigest")) return "mindmap_preflight_args"
        val width = options["width"]
        val height = options["height"]
        val epoch = options["scopeEpoch"]
        val scope = options["scope"] as? String ?: return "mindmap_preflight_scope"
        val source = options["sourceDigest"] as? String ?: return "mindmap_preflight_scope"
        if((width !is Int && width !is Long) ||
            (height !is Int && height !is Long) ||
            (epoch !is Int && epoch !is Long)) return "mindmap_preflight_args"
        val w = (width as Number).toLong()
        val h = (height as Number).toLong()
        val e = (epoch as Number).toLong()
        if(id.length !in 1..128) return "mindmap_preflight_args"
        if(options["identityDigest"] != localMindmapScope ||
            !scope.matches(Regex("[a-f0-9]{64}")) ||
            !source.matches(Regex("[a-f0-9]{64}")) ||
            e <= 0 || !ComplexSourceIoChannel.ownsScope(scope,e))
            return "mindmap_preflight_scope"
        if(w !in 1L..16384L || h !in 1L..16384L || w*h > 32L*1024*1024)
            return "mindmap_preflight_dimensions"
        val uri = try { Uri.parse(reference) } catch(_: Exception) {
            return "mindmap_preflight_reference"
        }
        val parts = uri.pathSegments
        if(reference.length > 2048 || uri.scheme != "bookstark-attachment" ||
            !uri.host.isNullOrEmpty() || uri.userInfo != null || uri.port != -1 ||
            uri.query != null || uri.fragment != null ||
            parts.size != 2 || !parts[0].matches(Regex("[a-f0-9]{32}")) ||
            parts[1].isEmpty() || parts[1].length > 255 ||
            parts[1] in setOf(".", "..") || parts[1].any {
                it.code < 32 || it.code == 127 || it.code == 47 || it.code == 92 })
            return "mindmap_preflight_reference"
        return null
    }

    private fun publicCommand(name: String?, args: List<Any?>): Boolean {
        if(name == "insertLocalDrawingImageSnapshot") {
            if(!localDrawingImages || publicMode || sharedEditing ||
                sharedComplexEditing || publicComplexReadOnly || ownedResourceMode ||
                generationResourceMode || localMarkdownImages || !authorized() ||
                readingKind != "drawing" || readingReadOnly || !ioEditable ||
                ioGeneration < 1 || ioGeneration != readingGeneration || args.size != 3)
                return false
            val id = args[0] as? String ?: return false
            val reference = args[1] as? String ?: return false
            val options = args[2] as? Map<*, *> ?: return false
            if(options.keys != setOf("width","height","scope","scopeEpoch",
                "identityDigest","sourceDigest","resourceId")) return false
            val width = options["width"]
            val height = options["height"]
            val epoch = options["scopeEpoch"]
            val scope = options["scope"] as? String ?: return false
            val source = options["sourceDigest"] as? String ?: return false
            if((width !is Int && width !is Long) ||
                (height !is Int && height !is Long) ||
                (epoch !is Int && epoch !is Long)) return false
            val w = (width as Number).toLong()
            val h = (height as Number).toLong()
            val e = (epoch as Number).toLong()
            val uri = try { Uri.parse(reference) } catch(_: Exception) { return false }
            val parts = uri.pathSegments
            return (options["resourceId"] as? String)?.matches(Regex("[a-f0-9]{64}")) == true &&
                id.length in 1..128 && options["identityDigest"] == localDrawingScope &&
                scope.matches(Regex("[a-f0-9]{64}")) &&
                source.matches(Regex("[a-f0-9]{64}")) &&
                e > 0 && ComplexSourceIoChannel.ownsScope(scope,e) &&
                w in 1L..16384L && h in 1L..16384L && w*h <= 32L*1024*1024 &&
                reference.length <= 2048 && uri.scheme == "bookstark-attachment" &&
                uri.host.isNullOrEmpty() && uri.userInfo == null && uri.port == -1 &&
                uri.query == null && uri.fragment == null &&
                parts.size == 2 && parts[0].matches(Regex("[a-f0-9]{32}")) &&
                parts[1].isNotEmpty() && parts[1].length <= 255 &&
                parts[1] !in setOf(".", "..") && parts[1].none {
                    it.code < 32 || it.code == 127 || it.code == 47 || it.code == 92 }
        }
        if(name == "insertLocalPresentationImageSnapshot") {
            if(!localPresentationImages || publicMode || sharedEditing ||
                sharedComplexEditing || publicComplexReadOnly || ownedResourceMode ||
                generationResourceMode || localMarkdownImages || !authorized() ||
                readingKind != "presentation" || readingReadOnly || !ioEditable ||
                ioGeneration < 1 || ioGeneration != readingGeneration || args.size != 3)
                return false
            val id = args[0] as? String ?: return false
            val reference = args[1] as? String ?: return false
            val options = args[2] as? Map<*, *> ?: return false
            if(options.keys != setOf("width","height","scope","scopeEpoch",
                "identityDigest","sourceDigest","resourceId")) return false
            val width = options["width"]
            val height = options["height"]
            val epoch = options["scopeEpoch"]
            val scope = options["scope"] as? String ?: return false
            val source = options["sourceDigest"] as? String ?: return false
            if((width !is Int && width !is Long) ||
                (height !is Int && height !is Long) ||
                (epoch !is Int && epoch !is Long)) return false
            val w = (width as Number).toLong()
            val h = (height as Number).toLong()
            val e = (epoch as Number).toLong()
            val uri = try { Uri.parse(reference) } catch(_: Exception) { return false }
            val parts = uri.pathSegments
            return (options["resourceId"] as? String)?.matches(Regex("[a-f0-9]{64}")) == true &&
                id.length in 1..128 && options["identityDigest"] == localPresentationScope &&
                scope.matches(Regex("[a-f0-9]{64}")) &&
                source.matches(Regex("[a-f0-9]{64}")) &&
                e > 0 && ComplexSourceIoChannel.ownsScope(scope,e) &&
                w in 1L..16384L && h in 1L..16384L && w*h <= 32L*1024*1024 &&
                reference.length <= 2048 && uri.scheme == "bookstark-attachment" &&
                uri.host.isNullOrEmpty() && uri.userInfo == null && uri.port == -1 &&
                uri.query == null && uri.fragment == null &&
                parts.size == 2 && parts[0].matches(Regex("[a-f0-9]{32}")) &&
                parts[1].isNotEmpty() && parts[1].length <= 255 &&
                parts[1] !in setOf(".", "..") && parts[1].none {
                    it.code < 32 || it.code == 127 || it.code == 47 || it.code == 92 }
        }
        if(name == "insertLocalRichdocImageSnapshot") {
            if(!localRichdocImages || publicMode || sharedEditing ||
                sharedComplexEditing || publicComplexReadOnly || ownedResourceMode ||
                generationResourceMode || localMarkdownImages || !authorized() ||
                readingKind != "richdoc" || readingReadOnly || !ioEditable ||
                ioGeneration < 1 || ioGeneration != readingGeneration || args.size != 3)
                return false
            val id = args[0] as? String ?: return false
            val reference = args[1] as? String ?: return false
            val options = args[2] as? Map<*, *> ?: return false
            if(options.keys != setOf("width","height","scope","scopeEpoch",
                "identityDigest","sourceDigest")) return false
            val width = options["width"]
            val height = options["height"]
            val epoch = options["scopeEpoch"]
            val scope = options["scope"] as? String ?: return false
            val source = options["sourceDigest"] as? String ?: return false
            if((width !is Int && width !is Long) ||
                (height !is Int && height !is Long) ||
                (epoch !is Int && epoch !is Long)) return false
            val w = (width as Number).toLong()
            val h = (height as Number).toLong()
            val e = (epoch as Number).toLong()
            val uri = try { Uri.parse(reference) } catch(_: Exception) { return false }
            val parts = uri.pathSegments
            return id.length in 1..128 && options["identityDigest"] == localRichdocScope &&
                scope.matches(Regex("[a-f0-9]{64}")) &&
                source.matches(Regex("[a-f0-9]{64}")) &&
                e > 0 && ComplexSourceIoChannel.ownsScope(scope,e) &&
                w in 1L..16384L && h in 1L..16384L && w*h <= 32L*1024*1024 &&
                reference.length <= 2048 && uri.scheme == "bookstark-attachment" &&
                uri.host.isNullOrEmpty() && uri.userInfo == null && uri.port == -1 &&
                uri.query == null && uri.fragment == null &&
                parts.size == 2 && parts[0].matches(Regex("[a-f0-9]{32}")) &&
                parts[1].isNotEmpty() && parts[1].length <= 255 &&
                parts[1] !in setOf(".", "..") && parts[1].none {
                    it.code < 32 || it.code == 127 || it.code == 47 || it.code == 92 }
        }
        if(localDrawingImages && name == "beginLoad") {
            if(args.size != 4 || args[0] != "drawing" || args[2] != localDrawingSource) return false
            val size = args[1] as? Int ?: return false
            val options = args[3] as? Map<*, *> ?: return false
            val binding = options["localDrawing"] as? Map<*, *> ?: return false
            val resources = binding["resources"] as? Map<*, *> ?: return false
            return size in 0..5*1024*1024 && options["readOnly"] == false &&
                options["sourceReadOnly"] != true && options["publicResourceRoot"] == null &&
                options["localMarkdownImages"] != true &&
                options["sharedMarkdownEditing"] != true &&
                options["sharedComplexEditing"] != true &&
                binding.keys == setOf("scope", "resources") &&
                binding["scope"] == localDrawingScope && resources.size <= 32 &&
                resources.all { (key, value) ->
                    key is String && key.length in 1..256 &&
                    value is String && value.matches(Regex("[a-f0-9]{64}"))
                }
        }
        if(localPresentationImages && name == "beginLoad") {
            if(args.size != 4 || args[0] != "presentation" || args[2] != localPresentationSource) return false
            val size = args[1] as? Int ?: return false
            val options = args[3] as? Map<*, *> ?: return false
            val binding = options["localPresentation"] as? Map<*, *> ?: return false
            val resources = binding["resources"] as? Map<*, *> ?: return false
            return size in 0..20*1024*1024 && options["readOnly"] == false &&
                options["sourceReadOnly"] != true && options["publicResourceRoot"] == null &&
                options["localMarkdownImages"] != true &&
                options["sharedMarkdownEditing"] != true &&
                options["sharedComplexEditing"] != true &&
                binding.keys == setOf("scope", "resources") &&
                binding["scope"] == localPresentationScope && resources.size <= 55000 && resources.values.toSet().size <= 32 &&
                resources.all { (key, value) ->
                    key is String && key.length in 1..256 &&
                    value is String && value.matches(Regex("[a-f0-9]{64}"))
                }
        }
        if(localRichdocImages && name == "beginLoad") {
            if(args.size != 4 || args[0] != "richdoc" || args[2] != localRichdocSource) return false
            val size = args[1] as? Int ?: return false
            val options = args[3] as? Map<*, *> ?: return false
            return size in 0..5*1024*1024 && options["readOnly"] == false &&
                options["sourceReadOnly"] != true && options["publicResourceRoot"] == null &&
                options["localMarkdownImages"] != true &&
                options["sharedMarkdownEditing"] != true &&
                options["sharedComplexEditing"] != true
        }
        if(name == "insertLocalMindmapImageSnapshot") {
            return mindmapImagePreflight(args) == null
        }
        if(localMindmapImages && name == "beginLoad") {
            if(args.size != 4 || args[0] != "mindmap" || args[2] != localMindmapSource) return false
            val size = args[1] as? Int ?: return false
            val options = args[3] as? Map<*, *> ?: return false
            return size in 0..5*1024*1024 && options["readOnly"] == false &&
                options["sourceReadOnly"] != true && options["publicResourceRoot"] == null &&
                options["localMarkdownImages"] != true &&
                options["sharedMarkdownEditing"] != true &&
                options["sharedComplexEditing"] != true
        }
        if (name == "authorizeLocalHtmlAttachments") {
            if (!localHtmlAttachmentMode() || args.size != 5) return false
            val scope = args[0] as? String ?: return false
            val epoch = args[1]
            val identity = args[2] as? String ?: return false
            val snapshot = args[3] as? String ?: return false
            val source = args[4] as? String ?: return false
            if (epoch !is Int && epoch !is Long) return false
            val expectedEpoch = (epoch as Number).toLong()
            return Regex("^[a-f0-9]{64}$").matches(scope) &&
                Regex("^[a-f0-9]{64}$").matches(identity) &&
                Regex("^[a-f0-9]{64}$").matches(source) &&
                snapshot.length in 1..128 && expectedEpoch > 0 &&
                ComplexSourceIoChannel.ownsScope(scope, expectedEpoch)
        }
        if (name == "insertLocalHtmlAttachmentSnapshot") {
            val scope = localHtmlAttachmentScope ?: return false
            if (!localHtmlAttachmentMode() || args.size != 3 ||
                localHtmlAttachmentGeneration != ioGeneration ||
                localHtmlAttachmentIdentity == null ||
                !ComplexSourceIoChannel.ownsScope(scope, localHtmlAttachmentEpoch)) return false
            val id = args[0] as? String ?: return false
            val uri = args[1] as? String ?: return false
            val options = args[2] as? Map<*, *> ?: return false
            return id.length in 1..128 && id == localHtmlAttachmentSnapshot &&
                localHtmlAttachmentSource != null && localHtmlAttachmentOptions(uri, options)
        }

        if(name == "insertImageSnapshot") {
            if(!ownedResourceMode || publicMode || sharedEditing || !ioEditable ||
                readingReadOnly || readingKind !in setOf("html","richdoc","spreadsheet","mindmap","drawing","presentation") || args.size != 4) return false
            val id = args[0] as? String ?: return false
            val text = args[1] as? String ?: return false
            val width = args[2] as? Number ?: return false
            val height = args[3] as? Number ?: return false
            val server = ownedServer ?: return false
            val uri = try { URI(text) } catch(_:Exception) { return false }
            val prefix = server.path.orEmpty().trimEnd('/')
            return id.length in 1..128 && text.length in 1..2048 &&
                uri.scheme == server.scheme && uri.rawAuthority == server.rawAuthority &&
                uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null &&
                uri.path.orEmpty().startsWith(prefix + "/upload-files/") &&
                width.toLong() in 1L..8192L && height.toLong() in 1L..8192L &&
                width.toLong()*height.toLong() <= 16L*1024*1024
        }

        if(name in setOf("bindPublicSelection", "capturePublicSelection")) {
            if(!publicComplexReadOnly || sharedEditing || !readingReadOnly || args.size != 1) return false
            val b=args[0] as? Map<*, *> ?: return false
            return b.keys == setOf("version","resource","identityDigest","kind","sourceDigest","runtimeLease","generation") &&
                b["version"] == 1 && b["resource"] == "public-share" && b["kind"] == readingKind &&
                b["runtimeLease"] == lease && b["generation"] == readingGeneration &&
                Regex("^[a-f0-9]{64}$").matches(b["identityDigest"] as? String ?: "") &&
                Regex("^[a-f0-9]{64}$").matches(b["sourceDigest"] as? String ?: "")
        }
        if (name in setOf("bindReading", "captureReading", "restoreReading")) {
            if (sharedEditing || !readingReadOnly || args.size != (if(name == "bindReading") 1 else 2)) return false
            if(name == "captureReading" && args[1] !is Boolean) return false
            val binding = args[0] as? Map<*, *> ?: return false
            val book = binding["bookId"] as? Number ?: return false
            val doc = binding["documentId"] as? Number ?: return false
            return binding.keys == setOf("version","bookId","documentId","kind","fullFingerprint","sourceDigest","runtimeLease","generation") &&
                binding["version"] == 1 && book.toLong() > 0 && doc.toLong() > 0 &&
                binding["runtimeLease"] == lease && binding["generation"] == readingGeneration &&
                binding["kind"] == readingKind &&
                Regex("^[a-f0-9]{64}$").matches(binding["sourceDigest"] as? String ?: "") &&
                Regex("^[a-f0-9]{64}$").matches(binding["fullFingerprint"] as? String ?: "")
        }
        if(sharedComplexEditing) {
            if(!publicMode || !sharedEditing || publicComplexReadOnly || localMarkdownImages) return false
            if(name != "beginLoad") return name in setOf("appendLoad", "abortLoad", "commitLoad", "state", "beginSnapshot", "readSnapshot", "endSnapshot", "acknowledgeSnapshot", "setInputLocked", "setMarkdownByteLimit") &&
                (name != "setInputLocked" || args.size == 2 && args[0] is Boolean && args[1] is Int && (args[1] as Int) > 0)
            if(args.size != 4) return false
            val kind = args[0] as? String ?: return false
            val limit = when(kind) { "html", "spreadsheet", "drawing", "mindmap", "richdoc" -> 5*1024*1024; "presentation" -> 20*1024*1024; else -> return false }
            val size = args[1] as? Int ?: return false
            val options = args[3] as? Map<*, *> ?: return false
            return size in 0..limit && options["sharedComplexEditing"] == true && options["readOnly"] is Boolean &&
                options["publicComplexReadOnly"] != true && options["sharedMarkdownEditing"] != true && options["sourceReadOnly"] != true &&
                options["localMarkdownImages"] != true && options["publicResourceRoot"] == publicServer?.toString() &&
                options.keys.all { it in setOf("sharedComplexEditing","publicResourceRoot","readOnly","sourceReadOnly","english","title") }
        }
        if(publicComplexReadOnly) {
            if(!publicMode || sharedEditing || localMarkdownImages) return false
            if(name != "beginLoad") return name in setOf("appendLoad", "abortLoad", "commitLoad", "state", "beginSnapshot", "readSnapshot", "endSnapshot")
            if(args.size != 4) return false
            val kind = args[0] as? String ?: return false
            val size = args[1] as? Int ?: return false
            val options = args[3] as? Map<*, *> ?: return false
            val limit = when(kind) {
                "markdown" -> 4 * 1024 * 1024
                "presentation" -> 20 * 1024 * 1024
                "html", "spreadsheet", "drawing", "mindmap", "richdoc" -> 5 * 1024 * 1024
                else -> return false
            }
            return size in 0..limit && options["publicComplexReadOnly"] == true &&
                options["readOnly"] == true && options["sourceReadOnly"] != true &&
                options["sharedMarkdownEditing"] != true && options["localMarkdownImages"] != true &&
                options["publicResourceRoot"] == publicServer?.toString() &&
                options.keys.all { it in setOf("readOnly", "sourceReadOnly", "english", "title", "publicResourceRoot", "publicComplexReadOnly") }
        }

        if(localMarkdownImages && name == "beginLoad") {
            if(args.size != 4 || args[0] != "markdown") return false
            val options = args[3] as? Map<*, *> ?: return false
            return options["localMarkdownImages"] == true && options["readOnly"] is Boolean &&
                options["sourceReadOnly"] != true && options["publicResourceRoot"] == null &&
                options["sharedMarkdownEditing"] != true
        }
        if(!publicMode) return true
        if(name == "insertMarkdownSnapshot") return sharedEditing && args.size == 2 &&
            args[0] is String && (args[0] as String).length in 1..128 &&
            args[1] is String && (args[1] as String).toByteArray(Charsets.UTF_8).size in 1..65536
        if(name == "acknowledgeSnapshot") return sharedEditing
        if(name == "setInputLocked") return args.size == 2 && args[1] is Int && (args[1] as Int) > 0 && (args[0] == true || sharedEditing && args[0] == false)
        if(name != "beginLoad") return true
        if(args.size != 4 || args[0] != "markdown") return false
        val size = args[1] as? Int ?: return false
        val options = args[3] as? Map<*, *> ?: return false
        return size in 0..4 * 1024 * 1024 && (if(sharedEditing) options["readOnly"] is Boolean else options["readOnly"] == true) &&
            (if(sharedEditing) options["sharedMarkdownEditing"] == true else options["sharedMarkdownEditing"] != true) &&
            options["sourceReadOnly"] != true && options["publicResourceRoot"] == publicServer?.toString()
    }

    private fun dispatch(name: String, arguments: List<Any?>, result: MethodChannel.Result) {
        var commandId: String? = null
        try {
            if (name == "authorizeLocalHtmlAttachments") {
                check(publicCommand(name, arguments))
                localHtmlAttachmentScope = arguments[0] as String
                localHtmlAttachmentEpoch = (arguments[1] as Number).toLong()
                localHtmlAttachmentGeneration = ioGeneration
                localHtmlAttachmentIdentity = arguments[2] as String
                localHtmlAttachmentSnapshot = arguments[3] as String
                localHtmlAttachmentSource = arguments[4] as String
                result.success(mapOf("generation" to ioGeneration,
                    "scopeEpoch" to localHtmlAttachmentEpoch,
                    "identityDigest" to localHtmlAttachmentIdentity,
                    "snapshotId" to localHtmlAttachmentSnapshot,
                    "sourceDigest" to localHtmlAttachmentSource))
                return
            }
            if (name == "insertLocalHtmlAttachmentSnapshot") {
                check(publicCommand(name, arguments))
                clearLocalHtmlAttachmentGrant()
            }
            if (name == "setMarkdownByteLimit") {
                check(!publicMode && !publicComplexReadOnly && !sharedEditing && !sharedComplexEditing)
                check(ioEditable && readingKind == "markdown" && !readingReadOnly && authorized())
                check(arguments.size == 2 && arguments[0] is Int && arguments[1] == ioGeneration)
                check((arguments[0] as Int) in 1..4 * 1024 * 1024)
            }
            if (name == "beginLoad") {
                clearLocalHtmlAttachmentGrant()
                reviewExportHash = null
                reviewExportBytes = null
                reviewCommitCommandId = null
                reviewReadyGeneration = -1
                readingGeneration = -1
                readingReadOnly = false
                ioEditable = false
                ioGeneration = -1
                val options = arguments.getOrNull(3) as? Map<*, *>
                if (!publicMode && !publicComplexReadOnly && !sharedEditing && !sharedComplexEditing &&
                    arguments.getOrNull(0) == "markdown" && options != null && options["ownedReviewExport"] == true &&
                    options["readOnly"] == true && options["sourceReadOnly"] != true &&
                    options["publicResourceRoot"] == null) {
                    val hash = (options["ownedReviewExportDigest"] ?: arguments.getOrNull(2)) as? String
                    val bytes = ((options["ownedReviewExportBytes"] ?: arguments.getOrNull(1)) as? Number)?.toLong()
                    check(bytes != null && bytes in 0..32L * 1024 * 1024)
                    check(hash != null && hash.matches(Regex("[a-f0-9]{64}")))
                    reviewExportHash = hash
                    reviewExportBytes = bytes
                }
                ownedMarkdownIoRequested = !publicMode && !publicComplexReadOnly &&
                    !sharedEditing && !sharedComplexEditing &&
                    arguments.getOrNull(0) == "markdown" && options != null &&
                    options["ownedMarkdownSourceIo"] == true &&
                    options["readOnly"] == false && options["sourceReadOnly"] != true &&
                    options["publicResourceRoot"] == null
            }
            val encoded = JSONArray(arguments).toString()
            check(encoded.length <= 400000)
            val id = UUID.randomUUID().toString()
            commandId = id
            if (name == "commitLoad" && reviewExportHash != null) reviewCommitCommandId = id
            val timeout = Runnable { pending.remove(id)?.result?.error("editor_timeout", "Editor command timed out", null) }
            pending[id] = Pending(result, timeout)
            handler.postDelayed(timeout, 60000)
            val safeMindmapCodes = setOf("invalid_local_mindmap_image",
                "invalid_local_mindmap_reference", "local_mindmap_image_capacity",
                "local_mindmap_selection_changed", "retired_local_mindmap_image",
                "local_mindmap_image_not_observed")
            val safeCodes = if (name == "insertLocalMindmapImageSnapshot")
                JSONArray(safeMindmapCodes.toList()).toString() else "[]"
            val script = "(async()=>{try{const value=await window.BookStarkEditorHost[${JSONObject.quote(name)}](...$encoded);" +
                "window.BookStarkEditorMessages.postMessage(JSON.stringify({type:'command',id:${JSONObject.quote(id)},ok:true,value:value===undefined?null:value}));" +
                "}catch(e){const safeCode=$safeCodes.includes(e&&e.message)?e.message:null;window.BookStarkEditorMessages.postMessage(JSON.stringify({type:'command',id:${JSONObject.quote(id)},ok:false,safeCode}));}})();void 0;"
            browser?.evaluateJavascript(script, null)
        } catch (_: Exception) {
            commandId?.let { pending.remove(it)?.let { work -> handler.removeCallbacks(work.timeout) } }
            result.error("invalid_command", "Invalid editor command", null)
        }
    }
    private fun publicExternalLink(raw: String) {
        if (!publicMode || !authorized() || !booted || publicLinkChecking ||
            raw.length !in 1..8192) return
        val uri = Uri.parse(raw)
        if (uri.scheme !in setOf("http", "https") || uri.host.isNullOrEmpty() || uri.userInfo != null) return
        val view = browser ?: return
        publicLinkChecking = true
        val sequence = ++publicLinkSequence
        val deadline = Runnable { if (sequence == publicLinkSequence) publicLinkChecking = false }
        handler.postDelayed(deadline, 3000)
        // Opaque child clicks activate ancestor windows. Query the trusted main
        // realm rather than trusting a gesture flag supplied by rendered data.
        // Keyboard and accessibility activation are supported by the same API.
        try {
            view.evaluateJavascript("Boolean(navigator.userActivation && navigator.userActivation.isActive)") { active ->
                handler.removeCallbacks(deadline)
                if (sequence != publicLinkSequence || !publicLinkChecking) return@evaluateJavascript
                publicLinkChecking = false
                if (active == "true" && authorized() && browser === view) {
                    channel.invokeMethod("externalLink", mapOf("lease" to lease, "url" to uri.toString()))
                }
            }
        } catch (_: Exception) {
            handler.removeCallbacks(deadline)
            publicLinkChecking = false
        }
    }

    private fun receive(text: String?) {
        if (text == null || text.length > 400000) return
        try {
            val message = JSONObject(text)
            when (message.optString("type")) {
                "command" -> {
                    val work = pending.remove(message.optString("id")) ?: return
                    handler.removeCallbacks(work.timeout)
                    if (message.optString("id") == reviewCommitCommandId) {
                        reviewCommitCommandId = null
                        val receipt = message.optJSONObject("value")
                        reviewReadyGeneration = if (message.optBoolean("ok") &&
                            receipt != null && receipt.optBoolean("ready", false) &&
                            receipt.optBoolean("readOnly", false) &&
                            !receipt.optBoolean("sourceReadOnly", false) &&
                            receipt.optString("kind") == "markdown")
                            receipt.optInt("generation", -1) else -1
                    }
                    if (message.optBoolean("ok")) work.result.success(value(message.opt("value")))
                    else {
                        val safeCode = message.optString("safeCode").takeIf {
                            it in setOf("invalid_local_mindmap_image",
                                "invalid_local_mindmap_reference", "local_mindmap_image_capacity",
                                "local_mindmap_selection_changed", "retired_local_mindmap_image",
                                "local_mindmap_image_not_observed")
                        }
                        work.result.error("editor_command_failed", "Editor command failed", safeCode)
                    }
                }
                "publicExternalLink" -> if (text.length <= 16384) {
                    publicExternalLink(message.optString("url"))
                }
                "localImageFailure" -> if(localMarkdownImages && authorized() && text.length <= 256) {
                    channel.invokeMethod("localImageFailure", mapOf("lease" to lease))
                }
                "publicImageFailure" -> if(publicMode && authorized() && text.length <= 256) {
                    channel.invokeMethod("publicImageFailure", mapOf("lease" to lease))
                }
                "state", "saveRequested" -> if (text.length <= 4096 && (!publicMode || sharedEditing || message.optString("type") == "state")) {
                    if (message.optString("type") == "state") {
                        if(generationResourceMode && message.optBoolean("dirty", false)) {
                            generationResources?.close()
                        }
                        readingGeneration = message.optInt("generation", -1)
                        readingKind = message.optString("kind", "")
                        readingReadOnly = message.optBoolean("ready", false) && message.optBoolean("readOnly", false) &&
                            !message.optBoolean("sourceReadOnly", false) && !sharedEditing
                        ioGeneration = message.optInt("generation", -1)
                        ioEditable = (!publicMode || sharedComplexEditing) && (!localMarkdownImages || ownedMarkdownIoRequested) && message.optBoolean("ready", false) &&
                            !message.optBoolean("readOnly", true) && !message.optBoolean("sourceReadOnly", true) &&
                            (message.optString("kind") in setOf("html","spreadsheet","drawing","mindmap","richdoc","presentation") || (!publicMode && !sharedEditing && ownedMarkdownIoRequested && message.optString("kind") == "markdown"))
                    }
                    channel.invokeMethod(message.getString("type"), mapOf("lease" to lease, "state" to value(message)))
                }
            }
        } catch (_: Exception) { /* Never log document text or engine exception strings. */ }
    }
    private fun value(item: Any?): Any? = when(item) {
        null, JSONObject.NULL -> null
        is JSONObject -> item.keys().asSequence().associateWith { value(item.get(it)) }
        is JSONArray -> (0 until item.length()).map { value(item.get(it)) }
        is String, is Number, is Boolean -> item
        else -> null
    }
    private fun asset(request: WebResourceRequest): WebResourceResponse {
        try {
            if(!authorized()) return denied()
            if(localDrawingImages && own(request.url) &&
                request.url.encodedPath.orEmpty().startsWith("/local-drawing/")) {
                if(request.isForMainFrame || request.method != "GET") return denied()
                return localDrawingResources?.read(request.url) ?: denied()
            }
            if(localPresentationImages && own(request.url) &&
                request.url.encodedPath.orEmpty().startsWith("/local-presentation/")) {
                if(request.isForMainFrame || request.method != "GET") return denied()
                return localPresentationResources?.read(request.url) ?: denied()
            }
            if(localRichdocImages && !request.isForMainFrame &&
                request.method == "GET" && request.url.scheme == "bookstark-attachment") {
                return localRichdocResources?.read(request.url) ?: denied()
            }
            if(localMindmapImages && !request.isForMainFrame &&
                request.method == "GET" && request.url.scheme == "bookstark-attachment") {
                return localMindmapResources?.read(request.url) ?: denied()
            }
            if(localMarkdownImages && own(request.url) && request.method == "GET" &&
                !request.isForMainFrame && request.url.encodedPath.orEmpty().startsWith("/__bookstark_local_image/")) {
                if(request.url.query != null || request.url.fragment != null) return denied()
                val reference = Uri.parse("bookstark-attachment:///" +
                    request.url.encodedPath.orEmpty().removePrefix("/__bookstark_local_image/"))
                return localImages?.read(reference) ?: denied()
            }
            if(generationResourceMode && !request.isForMainFrame &&
                request.url.encodedPath.orEmpty().startsWith("/upload-files/")) {
                if(!own(request.url) || request.method != "GET" ||
                    request.url.query != null || request.url.fragment != null) return denied()
                return generationResources?.read(Uri.parse(request.url.encodedPath)) ?: denied()
            }
            if(ownedResourceMode && request.method == "GET" && !request.isForMainFrame) {
                val uri = request.url
                if(uri.query != null || uri.fragment != null) return denied()
                val server = ownedServer
                if(own(uri) && (uri.path.orEmpty().startsWith("/upload-files/") ||
                        uri.path.orEmpty().startsWith("/static/") && !manifest.has(uri.path.orEmpty().removePrefix("/")))) {
                    val mapped = if(server == null) null else Uri.parse(
                        "${server.scheme}://${server.rawAuthority}${uri.encodedPath}")
                    return mapped?.let { ownedResources?.read(it) } ?: denied()
                }
                if(!own(uri)) return ownedResources?.read(uri) ?: denied()
            }
            if(sharedComplexEditing && own(request.url) && request.method == "GET" && !request.isForMainFrame &&
                request.url.encodedPath.orEmpty().startsWith("/upload-files/")) {
                val server = publicServer ?: return denied()
                val mapped = Uri.parse(server.scheme + "://" + server.rawAuthority + server.path.orEmpty().trimEnd('/') + request.url.encodedPath +
                    (request.url.encodedQuery?.let { "?" + it } ?: ""))
                return publicResources?.read(mapped) ?: denied()
            }
            if(!own(request.url)) return if(publicMode && request.method == "GET" && !request.isForMainFrame)
                publicResources?.read(request.url) ?: denied() else denied()
            if (request.method !in setOf("GET", "HEAD") || request.url.fragment != null) return denied()
            val path = request.url.path?.removePrefix("/") ?: return denied()
            if (path.length !in 1..1024 || path.contains('\\') || path.any { it.code < 32 } ||
                path.split('/').any { it.isEmpty() || it == "." || it == ".." }) return denied()
            if (path !in hostFiles && !manifest.has(path)) { debugStage("unlisted_asset_denied"); return denied() }
            // No arbitrary packaged HTML, including a PPT app opened as the top
            // document. Only the owned host and its existing PPT child execute.
            if (path.endsWith(".html") && path !in setOf("host.html", "static/pptist/app.html")) return denied()
            if (request.isForMainFrame && path != "host.html") return denied()
            val info = manifest.optJSONObject(path)
            var bytes = context.assets.open(ROOT + path).use { input ->
                val bound = info?.getInt("bytes") ?: 1024 * 1024
                check(bound in 0..32 * 1024 * 1024)
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(16384)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    check(output.size() + count <= bound)
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            if (info != null) {
                check(bytes.size == info.getInt("bytes"))
                val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                check(digest == info.getString("sha256"))
            }
            if (path == "host.html") debugStage("host_asset_verified")
            if (path == "static/pptist/app.html") {
                val html = bytes.toString(Charsets.UTF_8)
                check(html.contains("<head>"))
                bytes = html.replaceFirst("<head>", "<head><script src=\"/memory-storage.js\"></script><script type=\"module\" src=\"/memory-indexeddb.js\"></script>").toByteArray(Charsets.UTF_8)
            }
            val mime = when(path.substringAfterLast('.', "")) {
                "html" -> "text/html"; "js", "mjs" -> "application/javascript"
                "css" -> "text/css"; "json" -> "application/json"; "svg" -> "image/svg+xml"
                "png" -> "image/png"; "jpg", "jpeg" -> "image/jpeg"; "webp" -> "image/webp"
                "ico" -> "image/x-icon"; "woff" -> "font/woff"; "woff2" -> "font/woff2"; "ttf" -> "font/ttf"
                else -> "text/plain"
            }
            if (!authorized()) return denied()
            return WebResourceResponse(mime, if(mime.startsWith("text/") || mime in setOf("application/javascript", "application/json", "image/svg+xml")) "UTF-8" else null,
                200, "OK", mapOf("Content-Security-Policy" to csp, "Cache-Control" to "no-store",
                    "Access-Control-Allow-Origin" to "*",
                    "Referrer-Policy" to "no-referrer", "X-Content-Type-Options" to "nosniff"),
                (if(request.method == "HEAD") byteArrayOf() else bytes).inputStream())
        } catch (_: Exception) { return denied() }
    }
    private fun denied() = WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden",
        mapOf("Cache-Control" to "no-store"), byteArrayOf().inputStream())
    private fun retire() {
        if (retired) return
        retired = true
        clearLocalHtmlAttachmentGrant()
        publicLinkChecking = false
        publicLinkSequence++
        localImages?.close()
        localDrawingResources?.close()
        localDrawingScope = null
        localDrawingSource = null
        localPresentationResources?.close()
        localPresentationScope = null
        localPresentationSource = null
        localRichdocResources?.close()
        localRichdocScope = null
        localRichdocSource = null
        localMindmapResources?.close()
        localMindmapScope = null
        localMindmapSource = null
        generationResources?.close(); generationResources = null
        ownedResources?.close(); ownedResources = null; ownedServer = null
        publicResources?.close()
        booted = false
        live.remove(this)
        pending.values.toList().forEach { handler.removeCallbacks(it.timeout); it.result.error("editor_retired", "Editor session ended", null) }
        pending.clear()
        browser?.let { view ->
            view.evaluateJavascript("window.BookStarkEditorHost?.retire();", null)
            view.settings.javaScriptEnabled = false
            view.stopLoading()
            WebViewCompat.removeWebMessageListener(view, "BookStarkEditorMessages")
            container.removeView(view)
            view.destroy()
        }
        browser = null
        container.removeAllViews()
        container.addView(TextView(context).apply { text = "编辑器已关闭 / Editor closed" })
    }
    override fun getView() = container
    override fun dispose() {
        if (disposed) return
        disposed = true
        retire()
        channel.setMethodCallHandler(null)
    }
}
