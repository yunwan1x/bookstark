package com.bookstark.bookstark_flutter

import android.system.Os
import android.system.OsConstants
import android.util.JsonReader
import android.util.JsonToken
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.File
import java.io.FileInputStream
import java.io.StringReader
import java.nio.charset.StandardCharsets
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.Locale

/** Strict, bounded storage framing; application-level SQLite checks remain in Dart. */
internal object LocalBackupEnvelope {
    const val MAX_MANIFEST = 8 * 1024 * 1024
    const val MAX_FILES = 32768
    const val MAX_FILE = 512L * 1024 * 1024
    const val MAX_TOTAL = 2L * 1024 * 1024 * 1024
    private val id = Regex("^[a-f0-9]{32}$")
    private val hash = Regex("^[a-f0-9]{64}$")
    private val basename = Regex("^[A-Za-z0-9._-]{1,200}$")
    private val tables = setOf(
        "notes", "tasks", "trash_entries", "books", "documents", "bookmarks",
        "topics", "topic_summaries", "topic_resources", "topic_comments",
        "local_labels", "label_recommendation_settings", "local_images",
        "local_drive_nodes", "html_creation_receipts", "html_preview_resources",
        "sqlite_sequence"
    )
    data class Entry(val path: String, val bytes: Long, val sha256: String)
    data class Manifest(val raw: ByteArray, val sha256: String, val entries: List<Entry>, val total: Long)
    data class Archive(val manifest: Manifest, val sha256: String, val bytes: Long)

    fun digest(bytes: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(bytes))
    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
    fun keys(value: JSONObject, expected: Set<String>) {
        val actual = value.keys().asSequence().toSet()
        check(actual == expected)
    }
    fun number(value: Any?): Long {
        check(value is Int || value is Long)
        return (value as Number).toLong()
    }
    fun text(value: Any?, maximum: Int = 65536): String {
        check(value is String && value.toByteArray(StandardCharsets.UTF_8).size <= maximum)
        return value
    }
    fun identity(value: String): String { check(id.matches(value)); return value }
    fun checksum(value: String): String { check(hash.matches(value)); return value }

    fun json(raw: ByteArray, maximum: Int): JSONObject {
        check(raw.isNotEmpty() && raw.size <= maximum)
        val text = raw.toString(StandardCharsets.UTF_8)
        check(text.toByteArray(StandardCharsets.UTF_8).contentEquals(raw))
        JsonReader(StringReader(text)).use { reader ->
            reader.isLenient = false
            uniqueValue(reader, 0)
            check(reader.peek() == JsonToken.END_DOCUMENT)
        }
        return JSONObject(text)
    }
    private fun uniqueValue(reader: JsonReader, depth: Int) {
        check(depth <= 32)
        when (reader.peek()) {
            JsonToken.BEGIN_OBJECT -> {
                val seen = mutableSetOf<String>()
                reader.beginObject()
                while (reader.hasNext()) {
                    check(seen.add(reader.nextName()))
                    uniqueValue(reader, depth + 1)
                }
                reader.endObject()
            }
            JsonToken.BEGIN_ARRAY -> {
                reader.beginArray()
                while (reader.hasNext()) uniqueValue(reader, depth + 1)
                reader.endArray()
            }
            JsonToken.STRING, JsonToken.NUMBER -> { reader.nextString() }
            JsonToken.BOOLEAN -> { reader.nextBoolean() }
            JsonToken.NULL -> { reader.nextNull() }
            else -> error("Invalid JSON metadata")
        }
    }
    fun manifest(raw: ByteArray): Manifest {
        val value = json(raw, MAX_MANIFEST)
        keys(value, setOf("format", "version", "schema", "id", "createdAt", "sqliteVersion", "tables", "files"))
        check(value.get("format") == "bookstark-local")
        val version = number(value.get("version"))
        val schema = number(value.get("schema"))
        check((version == 1L && schema == 14L) || (version == 2L && schema == 16L) || (version == 3L && schema == 15L))
        val requiredTables = when (schema) {
            15L -> tables + setOf("legacy_import_sources", "legacy_import_records",
                "legacy_import_label_relations", "legacy_friend_links",
                "legacy_import_upload_blobs", "legacy_import_upload_bindings")
            16L -> tables + "assistant_creation_receipts"
            else -> tables
        }
        identity(text(value.get("id"), 32))
        val created = text(value.get("createdAt"), 40)
        check(created.endsWith("Z") && created.all { it.code in 32..126 })
        check(Regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$").matches(text(value.get("sqliteVersion"), 16)))
        val counts = value.get("tables")
        check(counts is JSONObject)
        val names = counts.keys().asSequence().toSet()
        check(names.containsAll(requiredTables) && names.all { it in requiredTables || it == "android_metadata" })
        names.forEach { check(number(counts.get(it)) in 0..100000000L) }
        val files = value.get("files")
        check(files is JSONArray && files.length() in 1..MAX_FILES)
        val folded = mutableSetOf<String>()
        val entries = mutableListOf<Entry>()
        var total = 0L
        for (index in 0 until files.length()) {
            val item = files.get(index)
            check(item is JSONObject)
            keys(item, setOf("path", "bytes", "sha256"))
            val path = text(item.get("path"), 220)
            check(pathAllowed(path) && folded.add(path.lowercase(Locale.ROOT)))
            val bytes = number(item.get("bytes"))
            check(bytes in 0..MAX_FILE && (path != "database/content.db" || bytes > 0))
            val digest = checksum(text(item.get("sha256"), 64))
            total += bytes
            check(total <= MAX_TOTAL)
            entries.add(Entry(path, bytes, digest))
        }
        check(entries.first().path == "database/content.db")
        check(entries.count { it.path == "database/content.db" } == 1)
        return Manifest(raw, digest(raw), entries, total)
    }
    private fun pathAllowed(path: String): Boolean {
        if (path == "database/content.db") return true
        val parts = path.split('/')
        return parts.size == 2 && parts[0] in setOf("attachments", "drive-blobs") &&
            basename.matches(parts[1]) && parts[1] != "." && parts[1] != ".." &&
            !parts[1].endsWith('.')
    }
    fun regular(file: File) {
        check(OsConstants.S_ISREG(Os.lstat(file.absolutePath).st_mode))
    }
    fun directory(file: File) {
        check(OsConstants.S_ISDIR(Os.lstat(file.absolutePath).st_mode))
    }
    fun small(file: File, maximum: Int): ByteArray {
        regular(file)
        check(file.length() in 1..maximum.toLong())
        FileInputStream(file).use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(65536)
            while (true) {
                val size = input.read(buffer)
                if (size < 0) break
                check(output.size().toLong() + size <= maximum)
                output.write(buffer, 0, size)
            }
            return output.toByteArray()
        }
    }
    fun sync(file: File) {
        val descriptor = Os.open(file.absolutePath, OsConstants.O_RDONLY, 0)
        try { Os.fsync(descriptor) } finally { Os.close(descriptor) }
    }
    fun archive(file: File, expectedManifest: String): Archive {
        regular(file)
        check(file.length() <= MAX_TOTAL + MAX_MANIFEST + 12)
        val outer = MessageDigest.getInstance("SHA-256")
        val result: Manifest
        FileInputStream(file).use { source ->
            DigestInputStream(source, outer).use { stream ->
                val input = DataInputStream(stream)
                val magic = ByteArray(8)
                input.readFully(magic)
                check(magic.contentEquals("BSTKBK01".toByteArray(StandardCharsets.US_ASCII)))
                val length = input.readInt()
                check(length in 1..MAX_MANIFEST)
                val metadata = ByteArray(length)
                input.readFully(metadata)
                result = manifest(metadata)
                check(result.sha256 == checksum(expectedManifest))
                val buffer = ByteArray(65536)
                for (entry in result.entries) {
                    var remaining = entry.bytes
                    val hash = MessageDigest.getInstance("SHA-256")
                    while (remaining > 0) {
                        val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                        check(count > 0)
                        hash.update(buffer, 0, count)
                        remaining -= count
                    }
                    check(hex(hash.digest()) == entry.sha256)
                }
                check(input.read() == -1)
            }
        }
        check(file.length() == 12L + result.raw.size + result.total)
        return Archive(result, hex(outer.digest()), file.length())
    }

    /** Verifies every declared byte and rejects undeclared files or links. */
    fun generation(root: File, expectedManifest: String, activated: Boolean = false): Manifest {
        directory(root)
        val metadata = File(root, "_manifest.json")
        val manifest = manifest(small(metadata, MAX_MANIFEST))
        check(manifest.sha256 == checksum(expectedManifest))
        val expected = manifest.entries.map { it.path }.toSet()
        val actual = mutableSetOf<String>()
        for (entry in root.listFiles().orEmpty()) {
            if (entry.name in setOf("_manifest.json", "_ready.json") ||
                (activated && entry.name == "_activated.json")) {
                regular(entry)
                continue
            }
            check(entry.name in setOf("database", "attachments", "drive-blobs"))
            directory(entry)
            for (file in entry.listFiles().orEmpty()) {
                regular(file)
                actual.add(entry.name + "/" + file.name)
                check(actual.size <= MAX_FILES)
            }
        }
        check(actual == expected)
        val buffer = ByteArray(65536)
        for (entry in manifest.entries) {
            val file = File(root, entry.path)
            regular(file)
            check(file.length() == entry.bytes)
            val hash = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { input ->
                var count = 0L
                while (true) {
                    val size = input.read(buffer)
                    if (size < 0) break
                    count += size
                    check(count <= entry.bytes)
                    hash.update(buffer, 0, size)
                }
                check(count == entry.bytes)
            }
            check(hex(hash.digest()) == entry.sha256)
            sync(file)
        }
        root.listFiles().orEmpty().forEach { sync(it) }
        sync(root)
        return manifest
    }
}
