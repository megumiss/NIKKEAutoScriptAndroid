package com.megumiss.nkas.mobile.preview.platform

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import java.io.IOException
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket

/**
 * 移植自 Shizuku 的 AdbMdns：通过 mDNS 发现本机无线调试广播的服务端口。
 * 只接受解析地址属于本机网卡、且端口确实在本机监听的服务，避免误连局域网中的其他设备。
 * 回调可能运行在 binder 线程，调用方需要自行切换到主线程。
 */
class AdbMdns(context: Context, private val serviceType: String, private val callback: (Int) -> Unit) {

    private var registered = false
    private var running = false
    private var serviceName: String? = null
    private val listener = DiscoveryListener()
    private val nsdManager: NsdManager? = context.getSystemService(NsdManager::class.java)

    fun start() {
        if (running) return
        running = true
        if (!registered) {
            runCatching { nsdManager?.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener) }
                .onFailure { Log.w(TAG, "discoverServices failed", it) }
        }
    }

    fun stop() {
        if (!running) return
        running = false
        if (registered) {
            runCatching { nsdManager?.stopServiceDiscovery(listener) }
        }
    }

    private fun handleResolved(info: NsdServiceInfo) {
        if (!running) return
        val localAddresses = NetworkInterface.getNetworkInterfaces()?.asSequence()
            ?.flatMap { it.inetAddresses.asSequence() }
            ?.mapNotNull { it.hostAddress }
            ?.toSet() ?: return
        if (info.host?.hostAddress !in localAddresses) return
        if (!isPortListening(info.port)) return
        serviceName = info.serviceName
        Log.i(TAG, "resolved $serviceType at 127.0.0.1:${info.port}")
        callback(info.port)
    }

    private fun handleLost(info: NsdServiceInfo) {
        if (info.serviceName == serviceName) callback(-1)
    }

    // 能在 127.0.0.1 上绑定成功说明端口空闲、不是本机服务；绑定失败（被占用）才是本机 adbd
    private fun isPortListening(port: Int) = try {
        ServerSocket().use { it.bind(InetSocketAddress("127.0.0.1", port), 1) }
        false
    } catch (_: IOException) {
        true
    }

    private inner class DiscoveryListener : NsdManager.DiscoveryListener {
        override fun onDiscoveryStarted(serviceType: String) { registered = true }
        override fun onDiscoveryStopped(serviceType: String) { registered = false }
        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) { Log.w(TAG, "discovery failed: $errorCode") }
        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        override fun onServiceFound(serviceInfo: NsdServiceInfo) {
            runCatching { nsdManager?.resolveService(serviceInfo, ResolveListener()) }
        }
        override fun onServiceLost(serviceInfo: NsdServiceInfo) { handleLost(serviceInfo) }
    }

    private inner class ResolveListener : NsdManager.ResolveListener {
        override fun onResolveFailed(nsdServiceInfo: NsdServiceInfo, errorCode: Int) {}
        override fun onServiceResolved(nsdServiceInfo: NsdServiceInfo) { handleResolved(nsdServiceInfo) }
    }

    companion object {
        const val TLS_CONNECT = "_adb-tls-connect._tcp"
        const val TLS_PAIRING = "_adb-tls-pairing._tcp"
        private const val TAG = "NkasAdbMdns"
    }
}
