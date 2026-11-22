package com.bookstark.bookstark_flutter

import android.app.Activity
import android.webkit.CookieManager
import androidx.webkit.Profile
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.URI
import java.util.ArrayDeque

/** Article Go UI has a named profile; its drafts never share the preview store. */
class ArticleWebSessionChannel(messenger: BinaryMessenger) {
    data class Session(
        val lease: String, val server: URI, val profileName: String,
        val cookiePath: String, val entry: String, val english: Boolean,
        val profile: Profile, @Volatile var retired: Boolean = false
    )
    companion object {
        @Volatile private var current: Session? = null
        private val pending = ArrayDeque<(() -> Unit) -> Unit>()
        private var running = false
        private fun enqueue(work: (() -> Unit) -> Unit) {
            pending.add(work); drain()
        }
        private fun drain() {
            if (running || pending.isEmpty()) return
            running = true
            pending.removeFirst().invoke { running = false; drain() }
        }
        fun owns(lease: String): Boolean = current?.let {
            it.lease == lease && !it.retired && HtmlPreviewSessionChannel.ownsLocalLease(lease)
        } == true
        fun session(lease: String): Session? = current?.takeIf { owns(lease) }

        private fun clearOwned(state: Session, complete: (Boolean) -> Unit) {
            state.retired = true
            ArticleWebView.retireLease(state.lease)
            if (current !== state) { complete(true); return }
            try {
                state.profile.cookieManager.removeAllCookies {
                    // Flush deletion, never the authenticated session on open.
                    state.profile.cookieManager.flush()
                    val clean = !state.profile.cookieManager.hasCookies()
                    if (clean && current === state) current = null
                    complete(clean)
                }
            } catch (_: Exception) { complete(false) }
        }
        fun retireAll() {
            val old = current ?: return
            old.retired = true
            ArticleWebView.retireLease(old.lease)
            enqueue { done -> clearOwned(old) { done() } }
        }
        fun retire(lease: String) {
            val old = current?.takeIf { it.lease == lease } ?: return
            old.retired = true
            ArticleWebView.retireLease(lease)
            enqueue { done -> clearOwned(old) { done() } }
        }
    }
    private val channel = MethodChannel(messenger, "bookstark/article_web_session")
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, reply ->
            val lease = call.argument<String>("lease")
            if (disposed || lease.isNullOrEmpty() || lease.length > 128) {
                reply.error("article_scope_invalid", "Article session unavailable", null)
            } else when (call.method) {
                "open" -> {
                    val serverText = call.argument<String>("server")
                    val server = try { URI(serverText ?: "") } catch (_: Exception) { null }
                    val profileName = call.argument<String>("profile") ?: ""
                    val cookiePath = call.argument<String>("cookiePath") ?: ""
                    val entry = call.argument<String>("entry") ?: ""
                    val entryUri = try { URI(entry) } catch (_: Exception) { null }
                    val cookies = call.argument<Map<String, String>>("cookies")
                    val language = call.argument<String>("language")
                    val prefix = server?.rawPath?.trimEnd('/') ?: ""
                    if (call.argument<Int>("format") != 1 ||
                        server == null || server.scheme !in listOf("http", "https") ||
                        server.host.isNullOrEmpty() || server.rawUserInfo != null ||
                        server.rawQuery != null || server.rawFragment != null ||
                        server.normalize() != server || prefix.contains("//") ||
                        prefix.any { it.code < 32 || it == ';' || it == '\\' } ||
                        !profileName.matches(Regex("^bookstark\\.article\\.v1\\.[a-f0-9]{64}$")) ||
                        cookiePath != "$prefix/" || language !in listOf("zh", "en") ||
                        entryUri == null || entryUri.scheme != server.scheme ||
                        entryUri.host != server.host || entryUri.port != server.port ||
                        !ArticleWebRoutes(server, cookiePath).validInitialEntry(entry) || entryUri.rawUserInfo != null ||
                        cookies == null || cookies.keys.any { it !in listOf("token", "csrf_token") } ||
                        cookies["token"].isNullOrEmpty() ||
                        cookies.values.any { it.length > 32768 || it.any { c -> c.code < 0x21 || c.code > 0x7e || c == ';' } }) {
                        reply.error("article_scope_invalid", "Article session unavailable", null)
                    } else if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE) || !WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                        reply.error("article_profile_unsupported", "Update Android System WebView", null)
                    } else enqueue { done ->
                        fun open() {
                            if (disposed || !HtmlPreviewSessionChannel.ownsLocalLease(lease)) {
                                reply.error("article_scope_retired", "Article session ended", null); done(); return
                            }
                            try {
                                val profile = ProfileStore.getInstance().getOrCreateProfile(profileName)
                                val state = Session(lease, server, profileName, cookiePath, entry, language == "en", profile)
                                current = state
                                val manager = profile.cookieManager
                                manager.setAcceptCookie(true)
                                manager.removeAllCookies {
                                    val values = cookies.entries.map { it.key to it.value } + ("lang" to language!!)
                                    fun install(index: Int) {
                                        if (disposed || !owns(lease)) {
                                            clearOwned(state) {
                                                reply.error("article_scope_retired", "Article session ended", null); done()
                                            }
                                            return
                                        }
                                        if (index == values.size) { reply.success(null); done(); return }
                                        val (name, value) = values[index]
                                        val secure = if (server.scheme == "https") "; Secure" else ""
                                        val httpOnly = if (name == "token") "; HttpOnly" else ""
                                        manager.setCookie(serverText!!,
                                            "$name=$value; Path=$cookiePath; SameSite=Lax$secure$httpOnly") { accepted ->
                                            if (accepted) install(index + 1) else clearOwned(state) {
                                                reply.error("article_cookie_rejected", "Article authentication unavailable", null); done()
                                            }
                                        }
                                    }
                                    install(0)
                                }
                            } catch (_: Exception) {
                                reply.error("article_profile_failed", "Article session unavailable", null); done()
                            }
                        }
                        val old = current
                        if (old == null) open() else clearOwned(old) { clean ->
                            if (clean) open() else {
                                reply.error("article_cleanup_pending", "Previous article session is closing", null); done()
                            }
                        }
                    }
                }
                "close" -> enqueue { done ->
                    val old = current?.takeIf { it.lease == lease }
                    if (old == null) { reply.success(null); done() } else clearOwned(old) { clean ->
                        if (clean) reply.success(null)
                        else reply.error("article_cleanup_pending", "Article session is closing", null)
                        done()
                    }
                }
                "releaseDownload" -> {
                    val id = call.argument<String>("id") ?: ""
                    if (!id.matches(Regex("^[a-f0-9]{32}$"))) reply.error("article_export_invalid", "Export unavailable", null)
                    else ArticleWebDownloads.release(lease, id) { clean ->
                        if (clean) reply.success(null) else reply.error("article_export_cleanup", "Export cleanup incomplete", null)
                    }
                }
                "pause", "resume", "back", "reload", "prepareLeave", "state" -> {
                    if (!owns(lease)) {
                        reply.error("article_scope_retired", "Article session ended", null)
                    } else {
                        val view = ArticleWebView.find(lease)
                        if (view == null) reply.error("article_view_unavailable", "Article page unavailable", null)
                        else view.command(call.method, reply)
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }
    fun dispose() {
        disposed = true
        retireAll()
        channel.setMethodCallHandler(null)
    }
}
