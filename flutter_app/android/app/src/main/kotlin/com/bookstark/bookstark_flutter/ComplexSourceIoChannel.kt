package com.bookstark.bookstark_flutter

import android.app.Activity
import android.content.Intent
import android.content.res.AssetFileDescriptor
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.OpenableColumns
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.ScheduledFuture

/** Explicit SOURCE I/O only. No file paths, URI grants or cache staging leave this channel. */
class ComplexSourceIoChannel(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        private val channels = mutableSetOf<ComplexSourceIoChannel>()
        @Volatile private var scopeEpoch = 0L
        @Volatile private var scopeHash: String? = null
        private fun matchesScope(hash: String, epoch: Long) = scopeHash == hash && scopeEpoch == epoch
        fun ownsScope(hash: String, epoch: Long): Boolean = matchesScope(hash, epoch)
        @Synchronized private fun replaceScope(hash: String?, expected: Long): Long {
            if (scopeEpoch != expected) throw IOException()
            scopeHash = null; scopeEpoch++
            channels.toList().forEach { it.retireAll() }
            ComplexEditorView.retireAll()
            scopeHash = hash
            return scopeEpoch
        }
    }
    private val channel = MethodChannel(messenger, "bookstark/complex_source_io")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val requestCode = 0x4261
    private val ids = Regex("^[a-f0-9]{32}$")
    private val hashes = Regex("^[a-f0-9]{64}$")
    @Volatile private var job: Job? = null
    @Volatile private var disposed = false
    private class Job(val id: String, val importing: Boolean, val limit: Long,
        val name: String, val mime: String, val expectedHash: String?,
        val owns: () -> Boolean, var pickerReply: MethodChannel.Result?) {
        val signal = CancellationSignal()
        val digest = MessageDigest.getInstance("SHA-256")
        @Volatile var cancelled = false
        @Volatile var awaitingPicker = true
        @Volatile var input: InputStream? = null
        @Volatile var output: OutputStream? = null
        @Volatile var asset: AssetFileDescriptor? = null
        @Volatile var descriptor: ParcelFileDescriptor? = null
        var index = 0
        var bytes = 0L
        var eof = false
        var busy = false
        @Volatile var deadline = Long.MAX_VALUE
        var deadlineTask: ScheduledFuture<*>? = null
        fun close() {
            deadlineTask?.cancel(false); deadlineTask = null
            try { input?.close() } catch (_: Exception) {}
            try { output?.close() } catch (_: Exception) {}
            try { asset?.close() } catch (_: Exception) {}
            try { descriptor?.close() } catch (_: Exception) {}
            input = null; output = null; asset = null; descriptor = null
        }
        fun cancel() { cancelled = true; signal.cancel(); close() }
    }
    init {
        channels.add(this)
        channel.setMethodCallHandler { call, reply ->
            try {
                if (call.method == "scopeState") {
                    reply.success(mapOf("epoch" to scopeEpoch)); return@setMethodCallHandler
                }
                if (call.method == "activateScope") {
                    val hash = call.argument<String>("scope") ?: throw IOException()
                    val expected = call.argument<Number>("expectedEpoch")?.toLong() ?: throw IOException()
                    if (!hashes.matches(hash)) throw IOException()
                    reply.success(mapOf("epoch" to replaceScope(hash, expected))); return@setMethodCallHandler
                }
                if (call.method == "retireScope") {
                    val hash = call.argument<String>("scope") ?: throw IOException()
                    val expected = call.argument<Number>("epoch")?.toLong() ?: throw IOException()
                    if (matchesScope(hash, expected)) replaceScope(null, expected)
                    reply.success(mapOf("retired" to true)); return@setMethodCallHandler
                }
                val id = call.argument<String>("id") ?: throw IOException()
                if (!ids.matches(id)) throw IOException()
                when (call.method) {
                    "pickImport", "beginExport" -> {
                        if (disposed || job != null) throw IOException()
                        val lease = call.argument<String>("lease") ?: throw IOException()
                        val generation = call.argument<Int>("generation") ?: throw IOException()
                        val requestedExportHash = if (call.method == "beginExport") call.argument<String>("sha256") else null
                        val browserOwns = ComplexEditorView.sourceIoAuthorization(lease, generation, requestedExportHash, call.argument<Number>("bytes")?.toLong()) ?: throw IOException()
                        if (!browserOwns()) throw IOException()
                        val ownerScope = call.argument<String>("scope") ?: throw IOException()
                        val ownerEpoch = call.argument<Number>("epoch")?.toLong() ?: throw IOException()
                        if (!matchesScope(ownerScope, ownerEpoch)) throw IOException()
                        // Explicit SAF handoff latches only this job capability.
                        // Browser retirement during SAF is expected; native scope
                        // retirement independently invalidates every chunk.
                        val owns = { !disposed && !activity.isFinishing && !activity.isDestroyed && matchesScope(ownerScope, ownerEpoch) }
                        val importing = call.method == "pickImport"
                        val limit = call.argument<Number>("bytes")?.toLong() ?: throw IOException()
                        val ownedReview = !importing && requestedExportHash != null &&
                            ComplexEditorView.ownsReviewExport(lease, generation, requestedExportHash, limit)
                        if (limit < 0 || limit > (if (ownedReview) 32L else 20L) * 1024 * 1024) throw IOException()
                        val name = if (importing) "" else safeName(call.argument<String>("name") ?: "")
                        val mime = if (importing) "*/*" else call.argument<String>("mime") ?: ""
                        if (!importing && !Regex("^[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+$").matches(mime)) throw IOException()
                        val hash = if (importing) null else call.argument<String>("sha256")
                        if (!importing && (hash == null || !hashes.matches(hash))) throw IOException()
                        val current = Job(id, importing, limit, name, mime, hash, owns, reply)
                        job = current
                        val intent = Intent(if (importing) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE); type = mime
                            if (!importing) putExtra(Intent.EXTRA_TITLE, name)
                        }
                        try {
                            @Suppress("DEPRECATION")
                            activity.startActivityForResult(intent, requestCode)
                        } catch (_: Exception) { job = null; throw IOException() }
                    }
                    "readImport" -> {
                        val current = requireJob(id, true)
                        if (current.eof || call.argument<Int>("index") != current.index) throw IOException()
                        execute(current, reply) {
                            val buffer = ByteArray(262144)
                            val n = current.input?.read(buffer) ?: throw IOException()
                            if (n < 0) {
                                current.eof = true
                                val hash = hex(current.digest.digest()); current.close()
                                mapOf("id" to id, "index" to current.index, "bytes" to current.bytes,
                                    "data" to "", "done" to true, "sha256" to hash)
                            } else {
                                if (n == 0 || current.bytes + n > current.limit) throw IOException()
                                current.bytes += n; current.digest.update(buffer, 0, n)
                                mapOf("id" to id, "index" to current.index++, "bytes" to current.bytes,
                                    "data" to Base64.encodeToString(buffer.copyOf(n), Base64.NO_WRAP), "done" to false)
                            }
                        }
                    }
                    "writeExport" -> {
                        val current = requireJob(id, false)
                        if (call.argument<Int>("index") != current.index) throw IOException()
                        val encoded = call.argument<String>("data") ?: throw IOException()
                        if (encoded.length > 349528 || !Regex("^[A-Za-z0-9+/]*={0,2}$").matches(encoded)) throw IOException()
                        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
                        if (bytes.isEmpty() || bytes.size > 262144 || current.bytes + bytes.size > current.limit) throw IOException()
                        execute(current, reply) {
                            current.output?.write(bytes) ?: throw IOException()
                            current.digest.update(bytes); current.bytes += bytes.size
                            mapOf("id" to id, "index" to current.index++, "bytes" to current.bytes)
                        }
                    }
                    "finishExport" -> {
                        val current = requireJob(id, false)
                        execute(current, reply, ending = true) {
                            if (current.bytes != current.limit || hex(current.digest.digest()) != current.expectedHash) throw IOException()
                            current.output?.flush() ?: throw IOException()
                            val actualSize = current.descriptor?.statSize ?: -1L
                            if (actualSize >= 0 && actualSize != current.limit) throw IOException()
                            // Provider close must succeed before saved is reported. This is a
                            // complete write acknowledgment, not a claim about provider disk fsync.
                            current.output?.close(); current.output = null
                            current.descriptor?.close(); current.descriptor = null
                            mapOf("id" to id, "saved" to true, "bytes" to current.bytes, "sha256" to current.expectedHash)
                        }
                    }
                    "releaseImport", "cancel" -> {
                        val current = job?.takeIf { it.id == id } ?: throw IOException()
                        current.cancel()
                        // Preserve a cancelled picker slot until its actual activity result.
                        // Otherwise a late result could be assigned to a new request.
                        if (!current.awaitingPicker) job = null
                        reply.success(mapOf("id" to id, "cancelled" to true))
                    }
                    else -> reply.notImplemented()
                }
            } catch (_: Exception) { reply.error("source_io_unavailable", "Source file operation unavailable", null) }
        }
    }
    private fun safeName(raw: String): String {
        if (raw.isEmpty() || raw.toByteArray(Charsets.UTF_8).size > 512 ||
            raw == "." || raw == ".." || raw.any { it.code < 32 || it.code == 127 || it == '/' || it == '\\' }) throw IOException()
        return raw
    }
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun check(current: Job) {
        if (disposed || job !== current || current.cancelled || !current.owns() || SystemClock.elapsedRealtime() > current.deadline) { current.cancel(); throw IOException() }
    }
    private fun requireJob(id: String, importing: Boolean): Job {
        val current = job?.takeIf { it.id == id && it.importing == importing && !it.awaitingPicker } ?: throw IOException()
        check(current); if (current.busy) throw IOException(); return current
    }
    private fun execute(current: Job, reply: MethodChannel.Result, ending: Boolean = false, action: () -> Any?) {
        if (current.busy) { reply.error("source_io_busy", "Source file operation busy", null); return }
        current.busy = true
        worker.execute {
            val watchdog = timer.schedule({ current.cancel() }, 20, TimeUnit.SECONDS)
            try {
                check(current); val value = action(); check(current)
                main.post { current.busy = false; try { check(current); if (ending) { current.close(); job = null }; reply.success(value) }
                    catch (_: Exception) { reply.error("source_io_retired", "Source file operation retired", null) } }
            } catch (_: Exception) {
                current.cancel()
                main.post { current.busy = false; if (job === current && !current.awaitingPicker) job = null
                    reply.error("source_io_unconfirmed", "Source file operation failed; destination may contain partial data", null) }
            } finally { watchdog.cancel(false) }
        }
    }
    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val current = job ?: return true
        current.awaitingPicker = false
        val reply = current.pickerReply ?: return true
        current.pickerReply = null
        val uri = data?.data
        if (current.cancelled || !current.owns() || resultCode != Activity.RESULT_OK || uri == null) {
            current.cancel(); if (job === current) job = null
            reply.success(mapOf("id" to current.id, "cancelled" to true)); return true
        }
        if (uri.scheme != "content") {
            current.cancel(); job = null; reply.error("source_io_uri", "A system document provider is required", null); return true
        }
        current.deadline = SystemClock.elapsedRealtime() + 180000L
        current.deadlineTask = timer.schedule({ current.cancel() }, 180, TimeUnit.SECONDS)
        execute(current, reply) {
            if (current.importing) {
                var name = ""
                activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null, null, null, current.signal)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIndex >= 0 && !cursor.isNull(sizeIndex) && cursor.getLong(sizeIndex) > current.limit) throw IOException()
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex >= 0) name = cursor.getString(nameIndex) ?: ""
                    }
                }
                name = safeName(name)
                val afd = activity.contentResolver.openAssetFileDescriptor(uri, "r", current.signal) ?: throw IOException()
                current.asset = afd
                if (afd.length > current.limit) throw IOException()
                current.input = afd.createInputStream()
                val mime = activity.contentResolver.getType(uri) ?: "application/octet-stream"
                if (mime.length > 128) throw IOException()
                mapOf("id" to current.id, "name" to name, "mime" to mime)
            } else {
                val descriptor = activity.contentResolver.openFileDescriptor(uri, "wt", current.signal) ?: throw IOException()
                current.descriptor = descriptor; current.output = ParcelFileDescriptor.AutoCloseOutputStream(descriptor)
                mapOf("id" to current.id, "ready" to true)
            }
        }
        return true
    }
    fun onHostStopped() { if (job?.awaitingPicker != true) retireAll() }
    fun retireAll() {
        job?.let { current -> current.cancel(); if (!current.awaitingPicker) job = null }
    }
    fun dispose() { disposed = true; channels.remove(this); retireAll(); channel.setMethodCallHandler(null); worker.shutdownNow(); timer.shutdownNow() }
}
