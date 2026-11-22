package com.bookstark.bookstark_flutter

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.WebResourceResponse
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Passive generation-owned raster bytes only. No server, account identity,
 * password, local path, cookie or networking capability crosses this bridge. */
internal class Owned15GenerationResources(
    private val channel: MethodChannel,
    private val lease: String,
    private val resourceScope: String,
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
        200, "OK", mapOf("Cache-Control" to "no-store",
            "X-Content-Type-Options" to "nosniff", "Referrer-Policy" to "no-referrer"),
        value.bytes.inputStream())
    fun read(uri: Uri): WebResourceResponse {
        if (!alive() || uri.scheme != null || uri.authority != null ||
            uri.query != null || uri.fragment != null ||
            !resourceScope.matches(Regex("[a-f0-9]{64}")) ||
            !uri.encodedPath.orEmpty().startsWith("/upload-files/") ||
            uri.pathSegments.any { it.isEmpty() || it == "." || it == ".." ||
                it.contains("/") || it.contains("\\\\") || it.contains("%") ||
                it.any { c -> c.code < 32 || c.code == 127 } }) return denied()
        val key = uri.toString()
        synchronized(cache) {
            if (!alive() || key in failed) return denied()
            cache[key]?.let { return response(it) }
            if (key !in requested && requested.size >= 32) return denied()
            requested.add(key)
        }
        if (Looper.myLooper() == Looper.getMainLooper()) return denied()
        val done = CountDownLatch(1)
        synchronized(waiting) { if(!alive() || waiting.size >= 4) return denied();waiting.add(done) }
        var value: Resource? = null
        Handler(Looper.getMainLooper()).post {
            if (!alive()) done.countDown()
            else channel.invokeMethod("generationResource", mapOf("lease" to lease, "resourceScope" to resourceScope, "url" to key),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        try {
                            val row = result as? Map<*, *> ?: error("Missing generation resource")
                            check(row.keys == setOf("resourceScope", "bytes", "mime", "sha256"))
                            check(row["resourceScope"] == resourceScope)
                            val data = row["bytes"] as? ByteArray ?: error("Missing resource bytes")
                            val mime = row["mime"] as? String ?: error("Missing resource type")
                            check(data.isNotEmpty() && data.size <= 5 * 1024 * 1024 && mime in mimes)
                            val hash = row["sha256"] as? String ?: error("Missing checksum")
                            check(hash.matches(Regex("[a-f0-9]{64}")))
                            val actual = java.security.MessageDigest.getInstance("SHA-256")
                                .digest(data).joinToString("") { "%02x".format(it.toInt() and 255) }
                            check(actual == hash)
                            if(mime.startsWith("image/")) {
                                val dimensions = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                                android.graphics.BitmapFactory.decodeByteArray(data, 0, data.size, dimensions)
                                check(dimensions.outWidth in 1..8192 && dimensions.outHeight in 1..8192 &&
                                    dimensions.outWidth.toLong() * dimensions.outHeight <= 16L * 1024 * 1024)
                            }
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
        synchronized(cache) { cache.values.forEach { it.bytes.fill(0) };cache.clear();requested.clear();failed.clear();bytes = 0 }
    }
}
