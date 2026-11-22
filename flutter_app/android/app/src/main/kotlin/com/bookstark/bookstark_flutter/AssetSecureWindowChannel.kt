package com.bookstark.bookstark_flutter

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.WeakHashMap

/** Leases belong to an engine, surviving activity reattachment without retaining it. */
class AssetSecureWindowChannel(
    private val activity: Activity,
    messenger: BinaryMessenger
) {
    private class LeaseState {
        private val leases = mutableSetOf<String>()
        private var current = WeakReference<Activity>(null)
        private var originallySecure = false

        @Synchronized fun attach(activity: Activity) {
            val old = current.get()
            if (old === activity) {
                if (leases.isNotEmpty()) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                return
            }
            if (old != null && !originallySecure && leases.isEmpty()) {
                old.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            current = WeakReference(activity)
            originallySecure = activity.window.attributes.flags and
                WindowManager.LayoutParams.FLAG_SECURE != 0
            if (leases.isNotEmpty()) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }

        @Synchronized fun detach(activity: Activity) {
            if (current.get() !== activity) return
            if (!originallySecure) activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            current.clear()
            originallySecure = false
            // The engine can still process release while no activity is attached.
        }

        @Synchronized fun handle(call: MethodCall, result: MethodChannel.Result) {
            if (call.method != "acquire" && call.method != "release") {
                result.notImplemented()
                return
            }
            val args = call.arguments as? Map<*, *>
            val id = args?.get("lease") as? String
            if (id == null || id.length != 64 ||
                !id.all { it in '0'..'9' || it in 'a'..'f' }) {
                result.error("invalid_lease", "Invalid secure-window lease", null)
                return
            }
            val activity = current.get()
            if (call.method == "acquire") {
                if (activity == null || activity.isDestroyed || activity.isFinishing ||
                    (leases.size >= 256 && !leases.contains(id))) {
                    result.error("window_unavailable", "Secure window unavailable", null)
                    return
                }
                leases.add(id)
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                leases.remove(id)
                if (leases.isEmpty() && activity != null && !originallySecure) {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
            }
            result.success(true)
        }
    }
    companion object {
        private val engines = WeakHashMap<BinaryMessenger, LeaseState>()
    }
    private val state = synchronized(engines) { engines.getOrPut(messenger) { LeaseState() } }
    private var disposed = false
    init {
        state.attach(activity)
        val heldState = state
        // The handler captures only state, which has a weak activity reference.
        MethodChannel(messenger, "bookstark/asset_secure_window")
            .setMethodCallHandler { call, result -> heldState.handle(call, result) }
    }
    fun dispose() {
        if (disposed) return
        disposed = true
        state.detach(activity)
        // Keep the engine's handler so detached routes can release their leases.
    }
}
