package com.bookstark.bookstark_flutter

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.WebResourceResponse
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Lease-owned raster image access to the existing Dart attachment repository.
 * No network, account, credentials or filesystem paths enter this helper. */
internal class LocalMarkdownImageResources(
    private val channel: MethodChannel,
    private val lease: String,
    private val authorized: () -> Boolean
) {
    private data class Resource(val bytes: ByteArray, val mime: String)
    private val cache = mutableMapOf<String, Resource>()
    private val requested = mutableSetOf<String>()
    private val failed = mutableSetOf<String>()
    private val waiting = mutableSetOf<CountDownLatch>()
    @Volatile private var closed = false
    private var bytes = 0L
    private val mimes = setOf("image/png", "image/jpeg", "image/gif", "image/webp")
    private fun alive() = !closed && authorized()
    private fun denied() = WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden",
        mapOf("Cache-Control" to "no-store"), byteArrayOf().inputStream())
    private fun response(value: Resource): WebResourceResponse = WebResourceResponse(
        value.mime, if(value.mime.startsWith("text/") || value.mime in
            setOf("application/javascript", "text/javascript", "image/svg+xml")) "UTF-8" else null,
        200, "OK", mapOf("Cache-Control" to "no-store", "Access-Control-Allow-Origin" to "*",
            "X-Content-Type-Options" to "nosniff", "Referrer-Policy" to "no-referrer"),
        value.bytes.inputStream())
    fun read(uri: Uri): WebResourceResponse {
        val parts = uri.pathSegments
        if (!alive() || uri.scheme != "bookstark-attachment" ||
            !uri.host.isNullOrEmpty() || uri.port != -1 || uri.userInfo != null ||
            uri.query != null || uri.fragment != null || uri.toString().length > 2048 ||
            parts.size != 2 || !Regex("^[a-f0-9]{32}$").matches(parts[0]) ||
            parts[1].isEmpty() || parts[1].length > 255 || parts[1] in setOf(".", "..") ||
            parts[1].any { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }) return denied()
        val key = parts[0]
        synchronized(cache) {
            if (!alive() || key in failed) return denied()
            cache[key]?.let { return response(it) }
            if (key !in requested && requested.size >= 32) return denied()
            requested.add(key)
        }
        if (Looper.myLooper() == Looper.getMainLooper()) return denied()
        val done = CountDownLatch(1)
        synchronized(waiting) { if(!alive()) return denied();waiting.add(done) }
        var value: Resource? = null
        Handler(Looper.getMainLooper()).post {
            if (!alive()) done.countDown()
            else channel.invokeMethod("localImageResource", mapOf("lease" to lease, "url" to uri.toString()),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        try {
                            val row = result as? Map<*, *> ?: error("Missing public resource")
                            val data = row["bytes"] as? ByteArray ?: error("Missing resource bytes")
                            val mime = row["mime"] as? String ?: error("Missing resource type")
                            check(data.size <= 5 * 1024 * 1024 && mime in mimes)
                            synchronized(cache) {
                                if (alive()) {
                                    val prior = cache[key]
                                    if(prior != null) value = prior
                                    else if(bytes + data.size <= 20 * 1024 * 1024) {
                                        value = Resource(data, mime);cache[key] = value!!;bytes += data.size
                                    }
                                }
                            }
                        } catch(_: Exception) { synchronized(cache) { failed.add(key) } }
                        finally { done.countDown() }
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        synchronized(cache) { failed.add(key) };done.countDown()
                    }
                    override fun notImplemented() { synchronized(cache) { failed.add(key) };done.countDown() }
                })
        }
        return try {
            if(!done.await(15, TimeUnit.SECONDS) || !alive()) denied()
            else value?.let { response(it) } ?: denied()
        } catch(_: InterruptedException) { Thread.currentThread().interrupt();denied() }
        finally { synchronized(waiting) { waiting.remove(done) } }
    }
    fun close() {
        closed = true
        synchronized(waiting) { waiting.forEach { it.countDown() };waiting.clear() }
        synchronized(cache) { cache.clear();requested.clear();failed.clear();bytes = 0 }
    }
}
