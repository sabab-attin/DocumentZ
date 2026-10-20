package com.example.documentz

/** Pure routing policy; it never requests permissions or changes device settings. */
object LocalSyncRoutePolicy {
    data class Route(val network: Int, val address: ByteArray, val prefix: Int, val validated: Boolean)
    private fun ipv4(host: String): ByteArray? {
        val parts = host.split('.')
        if (parts.size != 4) return null
        val values = parts.map { if (!it.matches(Regex("0|[1-9][0-9]{0,2}"))) return null else it.toInt() }
        if (values.any { it !in 0..255 }) return null
        return values.map { it.toByte() }.toByteArray()
    }
    fun isLocal(host: String): Boolean {
        val bytes = ipv4(host) ?: return false
        val a = bytes[0].toInt() and 255; val b = bytes[1].toInt() and 255
        return a == 10 || (a == 172 && b in 16..31) || (a == 192 && b == 168) || (a == 169 && b == 254)
    }
    fun choose(host: String, routes: List<Route>): Int? {
        if (!isLocal(host)) return null
        val target = ipv4(host) ?: return null
        return routes.filter { route ->
            route.address.size == 4 && route.prefix in 1..32 && (0 until route.prefix).all { bit ->
                val mask = 1 shl (7 - bit % 8)
                (route.address[bit / 8].toInt() and mask) == (target[bit / 8].toInt() and mask)
            }
        }.maxWithOrNull(compareBy<Route> { it.validated }.thenBy { it.prefix })?.network
    }
}
