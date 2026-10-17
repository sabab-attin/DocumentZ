package com.example.documentz

import java.net.URI

/** Pure policy shared by foreground and background update checks. */
object UpdatePolicy {
    private val stable = Regex("^v?\\.?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
    fun version(value: String): List<Int>? {
        val match = stable.matchEntire(value) ?: return null
        return match.groupValues.drop(1).map { it.toIntOrNull() ?: return null }
    }
    fun newer(candidate: String, installed: String): Boolean {
        val next = version(candidate) ?: return false
        val current = version(installed) ?: return false
        for (i in 0..2) if (next[i] != current[i]) return next[i] > current[i]
        return false
    }
    fun assetName(abis: List<String>): String? = abis.firstNotNullOfOrNull {
        when (it) {
            "arm64-v8a" -> "app-arm64-v8a-release.apk"
            "armeabi-v7a" -> "app-armeabi-v7a-release.apk"
            "x86_64" -> "app-x86_64-release.apk"
            else -> null
        }
    }
    fun trustedAsset(url: String, tag: String, filename: String): Boolean = try {
        val uri = URI(url)
        version(tag) != null && uri.scheme == "https" && uri.host == "github.com" &&
            uri.port == -1 && uri.userInfo == null && uri.query == null && uri.fragment == null &&
            uri.rawPath == "/sabab-attin/DocumentZ/releases/download/$tag/$filename"
    } catch (_: Exception) { false }
}
