package com.bookstark.bookstark_flutter

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** No external paths or URI persist; only bounded random private inbox files. */
class LocalArticleAttachmentPickerChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bookstark/local_article_attachment_picker")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val requestCode = 0x4256
    private val ids = Regex("^[a-f0-9]{32}$")
    private val limit = 64L * 1024 * 1024
    private val reserve = 128L * 1024 * 1024
    private var pending: Job? = null
    private var disposed = false

    private class Job(val id: String, val reply: MethodChannel.Result, val maxBytes: Long) {
        val signal = CancellationSignal()
        @Volatile var cancelled = false
        @Volatile var descriptor: android.content.res.AssetFileDescriptor? = null
        var copying = false
        fun cancel() {
            cancelled = true
            signal.cancel()
            try { descriptor?.close() } catch (_: Exception) {}
        }
    }

    init {
        channel.setMethodCallHandler { call, reply ->
            try {
                val id = call.argument<String>("id") ?: throw IOException("Missing identity")
                if (!ids.matches(id)) throw IOException("Invalid identity")
                when (call.method) {
                    "pick" -> {
                        if (disposed || pending != null) throw IOException("Picker busy")
                        val rawImagesOnly = call.argument<Any>("imagesOnly")
                        if(rawImagesOnly != null && rawImagesOnly !is Boolean) throw IOException("Invalid picker mode")
                        val imagesOnly = rawImagesOnly == true
                        pending = Job(id, reply, if(imagesOnly) 5L * 1024 * 1024 else limit)
                        try {
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = if(imagesOnly) "image/*" else "*/*"
                                if(imagesOnly) putExtra(Intent.EXTRA_MIME_TYPES,
                                    arrayOf("image/png","image/jpeg","image/gif","image/webp"))
                            }
                            @Suppress("DEPRECATION")
                            activity.startActivityForResult(intent, requestCode)
                        } catch (_: Exception) {
                            pending = null
                            throw IOException("Picker unavailable")
                        }
                    }
                    "cancel" -> {
                        pending?.takeIf { it.id == id }?.let { job ->
                            job.cancel()
                            // Keep the slot until this picker result arrives: a late
                            // result must never be attributed to a newer request.
                        }
                        reply.success(mapOf("format" to 1, "cancelled" to true))
                    }
                    "release" -> {
                        if (pending?.id == id) throw IOException("Inbox in use")
                        worker.execute {
                            try {
                                val file = File(inbox(), "$id.attachment")
                                if (file.exists() && (file.canonicalFile != file.absoluteFile ||
                                    !file.isFile || !file.delete())) throw IOException("Release refused")
                                main.post { reply.success(mapOf("format" to 1, "released" to id)) }
                            } catch (_: Exception) {
                                main.post { reply.error("article_attachment_release_failed", "Cannot release private inbox file", null) }
                            }
                        }
                    }
                    else -> reply.notImplemented()
                }
            } catch (_: Exception) {
                reply.error("article_attachment_picker_unavailable", "Cannot access attachment document picker", null)
            }
        }
    }

    private fun inbox(): File {
        val root = File(activity.cacheDir.canonicalFile, "local-article-attachment-inbox-v1")
        if (root.canonicalFile != root.absoluteFile ||
            (!root.isDirectory && !root.mkdir())) throw IOException("Invalid inbox")
        return root
    }

    private fun displayName(uri: android.net.Uri, job: Job): String {
        var name = "attachment"
        activity.contentResolver.query(uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null, null, null, job.signal)?.use { cursor ->
            if(cursor.moveToFirst()) {
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if(sizeIndex >= 0 && !cursor.isNull(sizeIndex) && cursor.getLong(sizeIndex) > job.maxBytes)
                    throw IOException("Oversize attachment")
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if(nameIndex >= 0) name = cursor.getString(nameIndex) ?: name
            }
        }
        name = name.toByteArray(Charsets.UTF_8).toString(Charsets.UTF_8)
            .replace('\\', '/').substringAfterLast('/')
            .map { if(it.code < 32 || it.code == 127) ' ' else it }.joinToString("").trim()
        if(name.length > 180) name = name.take(180)
        if(name.isNotEmpty() && Character.isHighSurrogate(name.last())) name = name.dropLast(1)
        return if(name.isEmpty() || name == "." || name == "..") "attachment" else name
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val job = pending ?: return true
        if (job.copying) return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || job.cancelled) {
            pending = null
            job.reply.success(mapOf("format" to 1, "cancelled" to true))
            return true
        }
        if (uri.scheme != "content") {
            pending = null
            job.reply.error("article_attachment_provider_invalid", "Select an Android document", null)
            return true
        }
        job.copying = true
        val deadline = SystemClock.elapsedRealtime() + 120_000
        val timeout = timer.schedule({ job.cancel() }, 120, TimeUnit.SECONDS)
        worker.execute {
            var owned: File? = null
            var completed: File? = null
            try {
                val root = inbox()
                if (StatFs(root.path).availableBytes < reserve) throw IOException("Insufficient space")
                val part = File(root, "${job.id}.part")
                val target = File(root, "${job.id}.attachment")
                if (part.exists() || target.exists() || !part.createNewFile()) throw IOException("Identity collision")
                owned = part
                val digest = MessageDigest.getInstance("SHA-256")
                var total = 0L
                fun check() {
                    if (job.cancelled || SystemClock.elapsedRealtime() >= deadline ||
                        Thread.currentThread().isInterrupted) throw IOException("Copy interrupted")
                }
                check()
                val name = displayName(uri, job)
                check()
                val descriptor = activity.contentResolver.openAssetFileDescriptor(uri, "r", job.signal)
                    ?: throw IOException("Cannot open document")
                job.descriptor = descriptor
                val declaredLength = descriptor.declaredLength
                descriptor.use { afd ->
                    check()
                    if (afd.declaredLength > job.maxBytes) throw IOException("Oversize document")
                    // Asset stream honours the provider's declared offset and length.
                    afd.createInputStream().use { input ->
                        FileOutputStream(part).use { output ->
                            val poll = StructPollfd().apply {
                                fd = (input as FileInputStream).fd
                                events = OsConstants.POLLIN.toShort()
                            }
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                check()
                                if (StatFs(root.path).availableBytes < reserve + buffer.size) throw IOException("Insufficient space")
                                poll.revents = 0
                                if (Os.poll(arrayOf(poll), 1000) == 0) continue
                                check()
                                val count = input.read(buffer)
                                if (count < 0) break
                                if (count == 0) continue
                                total += count
                                if (total > job.maxBytes) throw IOException("Oversize document")
                                digest.update(buffer, 0, count)
                                output.write(buffer, 0, count)
                            }
                            output.flush()
                            output.fd.sync()
                        }
                    }
                }
                job.descriptor = null
                check()
                if(declaredLength >= 0 && total != declaredLength) throw IOException("Incomplete attachment")
                if (!part.renameTo(target)) throw IOException("Incomplete document")
                owned = null
                completed = target
                val hash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
                main.post {
                    if (!disposed && pending === job && !job.cancelled) {
                        pending = null
                        job.reply.success(mapOf("format" to 1, "cancelled" to false,
                            "id" to job.id, "bytes" to total, "sha256" to hash, "name" to name))
                    } else {
                        target.delete()
                        if (pending === job) {
                            pending = null
                            job.reply.error("article_attachment_import_interrupted", "Attachment copy interrupted", null)
                        }
                    }
                }
            } catch (_: Exception) {
                owned?.delete()
                completed?.delete()
                main.post {
                    if (!disposed && pending === job) {
                        pending = null
                        job.reply.error("article_attachment_import_failed", "Cannot copy attachment: check space, size and document provider", null)
                    }
                }
            } finally {
                timeout.cancel(false)
                job.descriptor = null
            }
        }
        return true
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        pending?.cancel()
        pending?.reply?.error("article_attachment_import_interrupted", "Attachment selection interrupted", null)
        pending = null
        worker.shutdown()
        timer.shutdownNow()
    }
}
