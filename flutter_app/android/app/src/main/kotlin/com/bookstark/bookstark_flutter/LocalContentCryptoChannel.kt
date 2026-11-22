package com.bookstark.bookstark_flutter

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/** One bounded process-wide worker. No database, file, preference or log access. */
class LocalContentCryptoChannel(messenger: BinaryMessenger) {
    companion object {
        private val busy = AtomicBoolean(false)
        private val main = Handler(Looper.getMainLooper())
        private val identity = Regex("[a-f0-9]{32}")
        // Main-thread state spans channel recreation while a retired worker
        // still computes. No request body/password is stored in this barrier.
        private var unfinished = 0
        private val drainers = mutableListOf<MethodChannel.Result>()
        private fun finishDrainers() {
            if (unfinished != 0 || busy.get()) return
            val ready = drainers.toList()
            drainers.clear()
            ready.forEach { result ->
                try { result.success(mapOf("format" to 1, "drained" to true)) }
                catch (_: Exception) { /* A disposed messenger cannot be acknowledged. */ }
            }
        }
    }
    private val channel = MethodChannel(messenger, "bookstark/local_content_crypto")
    private class Request(val id: String, val result: MethodChannel.Result) {
        var retired = false
        var thread: Thread? = null
    }
    private var active: Request? = null
    private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "drain") {
                if (closed || call.arguments != null || drainers.size >= 16) {
                    result.error("UNAVAILABLE", "Crypto drain unavailable", null)
                } else {
                    drainers.add(result)
                    finishDrainers()
                }
                return@setMethodCallHandler
            }
            val keys = when (call.method) {
                "cancel" -> setOf("id")
                "unlock", "encryptExisting" -> setOf("id", "password", "hash", "body")
                "protectNew", "unlockEnvelope", "encryptEnvelope" -> setOf("id", "password", "body")
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            val arguments = call.arguments as? Map<*, *>
            if (closed || arguments == null || arguments.keys != keys ||
                !identity.matches(arguments["id"] as? String ?: "")) {
                (arguments?.get("body") as? ByteArray)?.fill(0)
                result.error("UNSUPPORTED", "Crypto request unavailable", null)
                return@setMethodCallHandler
            }
            val id = arguments["id"] as String
            if (call.method == "cancel") {
                if (active?.id == id) retire()
                result.success(mapOf("format" to 1, "id" to id, "cancelled" to true))
                return@setMethodCallHandler
            }
            val password = arguments["password"] as? String
            val bodyBytes = arguments["body"] as? ByteArray
            val hash = arguments["hash"] as? String
            if (password == null || bodyBytes == null || password.length > 4096 ||
                bodyBytes.size > LegacyContentCrypto.MAX_WIRE_BYTES ||
                (call.method in setOf("unlock", "encryptExisting") && hash == null) ||
                (hash != null && hash.length != 60)) {
                bodyBytes?.fill(0)
                result.error("UNSUPPORTED", "Crypto request unavailable", null)
                return@setMethodCallHandler
            }
            if (active != null || !busy.compareAndSet(false, true)) {
                bodyBytes.fill(0)
                result.error("BUSY", "Crypto worker is busy", null)
                return@setMethodCallHandler
            }
            val request = Request(id, result)
            active = request
            unfinished++
            try {
                request.thread = Thread({
                    var value: Map<String, Any>? = null
                    var failure = "UNAVAILABLE"
                    try {
                        val body = LegacyContentCrypto.decodeWireBody(bodyBytes)
                        value = when (call.method) {
                            "unlock" -> mapOf("format" to 1, "id" to id, "body" to
                                LegacyContentCrypto.encodeWireBody(LegacyContentCrypto.unlock(password, hash!!, body)))
                            "unlockEnvelope" -> mapOf("format" to 1, "id" to id, "body" to
                                LegacyContentCrypto.encodeWireBody(LegacyContentCrypto.unlockEnvelope(password, body)))
                            "encryptEnvelope" -> mapOf("format" to 1, "id" to id, "body" to
                                LegacyContentCrypto.encodeWireBody(LegacyContentCrypto.encryptEnvelope(password, body)))
                            "encryptExisting" -> mapOf("format" to 1, "id" to id, "body" to
                                LegacyContentCrypto.encodeWireBody(LegacyContentCrypto.encryptExisting(password, hash!!, body)))
                            else -> {
                                val sealedBody = LegacyContentCrypto.protectNew(password, body)
                                mapOf("format" to 1, "id" to id, "body" to
                                    LegacyContentCrypto.encodeWireBody(sealedBody.encryptedBody), "hash" to sealedBody.passwordHash)
                            }
                        }
                    } catch (error: LegacyContentCrypto.Failure) {
                        failure = error.reason.name
                    } catch (_: Exception) {
                        // Never return provider messages or an argument's value.
                    } finally {
                        bodyBytes.fill(0)
                        busy.set(false)
                        val outcome = value
                        val reason = failure
                        main.post {
                            try {
                                if (!request.retired && !closed) {
                                    if (outcome != null) request.result.success(outcome)
                                    else request.result.error(reason, "Crypto operation failed", null)
                                }
                            } finally {
                                (outcome?.get("body") as? ByteArray)?.fill(0)
                                if (active === request) active = null
                                unfinished--
                                finishDrainers()
                            }
                        }
                    }
                }, "bookstark-local-crypto").apply { isDaemon = true; start() }
            } catch (_: Exception) {
                bodyBytes.fill(0)
                busy.set(false)
                active = null
                unfinished--
                finishDrainers()
                result.error("UNAVAILABLE", "Crypto worker unavailable", null)
            }
        }
    }

    /** Keep the process lease until actual worker exit, including slow bcrypt. */
    fun retire() {
        val request = active ?: return
        if (request.retired) return
        request.retired = true
        request.result.error("CANCELLED", "Crypto operation cancelled", null)
        request.thread?.interrupt()
    }

    fun dispose() {
        if (closed) return
        retire()
        closed = true
        channel.setMethodCallHandler(null)
    }
}
