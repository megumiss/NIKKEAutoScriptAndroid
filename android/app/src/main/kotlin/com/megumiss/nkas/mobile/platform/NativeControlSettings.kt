package com.megumiss.nkas.mobile.platform

import android.content.Context
import com.megumiss.nkas.mobile.platform.adb.AdbEndpoint
import org.json.JSONObject

class NativeControlSettings(context: Context) {
    private val prefs = context.getSharedPreferences("nkas_native_control", Context.MODE_PRIVATE)
    val mode get() = prefs.getString("mode", "remote_adb")!!
    val endpoint get() = prefs.getString("endpoint", "")!!
    val tailscaleEnabled get() = prefs.getBoolean("tailscaleEnabled", false)
    val hostname get() = prefs.getString("hostname", "nkas-android")!!
    val endpoints: Map<String, String>
        get() {
            val raw = prefs.getString("endpoints", null) ?: return emptyMap()
            val json = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()
            return json.keys().asSequence().associateWith { json.getString(it) }
        }

    fun snapshot(): Map<String, Any> = mapOf(
        "mode" to mode, "endpoint" to endpoint, "tailscaleEnabled" to tailscaleEnabled, "hostname" to hostname,
        "endpoints" to endpoints,
    )

    fun save(values: Map<*, *>): Map<String, Any> {
        val mode = values["mode"] as? String ?: "remote_adb"
        require(mode in setOf("remote_adb", "local_virtual_display")) { "控制模式无效" }
        val endpoint = (values["endpoint"] as? String).orEmpty().trim()
        if (endpoint.isNotEmpty()) AdbEndpoint.parse(endpoint)
        val hostname = (values["hostname"] as? String).orEmpty().trim().ifEmpty { "nkas-android" }
        require(hostname.matches(Regex("[a-zA-Z0-9][a-zA-Z0-9-]{0,62}"))) { "节点名称只能包含字母、数字和连字符" }
        val endpoints = JSONObject()
        (values["endpoints"] as? Map<*, *>).orEmpty().forEach { (name, address) ->
            val key = name.toString()
            val value = address.toString().trim()
            require(key.isNotEmpty()) { "实例名不能为空" }
            if (value.isNotEmpty()) {
                AdbEndpoint.parse(value)
                endpoints.put(key, value)
            }
        }
        prefs.edit().putString("mode", mode).putString("endpoint", endpoint)
            .putBoolean("tailscaleEnabled", values["tailscaleEnabled"] as? Boolean ?: false)
            .putString("hostname", hostname).putString("endpoints", endpoints.toString()).apply()
        return snapshot()
    }
}
