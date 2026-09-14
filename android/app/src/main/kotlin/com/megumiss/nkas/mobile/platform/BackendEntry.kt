package com.megumiss.nkas.mobile.platform

internal object BackendEntry {
    fun isLocalHost(host: String): Boolean = host in setOf("127.0.0.1", "localhost", "::1", "[::1]")

    fun parseKey(output: String): String? {
        val lines = output.trim().lineSequence().toList()
        if (lines.firstOrNull() == "disabled") return null
        require(lines.size == 2 && lines[0] == "enabled" && Regex("[A-Za-z0-9_-]{43}").matches(lines[1])) {
            "本机安全入口数据无效"
        }
        return lines[1]
    }
}
