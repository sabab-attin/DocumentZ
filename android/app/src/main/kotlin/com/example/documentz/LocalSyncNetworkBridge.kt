package com.example.documentz

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Pins only the sync TCP socket to an eligible Wi-Fi network. Never binds the
 * application process, changes the default network, or bypasses an active VPN.
 * The loopback bridge streams bounded buffers; Dart retains the authenticated,
 * encrypted sync protocol and matching-number approval. */
class LocalSyncNetworkBridge(context: Context, engine: FlutterEngine) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newCachedThreadPool()
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "documentz/lan_sync")
    private val connections = ConcurrentHashMap<String, Link>()
    @Volatile private var closed = false
    private class Link(val remote: Socket, val listener: ServerSocket) {
        @Volatile var local: Socket? = null
        fun close() {
            try { local?.close() } catch (_: Exception) {}
            try { listener.close() } catch (_: Exception) {}
            try { remote.close() } catch (_: Exception) {}
        }
    }
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val host = call.argument<String>("host") ?: ""
                    val port = call.argument<Int>("port") ?: 0
                    if (!LocalSyncRoutePolicy.isLocal(host) || port !in 1..65535) {
                        result.error("invalid_address", "Expected a local IPv4 sync address.", null)
                    } else {
                        val timeout = (call.argument<Int>("timeoutMs") ?: 4000).coerceIn(100, 10000)
                        connect(host, port, timeout, result)
                    }
                }
                "close" -> {
                    call.argument<String>("id")?.let { connections.remove(it)?.close() }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun connect(host: String, port: Int, timeout: Int, result: MethodChannel.Result) {
        worker.execute {
            var link: Link? = null
            var delivered = false
            try {
                if (closed) throw IllegalStateException("Sync connection is closed.")
                val active = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                // Returning null leaves Dart on the ordinary, VPN-respecting route.
                if (active?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) {
                    handler.post { result.success(null) }; return@execute
                }
                val networks = connectivity.allNetworks.toList()
                val routes = networks.flatMapIndexed { index, network ->
                    val caps = connectivity.getNetworkCapabilities(network)
                    if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true ||
                        !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) emptyList()
                    else connectivity.getLinkProperties(network)?.linkAddresses.orEmpty()
                        .filter { it.address is Inet4Address }
                        .map { LocalSyncRoutePolicy.Route(index, it.address.address, it.prefixLength,
                            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) }
                }
                val selected = LocalSyncRoutePolicy.choose(host, routes)
                if (selected == null) { handler.post { result.success(null) }; return@execute }
                val remote = networks[selected].socketFactory.createSocket()
                try { remote.tcpNoDelay = true; remote.connect(InetSocketAddress(host, port), timeout) }
                catch (error: Exception) { remote.close(); throw error }
                val listener = ServerSocket()
                try { listener.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), 0), 1); listener.soTimeout = 10000 }
                catch (error: Exception) { remote.close(); listener.close(); throw error }
                val token = ByteArray(16).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
                val connection = Link(remote, listener)
                link = connection
                if (closed) { connection.close(); throw IllegalStateException("Sync connection is closed.") }
                connections[token] = connection
                delivered = true
                handler.post { result.success(mapOf("id" to token, "port" to listener.localPort)) }
                val local = listener.accept()
                connection.local = local
                local.soTimeout = 10000
                val authentication = ByteArray(32)
                var read = 0
                while (read < authentication.size) {
                    val count = local.getInputStream().read(authentication, read, authentication.size - read)
                    if (count < 0) throw IllegalStateException("Local sync connection closed.")
                    read += count
                }
                if (!java.security.MessageDigest.isEqual(authentication, token.toByteArray(Charsets.US_ASCII)))
                    throw SecurityException("Invalid local sync connection.")
                listener.close()
                local.soTimeout = 0; local.tcpNoDelay = true
                worker.execute { pipe(local, remote, token, connection) }
                pipe(remote, local, token, connection)
            } catch (error: Exception) {
                val connection = link
                if (!delivered) handler.post { result.error("wifi_connect", "Could not reach the sync device over Wi-Fi.", null) }
                if (connection != null) { connections.entries.removeIf { it.value === connection }; connection.close() }
            }
        }
    }
    private fun pipe(input: Socket, output: Socket, token: String, connection: Link) {
        try { input.getInputStream().copyTo(output.getOutputStream(), 16 * 1024) }
        catch (_: Exception) { /* Cancellation and peer disconnect close both directions. */ }
        finally { connections.remove(token, connection); connection.close() }
    }
    fun close() {
        closed = true; channel.setMethodCallHandler(null)
        connections.values.forEach { it.close() }; connections.clear(); worker.shutdownNow()
    }
}
