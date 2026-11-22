package com.bookstark.bookstark_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

/** Fixed private roots only. No user path, account value or SQL crosses this channel. */
class LocalDataControlChannel(context: Context, messenger: BinaryMessenger) {
    private val files = context.applicationContext.filesDir.canonicalFile
    private val legacyDatabase = context.applicationContext.getDatabasePath("bookstark-flutter.db").canonicalFile
    private val root = File(files, "local-data-v1")
    private val channel = MethodChannel(messenger, "bookstark/local_data_control")
    @Volatile private var closed = false
    companion object {
        private val worker = Executors.newSingleThreadExecutor { work ->
            Thread(work, "bookstark-local-data-control").apply { isDaemon = true }
        }
        private val main = Handler(Looper.getMainLooper())
        private const val LIMIT = 16384
    }
    private data class Pointer(val raw: String, val generation: String, val epoch: Long,
        val operation: String, val sourceHash: String)
    private data class Retention(val raw: String, val id: String, val pointerHash: String,
        val generation: String, val manifestHash: String)
    private data class Intent(val raw: String, val operation: String, val source: Pointer?,
        val sourceHash: String, val retainedId: String, val retainedHash: String, val target: Pointer)
    private data class State(val pointer: Pointer?, val intent: Intent?,
        val current: Retention?, val source: Retention?)

    init {
        channel.setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    check(!closed)
                    ensureRoot()
                    val value = execute(call)
                    main.post { result.success(value) }
                } catch (_: Exception) {
                    main.post { result.error("local_data_control_failed",
                        "Local data control requires read-only review; files are retained", null) }
                }
            }
        }
    }
    private fun present(file: File): Boolean = try {
        Os.lstat(file.absolutePath); true
    } catch (error: ErrnoException) {
        if (error.errno == OsConstants.ENOENT) false else throw error
    }
    private fun dir(file: File, create: Boolean = false): File {
        if (!present(file)) {
            check(create && file.mkdir())
            Os.chmod(file.absolutePath, 448)
            LocalBackupEnvelope.sync(file.parentFile!!)
        }
        LocalBackupEnvelope.directory(file)
        return file
    }
    private fun ensureRoot() {
        dir(files)
        dir(root, true)
        dir(File(root, "generations"), true)
        dir(File(root, "retained"), true)
        dir(File(root, "locks"), true)
    }
    private fun generation(id: String): File =
        dir(File(File(root, "generations"), LocalBackupEnvelope.identity(id)))
    private fun retained(id: String): File =
        dir(File(File(root, "retained"), LocalBackupEnvelope.identity(id)))
    private fun lockFile(hash: String): File =
        File(File(root, "locks"), LocalBackupEnvelope.checksum(hash) + ".json")
    private fun pointerFile() = File(root, "pointer.json")
    private fun intentFile() = File(root, "intent.json")
    private fun utf8(raw: String) = raw.toByteArray(StandardCharsets.UTF_8)
    private fun hash(raw: String?) = LocalBackupEnvelope.digest(if (raw == null) ByteArray(0) else utf8(raw))
    private fun sides(file: File) = listOf(file, File(file.path + ".bak"), File(file.path + ".new"))
    private fun read(file: File): String? {
        sides(file).filter { present(it) }.forEach { LocalBackupEnvelope.regular(it) }
        if (!present(file) && !present(File(file.path + ".bak"))) return null
        // Framework recovery may restore its previous atomic version. The
        // independent retained lock/intent keeps this a read-only observation.
        AtomicFile(file).openRead().use { input ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            while (true) {
                val size = input.read(buffer)
                if (size < 0) break
                check(output.size() + size <= LIMIT)
                output.write(buffer, 0, size)
            }
            LocalBackupEnvelope.sync(file.parentFile!!)
            return output.toByteArray().toString(StandardCharsets.UTF_8)
        }
    }
    private fun write(file: File, raw: String) {
        val bytes = utf8(raw)
        check(bytes.size in 1..LIMIT)
        sides(file).filter { present(it) }.forEach { LocalBackupEnvelope.regular(it) }
        val atomic = AtomicFile(file)
        var output: FileOutputStream? = null
        var finished = false
        try {
            output = atomic.startWrite()
            output.write(bytes)
            output.fd.sync()
            atomic.finishWrite(output)
            finished = true
            Os.chmod(file.absolutePath, 384)
            LocalBackupEnvelope.sync(file)
            LocalBackupEnvelope.sync(file.parentFile!!)
        } catch (error: Exception) {
            if (!finished) atomic.failWrite(output)
            throw error
        }
    }
    private fun remove(file: File) {
        sides(file).filter { present(it) }.forEach { LocalBackupEnvelope.regular(it) }
        AtomicFile(file).delete()
        check(sides(file).none { present(it) })
        LocalBackupEnvelope.sync(file.parentFile!!)
    }
    private fun objectValue(raw: String, names: Set<String>): JSONObject {
        val value = LocalBackupEnvelope.json(utf8(raw), LIMIT)
        LocalBackupEnvelope.keys(value, names)
        check(LocalBackupEnvelope.number(value.get("format")) == 1L)
        return value
    }
    private fun pointer(raw: String): Pointer {
        val value = objectValue(raw, setOf("format", "generation", "epoch", "activationId", "sourceSHA256"))
        val epoch = LocalBackupEnvelope.number(value.get("epoch"))
        check(epoch in 1..0x1ffffffffffffeL)
        return Pointer(raw, LocalBackupEnvelope.identity(LocalBackupEnvelope.text(value.get("generation"), 32)),
            epoch, LocalBackupEnvelope.identity(LocalBackupEnvelope.text(value.get("activationId"), 32)),
            LocalBackupEnvelope.checksum(LocalBackupEnvelope.text(value.get("sourceSHA256"), 64)))
    }
    private fun retention(raw: String): Retention {
        val value = objectValue(raw, setOf("format", "id", "sourcePointerSHA256", "sourceGeneration", "manifestSHA256"))
        val generation = LocalBackupEnvelope.text(value.get("sourceGeneration"), 32)
        check(generation == "legacy" || Regex("^[a-f0-9]{32}$").matches(generation))
        return Retention(raw,
            LocalBackupEnvelope.identity(LocalBackupEnvelope.text(value.get("id"), 32)),
            LocalBackupEnvelope.checksum(LocalBackupEnvelope.text(value.get("sourcePointerSHA256"), 64)),
            generation, LocalBackupEnvelope.checksum(LocalBackupEnvelope.text(value.get("manifestSHA256"), 64)))
    }
    private fun intent(raw: String): Intent {
        val value = objectValue(raw, setOf("format", "operationId", "sourcePointer", "sourcePointerSHA256",
            "retainedId", "retainedManifestSHA256", "targetPointer"))
        val source = if (value.isNull("sourcePointer")) null else
            pointer(LocalBackupEnvelope.text(value.get("sourcePointer"), 4096))
        val target = pointer(LocalBackupEnvelope.text(value.get("targetPointer"), 4096))
        val operation = LocalBackupEnvelope.identity(LocalBackupEnvelope.text(value.get("operationId"), 32))
        val sourceHash = LocalBackupEnvelope.checksum(LocalBackupEnvelope.text(value.get("sourcePointerSHA256"), 64))
        check(sourceHash == hash(source?.raw) && target.operation == operation &&
            target.epoch == (source?.epoch ?: 0L) + 1L && target.generation != source?.generation)
        return Intent(raw, operation, source, sourceHash,
            LocalBackupEnvelope.identity(LocalBackupEnvelope.text(value.get("retainedId"), 32)),
            LocalBackupEnvelope.checksum(LocalBackupEnvelope.text(value.get("retainedManifestSHA256"), 64)),
            target)
    }
    private fun ready(pointer: Pointer): Pair<File, String> {
        val directory = generation(pointer.generation)
        val raw = LocalBackupEnvelope.small(File(directory, "_ready.json"), 4096)
        val value = LocalBackupEnvelope.json(raw, 4096)
        LocalBackupEnvelope.keys(value, setOf("format", "generation", "sourceSHA256", "manifestSHA256"))
        check(LocalBackupEnvelope.number(value.get("format")) == 1L &&
            value.get("generation") == pointer.generation && value.get("sourceSHA256") == pointer.sourceHash)
        return directory to LocalBackupEnvelope.checksum(LocalBackupEnvelope.text(value.get("manifestSHA256"), 64))
    }
    private fun activated(pointer: Pointer) {
        val (directory, _) = ready(pointer)
        dir(File(directory, "database"))
        val database = File(File(directory, "database"), "content.db")
        LocalBackupEnvelope.regular(database)
        check(database.length() > 0)
        for (name in listOf("attachments", "drive-blobs")) {
            val child = File(directory, name)
            if (present(child)) dir(child)
        }
        val raw = LocalBackupEnvelope.small(File(directory, "_activated.json"), 4096)
        val value = LocalBackupEnvelope.json(raw, 4096)
        LocalBackupEnvelope.keys(value, setOf("format", "pointerSHA256", "operationId"))
        check(LocalBackupEnvelope.number(value.get("format")) == 1L &&
            value.get("pointerSHA256") == hash(pointer.raw) && value.get("operationId") == pointer.operation)
    }
    private fun matching(lock: Retention, pointer: Pointer?) {
        check(lock.pointerHash == hash(pointer?.raw) && lock.generation == (pointer?.generation ?: "legacy"))
        val readyRaw = LocalBackupEnvelope.small(File(retained(lock.id), "_ready.json"), 4096)
            .toString(StandardCharsets.UTF_8)
        check(readyRaw == lock.raw)
    }
    private fun verifyRetained(lock: Retention) {
        val directory = retained(lock.id)
        val readyFile = File(directory, "_ready.json")
        check(LocalBackupEnvelope.small(readyFile, 4096).toString(StandardCharsets.UTF_8) == lock.raw)
        val archive = File(directory, "content.bsbackup")
        LocalBackupEnvelope.archive(archive, lock.manifestHash)
        LocalBackupEnvelope.sync(archive)
        LocalBackupEnvelope.sync(readyFile)
        LocalBackupEnvelope.sync(directory)
    }
    private fun state(): State {
        val current = read(pointerFile())?.let { pointer(it) }
        current?.let { activated(it) }
        val pending = read(intentFile())?.let { intent(it) }
        val currentLock = read(lockFile(hash(current?.raw)))?.let { retention(it) }
        currentLock?.let { matching(it, current) }
        val sourceLock = pending?.let { read(lockFile(it.sourceHash))?.let { raw -> retention(raw) } }
        if (pending != null && sourceLock != null) {
            matching(sourceLock, pending.source)
            check(sourceLock.id == pending.retainedId && sourceLock.manifestHash == pending.retainedHash)
        }
        return State(current, pending, currentLock, sourceLock)
    }
    private fun snapshot(state: State): Map<String, Any?> = mapOf(
        "format" to 1, "pointerRaw" to state.pointer?.raw, "intentRaw" to state.intent?.raw,
        "currentRetentionRaw" to state.current?.raw, "sourceRetentionRaw" to state.source?.raw,
        "metadataOnly" to true
    )
    private fun arguments(call: MethodCall, names: Set<String>): Map<*, *> {
        val values = call.arguments as? Map<*, *> ?: error("Missing control arguments")
        check(values.keys.toSet() == names)
        return values
    }
    private fun pending(call: MethodCall): Intent {
        val args = arguments(call, setOf("operationId", "intentSHA256"))
        val raw = read(intentFile()) ?: error("No pending intent")
        val value = intent(raw)
        check(value.operation == args["operationId"] &&
            hash(raw) == LocalBackupEnvelope.checksum(LocalBackupEnvelope.text(args["intentSHA256"], 64)))
        return value
    }
    private fun receipt(action: String, id: String): Map<String, Any?> =
        mapOf("format" to 1, "action" to action, "id" to id,
            "durable" to true, "state" to snapshot(state()))

    private fun deleteOwnedTree(file: File, depth: Int = 0) {
        check(depth <= 6)
        val stat = Os.lstat(file.absolutePath)
        if (OsConstants.S_ISDIR(stat.st_mode)) {
            file.listFiles().orEmpty().forEach { deleteOwnedTree(it, depth + 1) }
        }
        check(file.delete())
    }

    private fun execute(call: MethodCall): Any = when (call.method) {
        "readState" -> { check(call.arguments == null); snapshot(state()) }
        "reenterReadySource" -> {
            val args = arguments(call, setOf("sourcePointerSHA256"))
            val before = state()
            check(before.intent == null && before.current == null && before.source == null)
            val expected = LocalBackupEnvelope.checksum(LocalBackupEnvelope.text(args["sourcePointerSHA256"], 64))
            check(hash(before.pointer?.raw) == expected)
            val database = before.pointer?.let { File(generation(it.generation), "database/content.db") }
                ?: legacyDatabase
            LocalBackupEnvelope.regular(database)
            check(database.length() > 0)
            LocalBackupEnvelope.sync(root)
            receipt("reentered-ready", expected)
        }
        "listRetained" -> {
            check(call.arguments == null)
            val rows = mutableListOf<String>()
            var unknown = 0
            var overflow = false
            val directory = dir(File(root, "retained"))
            val entries = directory.listFiles() ?: error("Cannot list retained copies")
            for ((index, entry) in entries.withIndex()) {
                if (index >= 256) { overflow = true; break }
                try {
                    LocalBackupEnvelope.identity(entry.name)
                    dir(entry)
                    val value = retention(LocalBackupEnvelope.small(File(entry, "_ready.json"), 4096)
                        .toString(StandardCharsets.UTF_8))
                    check(value.id == entry.name)
                    LocalBackupEnvelope.regular(File(entry, "content.bsbackup"))
                    rows.add(value.raw)
                } catch (_: Exception) {
                    unknown++
                }
            }
            mapOf("format" to 1, "retentions" to rows, "unknown" to unknown,
                "overflow" to overflow, "metadataOnly" to true)
        }
        "space" -> {
            check(call.arguments == null)
            mapOf("format" to 1, "availableBytes" to StatFs(root.absolutePath).availableBytes)
        }
        "prepareRestore" -> {
            val args = arguments(call, setOf("intentRaw"))
            val pending = intent(LocalBackupEnvelope.text(args["intentRaw"], LIMIT))
            val before = state()
            check(before.intent == null && before.pointer?.raw == pending.source?.raw)
            val retainedRaw = LocalBackupEnvelope.small(File(retained(pending.retainedId), "_ready.json"), 4096)
                .toString(StandardCharsets.UTF_8)
            val lock = retention(retainedRaw)
            matching(lock, pending.source)
            check(lock.id == pending.retainedId && lock.manifestHash == pending.retainedHash)
            if (before.current != null) check(before.current.raw == lock.raw)
            verifyRetained(lock)
            val (directory, manifestHash) = ready(pending.target)
            check(sides(File(directory, "_activated.json")).none { present(it) })
            LocalBackupEnvelope.generation(directory, manifestHash)
            check(read(pointerFile()) == pending.source?.raw && read(intentFile()) == null)
            if (before.current == null) write(lockFile(pending.sourceHash), lock.raw)
            write(intentFile(), pending.raw)
            receipt("prepared", pending.operation)
        }
        "commitRestore" -> {
            val pending = pending(call)
            val before = state()
            check(before.pointer?.raw == pending.source?.raw && before.current != null &&
                before.source != null && before.current.id == pending.retainedId)
            verifyRetained(before.current)
            val (directory, manifestHash) = ready(pending.target)
            check(sides(File(directory, "_activated.json")).none { present(it) })
            LocalBackupEnvelope.generation(directory, manifestHash)
            check(read(pointerFile()) == pending.source?.raw)
            write(File(directory, "_activated.json"), JSONObject().put("format", 1)
                .put("pointerSHA256", hash(pending.target.raw)).put("operationId", pending.operation).toString())
            write(pointerFile(), pending.target.raw)
            receipt("switched", pending.operation)
        }
        "reviewApplied" -> {
            val pending = pending(call)
            val before = state()
            check(before.pointer?.raw == pending.target.raw && before.current == null && before.source != null)
            verifyRetained(before.source)
            val (directory, manifestHash) = ready(pending.target)
            LocalBackupEnvelope.generation(directory, manifestHash, true)
            val manifestRaw = LocalBackupEnvelope.small(File(directory, "_manifest.json"),
                LocalBackupEnvelope.MAX_MANIFEST)
            check(LocalBackupEnvelope.digest(manifestRaw) == manifestHash)
            mapOf("format" to 1, "operationId" to pending.operation,
                "pointerSHA256" to hash(pending.target.raw), "intentSHA256" to hash(pending.raw),
                "manifestRaw" to manifestRaw.toString(StandardCharsets.UTF_8),
                "metadataOnly" to true)
        }
        "acknowledgeApplied" -> {
            val pending = pending(call)
            val before = state()
            check(before.pointer?.raw == pending.target.raw && before.current == null && before.source != null)
            verifyRetained(before.source)
            val (directory, manifestHash) = ready(pending.target)
            LocalBackupEnvelope.generation(directory, manifestHash, true)
            remove(intentFile())
            receipt("acknowledged", pending.operation)
        }
        "finishUnapplied" -> {
            val pending = pending(call)
            val before = state()
            check(before.pointer?.raw == pending.source?.raw && before.current != null &&
                before.source != null && before.current.id == pending.retainedId)
            verifyRetained(before.current)
            remove(intentFile())
            receipt("finished-unapplied", pending.operation)
        }
        "discardCandidate" -> {
            val args = arguments(call, setOf("generation"))
            val id = LocalBackupEnvelope.identity(LocalBackupEnvelope.text(args["generation"], 32))
            val before = state()
            check(before.pointer?.generation != id && before.intent?.target?.generation != id)
            val directory = generation(id)
            check(sides(File(directory, "_activated.json")).none { present(it) })
            deleteOwnedTree(directory)
            LocalBackupEnvelope.sync(directory.parentFile!!)
            receipt("discarded", id)
        }
        "reenterUnchangedSource" -> {
            val args = arguments(call, setOf("sourcePointerSHA256", "retainedId", "retainedManifestSHA256"))
            val before = state()
            val lock = before.current ?: error("No retained source lock")
            check(before.intent == null && lock.pointerHash == args["sourcePointerSHA256"] &&
                lock.id == args["retainedId"] && lock.manifestHash == args["retainedManifestSHA256"])
            verifyRetained(lock)
            if (before.pointer == null) {
                LocalBackupEnvelope.regular(legacyDatabase)
                check(legacyDatabase.length() > 0)
            }
            check(read(pointerFile()) == before.pointer?.raw && read(intentFile()) == null)
            remove(lockFile(lock.pointerHash))
            receipt("reentered", lock.id)
        }
        else -> error("Unsupported local data operation")
    }
    fun dispose() {
        closed = true
        channel.setMethodCallHandler(null)
    }
}
