package com.bookstark.bookstark_flutter

import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.system.Os
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Export staging only: caller must still confirm a system save location. */
object ArticleWebDownloads {
    private const val limit = 32L * 1024 * 1024
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val jobs = ConcurrentHashMap<String, Job>()
    private val owners = ConcurrentHashMap<ArticleWebView, String>()
    private class Job(val id: String, val owner: ArticleWebView, val url: String, var name: String, var mime: String) {
        @Volatile var cancelled = false
        @Volatile var connection: HttpURLConnection? = null
        var directory: File? = null
        var output: FileOutputStream? = null
        var digest = MessageDigest.getInstance("SHA-256")
        var bytes = 0L
        var total = -1L
        var index = 0
        var ready = false
        val deadline = System.nanoTime() + 60L * 1_000_000_000
        fun check() {
            if (cancelled || !owner.current() || System.nanoTime() > deadline) throw IOException("Export retired")
        }
    }
    private fun safeName(value: String): String {
        val cleaned = value.map { if (it == '/' || it == '\\' || it.code < 32 || it.code == 127) '_' else it }
            .joinToString("").trim().trim('.')
        val bounded = StringBuilder()
        var bytes = 0
        cleaned.codePoints().toArray().forEach { point ->
            val unit = String(Character.toChars(point))
            val length = unit.toByteArray(Charsets.UTF_8).size
            if (bytes + length <= 240) { bounded.append(unit); bytes += length }
        }
        return if (bounded.isBlank()) "article-export.bin" else bounded.toString()
    }
    private fun safeMime(value: String): String {
        val mime = value.substringBefore(';').trim()
        return if (mime.matches(Regex("^[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+$"))) mime else "application/octet-stream"
    }
    fun start(owner: ArticleWebView, url: String, disposition: String?, mime: String?) {
        if (!owner.current() || url.length > 8192) return
        val previous = owners[owner]?.let { jobs[it] }
        if (previous != null) {
            if (previous.url != url) owner.event("operationError", mapOf("reason" to "download-busy"))
            return
        }
        val state = owner.profileSession() ?: return
        val routes = ArticleWebRoutes(state.server, state.cookiePath)
        val blob = url.startsWith("blob:${routes.origin}/")
        val target = if (!blob) approved(url, state) else null
        if (!blob && target == null) {
            owner.event("operationError", mapOf("reason" to "download-address")); return
        }
        val suggested = if (blob) disposition ?: "article-export.bin"
            else android.webkit.URLUtil.guessFileName(url, disposition, mime)
        val id = UUID.randomUUID().toString().replace("-", "")
        val job = Job(id, owner, url, safeName(suggested), safeMime(mime ?: "application/octet-stream"))
        jobs[id] = job; owners[owner] = id
        worker.execute {
            try {
                job.check()
                if (StatFs(owner.hostActivity().cacheDir.path).availableBytes < limit + 128L*1024*1024) throw IOException("Export capacity")
                // Android may expose /data/user/0 while Java resolves /data/data.
                // Normalize the trusted Context capability before checking owned children.
                val root = File(owner.hostActivity().cacheDir.canonicalFile, "article-web-downloads-v1")
                if (!root.exists() && !root.mkdir()) throw IOException("Cannot prepare export")
                if (!root.isDirectory || root.canonicalFile != root.absoluteFile) throw IOException("Untrusted export root")
                Os.chmod(root.path, 448)
                val folder = File(root, id)
                if (!folder.mkdir()) throw IOException("Export identity exists")
                Os.chmod(folder.path, 448); job.directory = folder
                File(folder, "owned.json").writeText(JSONObject(mapOf("format" to 1, "id" to id,
                    "lease" to owner.ownedLease())).toString())
                Os.chmod(File(folder, "owned.json").path, 384)
                job.output = FileOutputStream(File(folder, "content.part"))
                Os.chmod(File(folder, "content.part").path, 384)
                if (blob) main.post {
                    if (owner.current() && !job.cancelled) owner.evaluate(
                        "window.__bookstarkReadArticleBlob(${JSONObject.quote(id)},${JSONObject.quote(url)});")
                    else fail(job, "download-retired")
                } else download(job, target!!)
            } catch (_: Exception) { fail(job, "download") }
        }
        main.postDelayed({
            if (!job.ready && jobs[id] === job) { job.cancelled = true; job.connection?.disconnect()
                worker.execute { fail(job, "download-timeout") } }
        }, 65000)
    }
    private fun approved(url: String, state: ArticleWebSessionChannel.Session): URI? {
        val uri = ArticleWebRoutes(state.server, state.cookiePath).normalized(url) ?: return null
        val prefix = state.server.path.trimEnd('/')
        val path = uri.path.removePrefix(prefix)
        return uri.takeIf { path.startsWith("/upload-files/") ||
            path.matches(Regex("^/api/blogs/[1-9][0-9]*/export(?:/[A-Za-z0-9_-]+)?$")) }
    }
    private fun download(job: Job, first: URI) {
        val state = job.owner.profileSession() ?: throw IOException("Export retired")
        var target = first
        for (attempt in 0..3) {
            job.check()
            val connection = target.toURL().openConnection() as HttpURLConnection
            job.connection = connection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 10000; connection.readTimeout = 15000
                connection.setRequestProperty("Accept-Encoding", "identity")
                state.profile.cookieManager.getCookie(target.toString())?.let { connection.setRequestProperty("Cookie", it) }
                val status = connection.responseCode
                if (status in 300..399) {
                    val next = target.resolve(connection.getHeaderField("Location") ?: throw IOException("Invalid redirect"))
                    target = approved(next.toString(), state) ?: throw IOException("Export redirect outside scope")
                    if (attempt == 3) throw IOException("Too many redirects")
                    continue
                }
                if (status != 200 || connection.contentLengthLong > limit) throw IOException("Export response unavailable")
                job.mime = safeMime(connection.contentType ?: job.mime)
                connection.getHeaderField("Content-Disposition")?.let {
                    job.name = safeName(android.webkit.URLUtil.guessFileName(target.toString(), it, job.mime))
                }
                connection.inputStream.use { input ->
                    val buffer = ByteArray(32768)
                    while (true) {
                        job.check()
                        val count = input.read(buffer)
                        if (count < 0) break
                        append(job, buffer, count)
                    }
                }
                finish(job); return
            } finally { connection.disconnect(); job.connection = null }
        }
    }
    fun message(owner: ArticleWebView, value: String) {
        if (!owner.current() || value.length > 128 * 1024) return
        val data = try { JSONObject(value) } catch (_: Exception) { return }
        if (data.optString("kind") == "download") {
            main.post { start(owner, data.optString("url"), data.optString("name"), null) }
            return
        }
        val id = data.optString("id")
        if (!id.matches(Regex("^[a-f0-9]{32}$"))) return
        val job = jobs[id]?.takeIf { it.owner === owner && !it.ready } ?: return
        worker.execute {
            if (job.ready || jobs[id] !== job) return@execute
            try {
                job.check()
                when (data.optString("kind")) {
                    "start" -> {
                        if (job.total != -1L || job.bytes != 0L) throw IOException("Export already started")
                        job.total = data.getLong("total")
                        if (job.total !in 0..limit) throw IOException("Export size")
                        job.mime = safeMime(data.optString("mime"))
                    }
                    "chunk" -> {
                        if (job.total < 0 || data.getInt("index") != job.index++) throw IOException("Export chunk order")
                        val encoded = data.getString("data")
                        if (encoded.length > 90000 || encoded.length % 4 != 0 ||
                            !encoded.matches(Regex("^[A-Za-z0-9+/]*={0,2}$"))) throw IOException("Invalid export chunk")
                        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
                        if (bytes.size > 65536) throw IOException("Export chunk limit")
                        append(job, bytes, bytes.size)
                        if (job.bytes > job.total) throw IOException("Export size mismatch")
                    }
                    "end" -> {
                        if (job.total < 0 || job.total != job.bytes) throw IOException("Incomplete export")
                        finish(job)
                    }
                    else -> throw IOException("Export failed")
                }
            } catch (_: Exception) { fail(job, "download") }
        }
    }
    private fun append(job: Job, data: ByteArray, count: Int) {
        job.check()
        if (count < 0 || job.bytes + count > limit) throw IOException("Export size limit")
        job.output?.write(data, 0, count) ?: throw IOException("Export not open")
        job.digest.update(data, 0, count); job.bytes += count
    }
    private fun finish(job: Job) {
        job.check()
        val folder = job.directory ?: throw IOException("Export missing")
        job.output?.fd?.sync(); job.output?.close(); job.output = null
        if (!File(folder, "content.part").renameTo(File(folder, "content.bin"))) throw IOException("Export rename failed")
        val sha = job.digest.digest().joinToString("") { "%02x".format(it) }
        val receipt = mapOf("format" to 1, "id" to job.id, "bytes" to job.bytes,
            "sha256" to sha, "name" to job.name, "mime" to job.mime)
        File(folder, "ready.json").writeText(JSONObject(receipt).toString())
        Os.chmod(File(folder, "ready.json").path, 384)
        job.ready = true
        main.post {
            if (job.owner.current() && !job.cancelled) job.owner.event("downloadReady", receipt)
            else worker.execute { cleanup(job) }
        }
    }
    private fun fail(job: Job, reason: String) {
        job.cancelled = true; job.connection?.disconnect()
        try { cleanup(job) } catch (_: Exception) {}
        main.post { if (job.owner.current()) job.owner.event("operationError", mapOf("reason" to reason)) }
    }
    private fun cleanup(job: Job) {
        job.output?.close(); job.output = null
        val folder = job.directory
        if (folder != null && folder.exists()) {
            if (folder.canonicalFile != folder.absoluteFile || folder.name != job.id) throw IOException("Export cleanup refused")
            val children = folder.listFiles() ?: throw IOException("Export cleanup unavailable")
            if (children.any { it.name !in setOf("owned.json", "content.part", "content.bin", "ready.json") ||
                    !it.isFile || it.canonicalFile.parentFile != folder.canonicalFile }) throw IOException("Unknown export file")
            children.forEach { if (!it.delete()) throw IOException("Export cleanup incomplete") }
            if (!folder.delete()) throw IOException("Export cleanup incomplete")
        }
        jobs.remove(job.id, job); owners.remove(job.owner, job.id)
    }
    fun release(lease: String, id: String, complete: (Boolean) -> Unit) {
        val job = jobs[id]?.takeIf { it.owner.ownedLease() == lease }
        if (job == null) { complete(true); return }
        job.cancelled = true; job.connection?.disconnect()
        worker.execute {
            val clean = try { cleanup(job); true } catch (_: Exception) { false }
            main.post { complete(clean) }
        }
    }
    fun retire(owner: ArticleWebView) {
        val job = owners[owner]?.let { jobs[it] } ?: return
        job.cancelled = true; job.connection?.disconnect()
        worker.execute { try { cleanup(job) } catch (_: Exception) {} }
    }
}
