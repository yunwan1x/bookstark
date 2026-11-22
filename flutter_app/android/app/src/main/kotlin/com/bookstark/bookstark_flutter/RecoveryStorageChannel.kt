package com.bookstark.bookstark_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.security.MessageDigest
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import android.util.Base64
import org.json.JSONArray

/** Durable barriers and bounded recovery-key metadata. Values never cross this channel. */
class RecoveryStorageChannel(context: Context, messenger: BinaryMessenger) {
    private val application = context.applicationContext
    private val channel = MethodChannel(messenger, "bookstark/recovery_storage")
    companion object {
        private val writer = Executors.newSingleThreadExecutor { work ->
            Thread(work, "bookstark-recovery-sync").apply { isDaemon = true }
        }
        private val main = Handler(Looper.getMainLooper())
        // Pinned flutter_secure_storage 9.2.4's public key prefix; not a key.
        private const val securePrefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_"
        private val draftPrefixes = listOf(
            "bookstark.draft.v1.", "bookstark.file-draft.v1.",
            "bookstark.topic-draft.v1.", "bookstark.bookmark-draft.v1.",
            "bookstark.bookmark-create.v1.", "bookstark.bookmark-create-slot.v1.",
            "bookstark.topic-create.v1.", "bookstark.topic-create-slot.v1.",
            "bookstark.label-create.v1.", "bookstark.label-create-slot.v1.",
            "bookstark.task-create.v1.", "bookstark.task-create-slot.v1.",
            "bookstark.local-task-create.v1.", "bookstark.local-task-create-slot.v1.",
            "bookstark.local-label-create.v1.", "bookstark.local-label-create-slot.v1.",
            "bookstark.book-draft.v1.", "bookstark.task-draft.v1.",
            "bookstark.document-create.v1.",
            "bookstark.owned-image-upload.v1.",
            "bookstark.owned15-create.v1",
                    "bookstark.owned15-save.v1",
            "bookstark.protected-owned-marker.v1.", "bookstark.protectedSharedOp.v1."
        )
    }
    private fun flush(): Boolean {
        val results = listOf(
            "FlutterSecureKeyStorage", "BookstarkHtmlRecovery", "FlutterSecureStorage"
        ).map { name ->
            try {
                application.getSharedPreferences(name, Context.MODE_PRIVATE).edit().commit()
            } catch (_: Exception) { false }
        }
        return results.all { it }
    }
    private fun metadata(): Map<String, Any> {
        val secure = mutableListOf<String>()
        val html = mutableListOf<String>()
        var bytes = 0
        var overflow = false
        for ((name, target) in listOf(
            "FlutterSecureStorage" to secure, "BookstarkHtmlRecovery" to html
        )) {
            // getAll returns encrypted values, but only keys are inspected.
            val keys = application.getSharedPreferences(name, Context.MODE_PRIVATE).all.keys
            check(keys.none { it.startsWith("__androidx_security_crypto_encrypted_prefs_") })
            for (stored in keys) {
                if (!stored.startsWith(securePrefix)) continue
                val key = stored.removePrefix(securePrefix)
                val local = key.startsWith("bookstark.local-")
                val ordinary = draftPrefixes.any { key.startsWith(it) }
                if (!local && !ordinary) continue
                val size = key.toByteArray(Charsets.UTF_8).size
                if (size > 65536 || bytes + size > 1048576 || secure.size + html.size >= 4096) {
                    overflow = true
                    continue
                }
                bytes += size
                target.add(key)
            }
        }
        return mapOf("format" to 1, "secureKeys" to secure.sorted(),
            "htmlKeys" to html.sorted(), "overflow" to overflow, "valuesIncluded" to false)
    }
    private fun articleDraftKey(key: String, creation: Boolean = false): Boolean = try {
        check(key.length in 1..4096 && key.startsWith("bookstark.draft.v1."))
        val suffix = key.removePrefix("bookstark.draft.v1.")
        check(Regex("[A-Za-z0-9_-]+={0,2}").matches(suffix))
        val bytes = Base64.decode(suffix, Base64.URL_SAFE or Base64.NO_WRAP)
        check(Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP) == suffix)
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        val raw = decoder.decode(ByteBuffer.wrap(bytes)).toString()
        val outer = JSONArray(raw)
        check(outer.length() == 2 && outer.get(0) is String)
        val id = outer.get(1)
        if (creation) check(outer.isNull(1))
        else check((id is Int || id is Long) && outer.getLong(1) > 0)
        val namespace = outer.getString(0)
        val scope = JSONArray(namespace)
        check(scope.length() == 2 && scope.get(0) is String && scope.get(1) == "article")
        val base = scope.getString(0)
        check(base == "local" || Regex("local-generation:[a-f0-9]{32}").matches(base))
        check(JSONArray().put(base).put("article").toString() == namespace)
        val canonical = JSONArray().put(namespace)
        if (creation) canonical.put(org.json.JSONObject.NULL) else canonical.put(outer.getLong(1))
        check(canonical.toString() == raw)
        true
    } catch (_: Exception) { false }

    private fun articleFingerprint(key: String, creation: Boolean): Map<String, Any?> {
        check(articleDraftKey(key, creation))
        val preferences = application.getSharedPreferences("FlutterSecureStorage", Context.MODE_PRIVATE)
        val value = preferences.getString(securePrefix + key, null)
        val bytes = value?.toByteArray(Charsets.UTF_8)
        check(bytes == null || bytes.size in 1..32 * 1024 * 1024)
        val hash = bytes?.let { encoded ->
            MessageDigest.getInstance("SHA-256").digest(encoded)
                .joinToString("") { "%02x".format(it) }
        }
        return mapOf("format" to 1, "key" to key, "sha256" to hash,
            "ciphertextBytes" to (bytes?.size ?: 0), "valuesIncluded" to false)
    }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method !in setOf("flush", "localMetadata", "localArticleDraftFingerprint", "localArticleCreationDraftFingerprint")) {
                result.notImplemented()
            } else {
                val arguments = call.arguments as? Map<*, *>
                val key = arguments?.get("key") as? String
                val creation = call.method == "localArticleCreationDraftFingerprint"
                val valid = if (creation || call.method == "localArticleDraftFingerprint") {
                    arguments?.size == 1 && key != null && articleDraftKey(key, creation)
                } else call.arguments == null
                if (!valid) {
                    result.error("invalid_arguments", "Invalid recovery metadata request", null)
                } else writer.execute {
                    val value = try {
                        check(flush())
                        when (call.method) {
                            "flush" -> true
                            "localMetadata" -> metadata()
                            else -> articleFingerprint(key!!, creation)
                        }
                    } catch (_: Exception) { null }
                    main.post {
                        if (value != null) result.success(value)
                        else result.error("recovery_sync_failed", "Recovery metadata unavailable", null)
                    }
                }
            }
        }
    }
    fun dispose() { channel.setMethodCallHandler(null) }
}
