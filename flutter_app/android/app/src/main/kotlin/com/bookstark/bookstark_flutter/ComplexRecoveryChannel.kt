package com.bookstark.bookstark_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Flutter-only private recovery storage. No URL/path/key material capability is
 * exposed to WebView. Each bounded chunk is authenticated before delivery; Dart
 * checks the full digest and typed record before accepting any recovered data. */
class ComplexRecoveryChannel(context: Context, messenger: BinaryMessenger) {
    companion object {
        private const val CHUNK = 262144
        private const val MAX_BYTES = 20 * 1024 * 1024 + 128 * 1024 + 4
        private const val MAGIC = "BSCR0001"
        private const val ALIAS = "bookstark.complex-recovery.v1.aes256"
        private val hex = Regex("^[a-f0-9]{64}$")
        private val worker = Executors.newSingleThreadExecutor { action ->
            Thread(action, "bookstark-complex-recovery").apply { isDaemon = true }
        }
        private val main = Handler(Looper.getMainLooper())
        private val writers = mutableMapOf<String, Writer>()
        private val readers = mutableMapOf<String, Reader>()
    }
    private data class Header(val key: String, val uuid: String, val total: Int, val sha: String)
    private class Writer(val owner: String, val id: String, val header: Header, val atomic: AtomicFile,
        val output: FileOutputStream, val stream: DataOutputStream) {
        val digest = MessageDigest.getInstance("SHA-256")
        var received = 0
        var index = 0
        var finished = false
        var touched = SystemClock.elapsedRealtime()
    }
    private class Reader(val owner: String, val id: String, val header: Header, val stream: DataInputStream) {
        val digest = MessageDigest.getInstance("SHA-256")
        var received = 0
        var index = 0
        var touched = SystemClock.elapsedRealtime()
    }
    private val directory = File(context.applicationContext.noBackupFilesDir, "complex-recovery-v1")
    private val channel = MethodChannel(messenger, "bookstark/complex_recovery")
    private val owner = UUID.randomUUID().toString()
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    check(!closed)
                    ensureDirectory()
                    expire()
                    val value = execute(call)
                    main.post { result.success(value) }
                } catch (_: Exception) {
                    // File names, plaintext and provider error messages stay private.
                    main.post { result.error("complex_recovery_failed", "Recovery storage unavailable", null) }
                }
            }
        }
    }
    private fun ensureDirectory() {
        check(directory.isDirectory || directory.mkdirs())
        Os.chmod(directory.absolutePath, 448) // 0700; fixed application-private directory.
    }
    private fun key(call: MethodCall): String {
        val value = call.argument<String>("key") ?: error("Missing record key")
        check(hex.matches(value))
        return value
    }
    private fun id(call: MethodCall): String {
        val value = call.argument<String>("id") ?: error("Missing transfer")
        check(value.length <= 128)
        return value
    }
    private fun file(key: String) = AtomicFile(File(directory, "$key.bin"))
    private fun free(key: String) {
        check(writers.values.none { it.header.key == key } && readers.values.none { it.header.key == key })
    }
    private fun secret(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(ALIAS)) return store.getKey(ALIAS, null) as SecretKey
        check(create)
        // Restored encrypted files must not be silently overwritten after key loss.
        check(directory.listFiles().orEmpty().none { it.isFile })
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    private fun aad(header: Header, part: String) =
        "$MAGIC|${header.key}|${header.uuid}|${header.total}|$part".toByteArray(Charsets.US_ASCII)
    private fun seal(key: SecretKey, data: ByteArray, aad: ByteArray): Pair<ByteArray, ByteArray> {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(aad)
        check(cipher.iv.size == 12)
        return cipher.iv to cipher.doFinal(data)
    }
    private fun open(key: SecretKey, iv: ByteArray, data: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.updateAAD(aad)
        return cipher.doFinal(data)
    }
    private fun readBytes(input: DataInputStream, length: Int) = ByteArray(length).also { input.readFully(it) }
    private fun writeHeader(output: DataOutputStream, header: Header, key: SecretKey) {
        output.write(MAGIC.toByteArray(Charsets.US_ASCII))
        output.writeInt(header.total)
        output.write(header.uuid.toByteArray(Charsets.US_ASCII))
        val encrypted = seal(key, header.sha.toByteArray(Charsets.US_ASCII), aad(header, "header"))
        output.write(encrypted.first)
        output.write(encrypted.second)
    }
    private fun readHeader(input: DataInputStream, name: String): Header {
        check(readBytes(input, 8).toString(Charsets.US_ASCII) == MAGIC)
        val total = input.readInt()
        check(total in 1..MAX_BYTES)
        val uuid = readBytes(input, 32).toString(Charsets.US_ASCII)
        check(Regex("^[a-f0-9]{32}$").matches(uuid))
        val partial = Header(name, uuid, total, "")
        val iv = readBytes(input, 12)
        val digest = open(secret(false), iv, readBytes(input, 80), aad(partial, "header")).toString(Charsets.US_ASCII)
        check(hex.matches(digest))
        return partial.copy(sha = digest)
    }
    private fun syncDirectory() {
        // Android's public SDK has no O_DIRECTORY. This fixed application-
        // private path is checked as a directory before every operation.
        val fd = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
        try { Os.fsync(fd) } finally { Os.close(fd) }
    }
    private fun abort(writer: Writer) {
        writers.remove(writer.id)
        if (!writer.finished) writer.atomic.failWrite(writer.output)
    }
    private fun end(reader: Reader) {
        readers.remove(reader.id)
        reader.stream.close()
    }
    private fun expire() {
        val now = SystemClock.elapsedRealtime()
        writers.values.filter { now - it.touched > 120000 }.toList().forEach { abort(it) }
        readers.values.filter { now - it.touched > 120000 }.toList().forEach { end(it) }
    }
    private fun digest(value: ByteArray) = value.joinToString("") { "%02x".format(it) }
    private fun execute(call: MethodCall): Any? = when (call.method) {
        "metadata" -> {
            check(call.arguments == null)
            val keys = mutableListOf<String>()
            var unknown = 0
            var overflow = false
            val pattern = Regex("^([a-f0-9]{64})\\.bin$")
            for (entry in directory.listFiles().orEmpty()) {
                val regular = try { OsConstants.S_ISREG(Os.lstat(entry.absolutePath).st_mode) }
                    catch (_: Exception) { false }
                val match = pattern.matchEntire(entry.name)
                if (!regular || match == null) {
                    unknown++
                } else if (keys.size < 4096) {
                    keys.add(match.groupValues[1])
                } else {
                    overflow = true
                }
            }
            mapOf("format" to 1, "keys" to keys.sorted(),
                "unknownFiles" to unknown, "overflow" to overflow,
                "activeTransfers" to writers.size + readers.size,
                "valuesIncluded" to false)
        }
        "beginWrite" -> {
            val name = key(call)
            val total = call.argument<Int>("bytes") ?: error("Missing size")
            val sha = call.argument<String>("sha256") ?: error("Missing digest")
            check(total in 1..MAX_BYTES && hex.matches(sha) && writers.size < 2)
            free(name)
            val encryptionKey = secret(true)
            val atomic = file(name)
            val output = atomic.startWrite()
            try {
                val header = Header(name, UUID.randomUUID().toString().replace("-", ""), total, sha)
                val writer = Writer(owner, UUID.randomUUID().toString(), header, atomic, output, DataOutputStream(output))
                writeHeader(writer.stream, header, encryptionKey)
                writers[writer.id] = writer
                mapOf("id" to writer.id, "bytes" to total, "chunkBytes" to CHUNK)
            } catch (error: Exception) { atomic.failWrite(output); throw error }
        }
        "writeChunk" -> {
            val writer = writers[id(call)]?.takeIf { it.owner == owner } ?: error("Missing writer")
            try {
                val index = call.argument<Int>("index") ?: error("Missing index")
                val bytes = call.argument<ByteArray>("data") ?: error("Missing bytes")
                val expected = minOf(CHUNK, writer.header.total - writer.received)
                check(index == writer.index && bytes.size == expected && expected > 0)
                val encrypted = seal(secret(false), bytes,
                    aad(writer.header, "${writer.header.sha}|$index|$expected"))
                writer.stream.writeInt(expected)
                writer.stream.write(encrypted.first)
                writer.stream.write(encrypted.second)
                writer.digest.update(bytes)
                writer.received += bytes.size
                writer.index++
                writer.touched = SystemClock.elapsedRealtime()
                mapOf("id" to writer.id, "index" to index, "received" to writer.received)
            } catch (error: Exception) { abort(writer); throw error }
        }
        "commitWrite" -> {
            val writer = writers[id(call)]?.takeIf { it.owner == owner } ?: error("Missing writer")
            try {
                check(writer.received == writer.header.total && digest(writer.digest.digest()) == writer.header.sha)
                writer.stream.flush()
                writer.output.fd.sync()
                writer.atomic.finishWrite(writer.output)
                writer.finished = true
                syncDirectory()
                val stored = DataInputStream(writer.atomic.openRead()).use { readHeader(it, writer.header.key) }
                check(stored == writer.header)
                val chunks = (stored.total + CHUNK - 1) / CHUNK
                check(writer.atomic.baseFile.length() == 136L + stored.total + 32L * chunks)
                writers.remove(writer.id)
                mapOf("id" to writer.id, "bytes" to stored.total, "sha256" to stored.sha, "committed" to true)
            } catch (error: Exception) { abort(writer); throw error }
        }
        "abortWrite" -> { writers[id(call)]?.takeIf { it.owner == owner }?.let { abort(it) }; null }
        "beginRead" -> {
            val name = key(call)
            check(readers.size < 2)
            free(name)
            val atomic = file(name)
            if (!atomic.baseFile.exists() && !File(atomic.baseFile.path + ".bak").exists()) null
            else {
                val input = DataInputStream(atomic.openRead())
                try {
                    val header = readHeader(input, name)
                    val reader = Reader(owner, UUID.randomUUID().toString(), header, input)
                    readers[reader.id] = reader
                    mapOf("id" to reader.id, "bytes" to header.total, "sha256" to header.sha,
                        "chunks" to (header.total + CHUNK - 1) / CHUNK)
                } catch (error: Exception) { input.close(); throw error }
            }
        }
        "readChunk" -> {
            val reader = readers[id(call)]?.takeIf { it.owner == owner } ?: error("Missing reader")
            try {
                val index = call.argument<Int>("index") ?: error("Missing index")
                check(index == reader.index)
                val expected = minOf(CHUNK, reader.header.total - reader.received)
                check(expected > 0 && reader.stream.readInt() == expected)
                val iv = readBytes(reader.stream, 12)
                val bytes = open(secret(false), iv, readBytes(reader.stream, expected + 16),
                    aad(reader.header, "${reader.header.sha}|$index|$expected"))
                check(bytes.size == expected)
                reader.digest.update(bytes)
                reader.received += bytes.size
                reader.index++
                reader.touched = SystemClock.elapsedRealtime()
                if (reader.received == reader.header.total) {
                    check(reader.stream.read() == -1 && digest(reader.digest.digest()) == reader.header.sha)
                }
                mapOf("id" to reader.id, "index" to index, "data" to bytes)
            } catch (error: Exception) { end(reader); throw error }
        }
        "endRead" -> { readers[id(call)]?.takeIf { it.owner == owner }?.let { end(it) }; null }
        "remove" -> {
            val name = key(call)
            free(name)
            val atomic = file(name)
            atomic.delete()
            syncDirectory()
            check(listOf("", ".bak", ".new").none { File(atomic.baseFile.path + it).exists() })
            true
        }
        else -> error("Unknown recovery command")
    }
    fun dispose() {
        closed = true
        channel.setMethodCallHandler(null)
        worker.execute {
            writers.values.filter { it.owner == owner }.toList().forEach { try { abort(it) } catch (_: Exception) {} }
            readers.values.filter { it.owner == owner }.toList().forEach { try { end(it) } catch (_: Exception) {} }
        }
    }
}
