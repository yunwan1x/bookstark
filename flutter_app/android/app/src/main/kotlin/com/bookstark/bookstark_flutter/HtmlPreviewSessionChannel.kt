package com.bookstark.bookstark_flutter

import android.webkit.CookieManager
import android.webkit.WebStorage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.URI
import java.util.ArrayDeque

/** Browser-only session: token remains HttpOnly, and old leases cannot erase new ones. */
class HtmlPreviewSessionChannel(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bookstark/html_preview_session")
    companion object {
        private val pending = ArrayDeque<(() -> Unit) -> Unit>()
        private var running = false
        @Volatile private var lease: String? = null
        @Volatile private var local = false
        @Volatile private var publicPreview = false
        fun ownsLocalLease(value: String): Boolean = local && lease == value
        fun ownsPublicLease(value: String): Boolean = publicPreview && lease == value
        private fun enqueue(work: (() -> Unit) -> Unit) {
            pending.add(work)
            drain()
        }
        private fun drain() {
            if (running || pending.isEmpty()) return
            running = true
            pending.removeFirst().invoke {
                running = false
                drain()
            }
        }
    }
    init {
        channel.setMethodCallHandler { call, result ->
            val key = call.argument<String>("lease")
            if (key.isNullOrEmpty() || key.length > 128) {
                result.error("invalid_session", "Invalid preview lease", null)
            } else when (call.method) {
                "open" -> {
                    val server = call.argument<String>("server")
                    val cookies = call.argument<Map<String, String>>("cookies")
                    val uri = try { URI(server ?: "") } catch (_: Exception) { null }
                    if (uri == null || uri.scheme !in listOf("http", "https") ||
                        uri.host.isNullOrEmpty() || uri.rawUserInfo != null ||
                        uri.rawQuery != null || uri.rawFragment != null || cookies == null ||
                        cookies.keys.any { it !in listOf("token", "csrf_token") } ||
                        cookies["token"].isNullOrEmpty() ||
                        cookies.values.any { it.length > 32768 || it.any { c -> c.code < 0x21 || c.code > 0x7e || c.code == 59 } }) {
                        result.error("invalid_session", "Invalid preview session", null)
                    } else enqueue { done ->
                        LocalHtmlPreviewView.retireAll()
                        ComplexEditorView.retireAll()
                    ArticleWebSessionChannel.retireAll()
                        val manager = CookieManager.getInstance()
                        manager.setAcceptCookie(true)
                        manager.removeAllCookies {
                            WebStorage.getInstance().deleteAllData()
                            val values = cookies.entries.toList()
                            fun install(index: Int) {
                                if (index == values.size) {
                                    lease = key
                                    local = false
                                    publicPreview = false
                                    // Session cookies are deliberately never flushed to disk here.
                                    result.success(null)
                                    done()
                                    return
                                }
                                val entry = values[index]
                                val secure = if (uri.scheme == "https") "; Secure" else ""
                                val httpOnly = if (entry.key == "token") "; HttpOnly" else ""
                                manager.setCookie(server!!, "${entry.key}=${entry.value}; Path=/; SameSite=Lax$secure$httpOnly") { accepted ->
                                    if (accepted) install(index + 1) else {
                                        manager.removeAllCookies {
                                            lease = null
                                            result.error("cookie_rejected", "Preview authentication failed", null)
                                            done()
                                        }
                                    }
                                }
                            }
                            install(0)
                        }
                    }
                }
                "openLocal" -> enqueue { done ->
                    LocalHtmlPreviewView.retireAll()
                    ComplexEditorView.retireAll()
                    ArticleWebSessionChannel.retireAll()
                    val manager = CookieManager.getInstance()
                    manager.removeAllCookies {
                        manager.setAcceptCookie(false)
                        WebStorage.getInstance().deleteAllData()
                        lease = key
                        local = true
                        publicPreview = false
                        result.success(null)
                        done()
                    }
                }
                "openPublic" -> enqueue { done ->
                    LocalHtmlPreviewView.retireAll()
                    ComplexEditorView.retireAll()
                    ArticleWebSessionChannel.retireAll()
                    val manager = CookieManager.getInstance()
                    manager.removeAllCookies {
                        manager.setAcceptCookie(false)
                        WebStorage.getInstance().deleteAllData()
                        lease = key
                        local = false
                        publicPreview = true
                        result.success(null)
                        done()
                    }
                }
                "close" -> enqueue { done ->
                    if (lease != key) {
                        result.success(null)
                        done()
                    } else {
                        LocalHtmlPreviewView.retireAll()
                        ComplexEditorView.retireAll()
                    ArticleWebSessionChannel.retireAll()
                        CookieManager.getInstance().removeAllCookies {
                            CookieManager.getInstance().setAcceptCookie(true)
                            local = false
                            publicPreview = false
                            lease = null
                            WebStorage.getInstance().deleteAllData()
                            result.success(null)
                            done()
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun dispose() { channel.setMethodCallHandler(null) }
}
