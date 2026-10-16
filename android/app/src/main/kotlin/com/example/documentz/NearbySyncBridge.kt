package com.example.documentz

import android.app.Activity
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.UUID

/** Nearby carries the existing authenticated/encrypted DocumentZ protocol.
 * Accepting a transport does NOT trust a device or expose annotations. */
@Suppress("MissingPermission")
class NearbySyncBridge(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "documentz/nearby")
    private val clientHolder = lazy { Nearby.getConnectionsClient(activity) }
    private val client by clientHolder
    private val handler = Handler(Looper.getMainLooper())
    private val service = "com.example.quiet_reader.annotations.v1"
    private val strategy = Strategy.P2P_POINT_TO_POINT
    private val permissionRequest = 8440
    private var ownId = ""
    private var running = false
    private var generation = 0
    private var startResult: MethodChannel.Result? = null
    private var connectResult: MethodChannel.Result? = null
    private var target: String? = null
    private val found = mutableMapOf<String, String>()
    private var link: Link? = null
    private data class Link(val token: String, val endpoint: String, val peer: String,
        val incoming: Boolean, val binding: String, var connected: Boolean = false,
        var authorized: Boolean = false, var sent: Long = 0, var received: Long = 0,
        var receivedBytes: Long = 0)
    private data class Sending(val token: String, val result: MethodChannel.Result)
    private val sending = mutableMapOf<Long, Sending>()

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> start(call.argument<String>("id") ?: "", result)
                    "stop" -> { stop(); result.success(null) }
                    "connect" -> connect(call.argument<String>("peer") ?: "", result)
                    "send" -> send(call.argument<String>("link") ?: "", call.argument<ByteArray>("bytes"), result)
                    "authorize" -> {
                        val current = requireLink(call.argument<String>("link") ?: "")
                        current.authorized = true
                        result.success(null)
                    }
                    "disconnect" -> {
                        if (link?.token == call.argument<String>("link")) disconnect("Connection closed.")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: SecurityException) {
                result.error("permission", "Allow Nearby devices access to connect the phones.", null)
            } catch (_: Exception) {
                result.error("nearby", "Nearby connection is unavailable. Keep both apps open and retry.", null)
            }
        }
    }

    private fun start(id: String, result: MethodChannel.Result) {
        require(Regex("^[a-f0-9]{32}$").matches(id))
        if (running && ownId == id) { result.success(null); return }
        if (startResult != null) { result.error("busy", "A Nearby permission request is already open.", null); return }
        ownId = id
        startResult = result
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) permissions.addAll(listOf(
            "android.permission.BLUETOOTH_SCAN", "android.permission.BLUETOOTH_CONNECT", "android.permission.BLUETOOTH_ADVERTISE"))
        if (Build.VERSION.SDK_INT >= 33) permissions.add("android.permission.NEARBY_WIFI_DEVICES")
        else permissions.add("android.permission.ACCESS_FINE_LOCATION")
        if (Build.VERSION.SDK_INT >= 37 && activity.applicationInfo.targetSdkVersion >= 37)
            permissions.add("android.permission.ACCESS_LOCAL_NETWORK")
        val missing = permissions.filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) activity.requestPermissions(missing.toTypedArray(), permissionRequest)
        else launch()
    }

    fun permissionResult(request: Int, results: IntArray): Boolean {
        if (request != permissionRequest) return false
        if (startResult == null) return true
        if (results.isEmpty() || results.any { it != PackageManager.PERMISSION_GRANTED })
            failStart("Allow Nearby devices access in Android Settings to use direct sync.")
        else launch()
        return true
    }

    private fun launch() {
        try {
            val bluetooth = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (bluetooth?.isEnabled != true || wifi?.isWifiEnabled != true) {
                failStart("Switch on Bluetooth and Wi-Fi, then enable sync again. You do not need to join a Wi-Fi network or turn on a hotspot.")
                return
            }
            val epoch = ++generation
            client.startAdvertising("dz1:$ownId", service, lifecycle,
                AdvertisingOptions.Builder().setStrategy(strategy).build())
                .addOnSuccessListener {
                    if (epoch != generation || startResult == null) return@addOnSuccessListener
                    running = true
                    startResult?.success(null); startResult = null
                }
                .addOnFailureListener { if (epoch == generation) failStart("Could not start direct sync. Check Google Play services and Nearby devices permission, then retry.") }
        } catch (_: Exception) { failStart("Could not start direct sync. Check Nearby devices permission, Wi-Fi and Bluetooth.") }
    }

    private fun failStart(message: String) {
        generation++
        running = false
        if (clientHolder.isInitialized()) {
            try { client.stopAdvertising(); client.stopDiscovery() } catch (_: Exception) { }
        }
        startResult?.error("nearby", message, null); startResult = null
    }

    private val discovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpoint: String, info: DiscoveredEndpointInfo) {
            if (!running || info.serviceId != service || !info.endpointName.startsWith("dz1:")) return
            val id = info.endpointName.removePrefix("dz1:")
            if (!Regex("^[a-f0-9]{32}$").matches(id) || id == ownId || found.size >= 64) return
            found[id] = endpoint
            if (target == id && link == null) request(id, endpoint)
        }
        override fun onEndpointLost(endpoint: String) { found.entries.removeAll { it.value == endpoint } }
    }

    private fun connect(peer: String, result: MethodChannel.Result) {
        require(Regex("^[a-f0-9]{32}$").matches(peer) && peer != ownId)
        if (!running) { result.error("nearby", "Enable direct sync on both devices first.", null); return }
        if (connectResult != null || link != null) { result.error("busy", "Finish the current connection first.", null); return }
        connectResult = result; target = peer
        val epoch = generation
        found.clear()
        // Scan only during an explicit connection attempt, not while reading.
        client.startDiscovery(service, discovery, DiscoveryOptions.Builder().setStrategy(strategy).build())
            .addOnFailureListener {
                if (epoch == generation && connectResult === result)
                    disconnect("Could not find nearby devices. Check Nearby devices permission and that Wi-Fi and Bluetooth are on.")
            }
        handler.postDelayed({
            if (generation == epoch && connectResult === result) {
                connectResult = null; target = null
                result.error("nearby", "The other phone was not found nearby. Keep both sync screens open with Wi-Fi and Bluetooth on, and scan a fresh QR.", null)
                disconnect("Connection timed out.")
            }
        }, 45000)
    }

    private fun request(peer: String, endpoint: String) {
        if (target != peer || connectResult == null || link != null) return
        // Reserve the slot until the lifecycle supplies its authenticated binding.
        val reservation = Link(UUID.randomUUID().toString(), endpoint, peer, false, "")
        link = reservation
        client.stopDiscovery()
        client.requestConnection("dz1:$ownId", endpoint, lifecycle).addOnFailureListener {
            if (link === reservation) disconnect("Could not establish the nearby connection. Retry from one phone only.")
        }
    }

    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpoint: String, info: ConnectionInfo) {
            val peer = info.endpointName.removePrefix("dz1:")
            val current = link
            if (!running || !info.endpointName.startsWith("dz1:") ||
                !Regex("^[a-f0-9]{32}$").matches(peer) || peer == ownId ||
                (target != null && target != peer) || (current != null && current.endpoint != endpoint)) {
                client.rejectConnection(endpoint); return
            }
            val binding = info.authenticationDigits
            if (binding.isBlank() || binding.length > 256) {
                client.rejectConnection(endpoint)
                disconnect("The nearby connection could not be authenticated. Retry with a fresh QR.")
                return
            }
            val pending = Link(UUID.randomUUID().toString(), endpoint, peer, info.isIncomingConnection, binding)
            link = pending
            // Only the transport is accepted here. QR-key proof, transcript binding
            // and explicit DocumentZ verification approval precede annotation access.
            client.acceptConnection(endpoint, payloads).addOnFailureListener {
                if (link === pending) disconnect("Nearby connection was not accepted.")
            }
            handler.postDelayed({ if (link === pending && !pending.authorized) disconnect("Authentication timed out.") }, 120000)
        }
        override fun onConnectionResult(endpoint: String, resolution: ConnectionResolution) {
            val current = link ?: return
            if (current.endpoint != endpoint) return
            if (!resolution.status.isSuccess) { disconnect("The nearby connection was declined or interrupted."); return }
            current.connected = true
            client.stopDiscovery()
            val event = mapOf("link" to current.token, "peer" to current.peer,
                "incoming" to current.incoming, "binding" to current.binding)
            channel.invokeMethod("connected", event)
            if (!current.incoming) { connectResult?.success(event); connectResult = null; target = null }
        }
        override fun onDisconnected(endpoint: String) {
            if (link?.endpoint == endpoint) disconnect("The other phone disconnected.")
        }
    }

    private fun requireLink(token: String): Link {
        val current = link
        require(current != null && current.connected && current.token == token)
        return current
    }

    private fun send(token: String, bytes: ByteArray?, result: MethodChannel.Result) {
        val current = requireLink(token)
        require(bytes != null && bytes.size in 1..32000 && sending.isEmpty())
        val frame = ByteBuffer.allocate(bytes.size + 8).putLong(current.sent++).put(bytes).array()
        val payload = Payload.fromBytes(frame)
        sending[payload.id] = Sending(token, result)
        client.sendPayload(current.endpoint, payload).addOnFailureListener {
            sending.remove(payload.id)?.result?.error("nearby", "The transfer was interrupted. Retry sync safely.", null)
        }
        handler.postDelayed({
            val pending = sending.remove(payload.id)
            if (pending != null) {
                client.cancelPayload(payload.id)
                pending.result.error("nearby", "The other phone did not receive the data in time. Retry sync safely.", null)
                if (link?.token == token) disconnect("Transfer timed out.")
            }
        }, 30000)
    }

    private val payloads = object : PayloadCallback() {
        override fun onPayloadReceived(endpoint: String, payload: Payload) {
            val current = link ?: return
            if (current.endpoint != endpoint || !current.connected) return
            val bytes = if (payload.type == Payload.Type.BYTES) payload.asBytes() else null
            if (bytes == null || bytes.size !in 9..32008) {
                client.cancelPayload(payload.id)
                disconnect("Invalid nearby data.")
                return
            }
            val frame = ByteBuffer.wrap(bytes)
            if (frame.long != current.received++) { disconnect("Nearby data arrived out of sequence."); return }
            current.receivedBytes += bytes.size - 8
            val limit = if (current.authorized) 32L * 1024 * 1024 else 8192L
            if (current.receivedBytes > limit) { disconnect("Nearby data exceeds the session limit."); return }
            channel.invokeMethod("bytes", mapOf("link" to current.token, "bytes" to bytes.copyOfRange(8, bytes.size)))
        }
        override fun onPayloadTransferUpdate(endpoint: String, update: PayloadTransferUpdate) {
            val pending = sending[update.payloadId] ?: return
            when (update.status) {
                PayloadTransferUpdate.Status.SUCCESS -> { sending.remove(update.payloadId); pending.result.success(null) }
                PayloadTransferUpdate.Status.FAILURE, PayloadTransferUpdate.Status.CANCELED -> {
                    sending.remove(update.payloadId)
                    pending.result.error("nearby", "The transfer was interrupted. Retry sync safely.", null)
                }
            }
        }
    }

    private fun disconnect(message: String) {
        val previous = link
        link = null
        connectResult?.error("nearby", message, null); connectResult = null; target = null
        val pending = sending.values.toList(); sending.clear()
        pending.forEach { it.result.error("nearby", message, null) }
        if (previous != null) {
            client.disconnectFromEndpoint(previous.endpoint)
            channel.invokeMethod("disconnected", mapOf("link" to previous.token))
        }
        client.stopDiscovery()
    }

    private fun stop() {
        generation++; running = false
        startResult?.error("cancelled", "Sync was stopped.", null); startResult = null
        if (!clientHolder.isInitialized()) return
        disconnect("Sync was stopped.")
        client.stopAllEndpoints(); client.stopAdvertising(); client.stopDiscovery(); found.clear()
    }
    fun close() { stop(); handler.removeCallbacksAndMessages(null); channel.setMethodCallHandler(null) }
}
