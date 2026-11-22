package com.bookstark.bookstark_flutter

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.WebResourceResponse
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.Semaphore

/** Ordinary-local presentation raster port. No account, path, general URI or file UI. */
internal class LocalPresentationImageResources(
    private val channel: MethodChannel,
    private val lease: String,
    private val scope: String,
    private val sourceDigest: String,
    private val host: String,
    private val authorized: () -> Boolean
) {
    private data class Resource(val bytes: ByteArray, val mime: String)
    private val cache = mutableMapOf<String, Resource>()
    private val requested = mutableSetOf<String>()
    private val waiting = mutableSetOf<CountDownLatch>()
    private val slots = Semaphore(4, true)
    private val mimes = setOf("image/png", "image/jpeg", "image/gif", "image/webp")
    @Volatile private var closed = false
    private var bytes = 0L
    init {
        require(scope.matches(Regex("[a-f0-9]{64}")) &&
            sourceDigest.matches(Regex("[a-f0-9]{64}")) && lease.length in 1..128)
    }
    private fun alive() = !closed && authorized()
    private fun denied() = WebResourceResponse("text/plain", "UTF-8", 403,
        "Forbidden", mapOf("Cache-Control" to "no-store"), byteArrayOf().inputStream())
    private fun response(resource: Resource) = WebResourceResponse(
        resource.mime, null, 200, "OK", mapOf("Cache-Control" to "no-store",
            "Access-Control-Allow-Origin" to "*", "X-Content-Type-Options" to "nosniff",
            "Referrer-Policy" to "no-referrer"), resource.bytes.inputStream())
    fun read(uri: Uri): WebResourceResponse {
        val parts = uri.pathSegments
        if (!alive() || uri.scheme != "https" || uri.host != host ||
            uri.userInfo != null || uri.port != -1 ||
            uri.query != null || uri.fragment != null || uri.toString().length > 1024 ||
            parts.size != 3 || parts[0] != "local-presentation" ||
            parts[1] != scope || !parts[2].matches(Regex("[a-f0-9]{64}")) ||
            uri.encodedPath != "/local-presentation/$scope/" + parts[2] ||
            Looper.myLooper() == Looper.getMainLooper()) return denied()
        val key = parts[2]
        synchronized(cache) {
            if (!alive()) return denied()
            cache[key]?.let { return response(it) }
            if (key !in requested && requested.size >= 32) return denied()
            requested.add(key)
        }
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
        val acquired = try {
            slots.tryAcquire(15, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
        if (!acquired) return denied()
        val done = CountDownLatch(1)
        synchronized(waiting) {
            if (!alive()) { slots.release(); return denied() }
            waiting.add(done)
        }
        var result: Resource? = null
        Handler(Looper.getMainLooper()).post {
            if (!alive()) done.countDown()
            else channel.invokeMethod("localPresentationImageResource", mapOf(
                "lease" to lease, "scope" to scope, "sourceDigest" to sourceDigest,
                "resourceId" to key), object : MethodChannel.Result {
                override fun success(value: Any?) {
                    try {
                        val map = value as? Map<*, *> ?: error("Missing raster")
                        val data = map["bytes"] as? ByteArray ?: error("Missing bytes")
                        val mime = map["mime"] as? String ?: error("Missing type")
                        check(map.keys == setOf("bytes", "mime") &&
                            data.size in 1..(5*1024*1024) && mime in mimes)
                        synchronized(cache) {
                            if (alive()) {
                                val prior = cache[key]
                                if (prior != null) result = prior
                                else if (bytes + data.size <= 20L*1024*1024) {
                                    val entry = Resource(data.copyOf(), mime)
                                    cache[key] = entry
                                    bytes += data.size
                                    result = entry
                                }
                            }
                        }
                    } catch (_: Exception) { /* Source remains untouched. */ }
                    finally { done.countDown() }
                }
                override fun error(code: String, message: String?, details: Any?) {
                    done.countDown()
                }
                override fun notImplemented() { done.countDown() }
            })
        }
        return try {
            if (!done.await(maxOf(0L, deadline - System.nanoTime()),
                TimeUnit.NANOSECONDS) || !alive()) denied()
            else result?.let { response(it) } ?: denied()
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            denied()
        } finally {
            synchronized(waiting) { waiting.remove(done) }
            slots.release()
        }
    }
    fun close() {
        closed = true
        synchronized(waiting) { waiting.forEach { it.countDown() }; waiting.clear() }
        synchronized(cache) { cache.clear(); requested.clear(); bytes = 0L }
    }
}
