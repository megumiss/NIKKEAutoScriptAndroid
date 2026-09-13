package com.megumiss.nkas.mobile.platform.adb

import java.net.URI

/** Parsed endpoint for the ordinary TCP ADB transport. */
data class AdbEndpoint(val host: String, val port: Int) {
    init {
        require(host.isNotBlank()) { "ADB host is required" }
        require(port in 1..65535) { "ADB port must be between 1 and 65535" }
    }

    override fun toString(): String = "adb://${if (host.contains(':')) "[$host]" else host}:$port"

    companion object {
        fun parse(value: String): AdbEndpoint {
            val trimmed = value.trim()
            val input = if (trimmed.contains("://")) trimmed else "adb://$trimmed"
            require(input.startsWith("adb://", ignoreCase = true)) {
                "ADB endpoint must use host:port or adb://host:port"
            }
            val uri = runCatching { URI(input) }.getOrElse {
                throw IllegalArgumentException("Invalid ADB endpoint", it)
            }
            require(uri.scheme.equals("adb", ignoreCase = true)) {
                "ADB endpoint must use host:port or adb://host:port"
            }
            require(uri.userInfo == null && uri.query == null && uri.fragment == null) {
                "ADB endpoint cannot contain credentials, query, or fragment"
            }
            val host = uri.host?.trim()?.removePrefix("[")?.removeSuffix("]").orEmpty()
            require(host.isNotBlank()) { "ADB host is required" }
            require(uri.port in 1..65535) { "ADB port must be between 1 and 65535" }
            return AdbEndpoint(host, uri.port)
        }
    }
}
