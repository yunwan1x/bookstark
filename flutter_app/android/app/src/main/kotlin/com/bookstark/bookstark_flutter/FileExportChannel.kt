package com.bookstark.bookstark_flutter

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Exports a completed private file through Android's Storage Access Framework. */
class FileExportChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bookstark/file_export")
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    private var expectedSize = 0L
    private var expectedHash = ""
    private val requestCode = 0x4253

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "saveFile") {
                result.notImplemented()
            } else if (pending != null) {
                result.error("export_in_progress", "Another file export is in progress", null)
            } else {
                try {
                    val path = call.argument<String>("path") ?: throw IOException("Missing source")
                    val name = call.argument<String>("name") ?: throw IOException("Missing name")
                    val size = call.argument<Number>("size")?.toLong() ?: throw IOException("Missing size")
                    val hash = call.argument<String>("sha256") ?: throw IOException("Missing checksum")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val file = File(path).canonicalFile
                    val roots = listOf(activity.cacheDir.canonicalFile, activity.filesDir.canonicalFile)
                    val owned = roots.any { file.path.startsWith(it.path + File.separator) }
                    if (!owned || !file.isFile || size < 0 || file.length() != size) {
                        throw IOException("Source is not a completed private application file")
                    }
                    if (name.isBlank() || name == "." || name == ".." || name.any { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }) {
                        throw IOException("Invalid export name")
                    }
                    if (!Regex("^[0-9a-f]{64}$").matches(hash)) throw IOException("Invalid checksum")
                    val safeMime = if (Regex("^[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+$").matches(mime)) mime else "application/octet-stream"
                    pending = result
                    source = file
                    expectedSize = size
                    expectedHash = hash
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = safeMime
                        putExtra(Intent.EXTRA_TITLE, name)
                    }
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(intent, requestCode)
                } catch (error: Exception) {
                    pending = null
                    source = null
                    result.error("export_unavailable", error.message ?: "Unable to export", null)
                }
            }
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val reply = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            source = null
            reply.success(mapOf("saved" to false))
            return true
        }
        if (uri.scheme != "content") {
            pending = null
            source = null
            reply.error("invalid_destination", "The selected destination is not an Android document provider", null)
            return true
        }
        val file = source ?: return true
        val size = expectedSize
        val hash = expectedHash
        executor.execute {
            var count = 0L
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                val output = activity.contentResolver.openOutputStream(uri, "w") ?: throw IOException("Cannot open selected destination")
                output.use { target ->
                    file.inputStream().use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            if (Thread.currentThread().isInterrupted) throw IOException("Export interrupted")
                            val length = input.read(buffer)
                            if (length < 0) break
                            count += length
                            if (count > size) throw IOException("Source grew while exporting")
                            digest.update(buffer, 0, length)
                            target.write(buffer, 0, length)
                        }
                    }
                    target.flush()
                }
                val actualHash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
                if (count != size || actualHash != hash) throw IOException("Exported source does not match expected bytes")
                main.post {
                    if (pending === reply) {
                        pending = null
                        source = null
                        reply.success(mapOf("saved" to true, "bytes" to count, "sha256" to actualHash))
                    }
                }
            } catch (_: Exception) {
                // A provider may have returned an existing document. Never delete an external URI automatically.
                main.post {
                    if (pending === reply) {
                        pending = null
                        source = null
                        reply.error("export_failed", "保存失败，目标位置可能有未完成文件 / Save failed; the destination may contain an incomplete file", null)
                    }
                }
            }
        }
        return true
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pending?.error("export_interrupted", "Export interrupted", null)
        pending = null
        source = null
        executor.shutdownNow()
    }
}
