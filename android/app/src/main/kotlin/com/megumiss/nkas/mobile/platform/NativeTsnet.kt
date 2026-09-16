package com.megumiss.nkas.mobile.platform

import android.content.Context
import android.net.ConnectivityManager
import com.megumiss.nkas.mobile.platform.adb.AdbEndpoint
import com.megumiss.nkas.tsnet.nativetsnet.Nativetsnet
import go.Seq
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.NetworkInterface

/** Called on the session worker, except interrupt which only cancels a pending connect. */
class NativeTsnet(context: Context, private val settings: NativeControlSettings) {
    private val app = context.applicationContext
    private val stateDir = File(app.filesDir, "tsnet")
    private val client = run { Seq.setContext(app); Nativetsnet.newClient() }

    fun configure(authKey: String) {
        client.close()
        client.configure(authKey, settings.hostname, stateDir.absolutePath)
    }

    fun connect() {
        val phase = JSONObject(client.status()).optString("phase")
        if (phase !in setOf("configured", "connecting", "connected", "error")) configure("")
        refreshNetworkInterfaces()
        lastCancelReason = ""
        try {
            client.connect()
        } catch (error: Exception) {
            throw withCancelReason(error)
        }
    }

    /** 最近一次取消待建立连接的来源；context canceled 报错附带它便于诊断 */
    @Volatile private var lastCancelReason = ""

    fun interrupt(reason: String) {
        if (reason.isNotEmpty()) lastCancelReason = reason
        client.interrupt()
    }

    private fun withCancelReason(error: Exception): Exception {
        val reason = lastCancelReason
        val message = error.message ?: return error
        if (reason.isEmpty() || !message.contains("context canceled")) return error
        return IOException("$message（取消来源：$reason）")
    }

    fun startForward(endpoint: AdbEndpoint, localPort: Int = 0): Map<String, Any> {
        connect()
        val value = JSONObject(client.startForward(endpoint.host, endpoint.port.toLong(), localPort.toLong()))
        return mapOf("id" to value.getString("id"), "remoteHost" to value.getString("remoteHost"),
            "remotePort" to value.getInt("remotePort"), "localPort" to value.getInt("localPort"))
    }

    fun stopForward(id: String) = client.stopForward(id)
    fun stopAll() = client.stopAll()
    fun close() = client.close()

    fun clearState() {
        // Configure may never have run in this process, but a previous node can exist on disk.
        client.close()
        if (client.hasPersistedLogin(stateDir.absolutePath)) {
            client.configure("", settings.hostname, stateDir.absolutePath)
        }
        client.clearState()
        if (stateDir.exists()) {
            check(stateDir.canonicalFile.parentFile == app.filesDir.canonicalFile)
            check(stateDir.deleteRecursively()) { "无法清除 Tailscale 身份" }
        }
    }

    fun status(): Map<String, Any> {
        val value = JSONObject(client.status())
        val addresses = value.optJSONArray("addresses") ?: JSONArray()
        return mapOf("phase" to value.optString("phase"), "hostname" to settings.hostname,
            "addresses" to (0 until addresses.length()).map { addresses.getString(it) },
            "forwardCount" to value.optInt("forwardCount"), "error" to value.optString("error"),
            "hasPersistedLogin" to client.hasPersistedLogin(stateDir.absolutePath))
    }

    private fun refreshNetworkInterfaces() {
        val manager = app.getSystemService(ConnectivityManager::class.java)
        val properties = manager?.activeNetwork?.let { manager.getLinkProperties(it) }
        val interfaces = JSONArray()
        NetworkInterface.getNetworkInterfaces()?.toList()?.forEach { network ->
            val addresses = JSONArray()
            network.interfaceAddresses.forEach { address ->
                val ip = address.address?.hostAddress ?: return@forEach
                addresses.put(JSONObject().put("ip", ip).put("prefixLen", address.networkPrefixLength.toInt()))
            }
            interfaces.put(JSONObject().put("name", network.name).put("index", network.index)
                .put("mtu", network.mtu).put("up", network.isUp).put("loopback", network.isLoopback)
                .put("pointToPoint", network.isPointToPoint).put("multicast", network.supportsMulticast())
                .put("broadcast", network.interfaceAddresses.any { it.broadcast != null }).put("addrs", addresses))
        }
        client.setAndroidNetworkInterfaces(interfaces.toString(), properties?.interfaceName.orEmpty())
    }
}
