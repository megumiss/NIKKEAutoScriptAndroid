package com.megumiss.nkas.mobile.platform.adb

import android.content.Context
import java.io.Closeable
import java.io.File

/** Owns the native ADB session used by future scrcpy and device-control flows. */
class NativeAdbManager(context: Context) : Closeable {
    private val keyStore = AdbKeyStore(File(context.filesDir, "native-adb"))
    private var client: NativeAdbClient? = null
    private var endpoint: AdbEndpoint? = null

    @Synchronized
    fun connect(rawEndpoint: String): AdbEndpoint {
        val parsed = AdbEndpoint.parse(rawEndpoint)
        close()
        NativeAdbClient(parsed, keyStore).also {
            it.connect()
            client = it
        }
        endpoint = parsed
        return parsed
    }

    @Synchronized
    fun connectLocalForward(localPort: Int): AdbEndpoint =
        connect("adb://127.0.0.1:$localPort")

    @Synchronized
    fun shell(command: String): String = requireClient().shell(command)

    @Synchronized
    fun push(data: ByteArray, remotePath: String, unixMode: Int = 420) {
        requireClient().push(data, remotePath, unixMode)
    }

    @Synchronized
    fun pull(remotePath: String): ByteArray = requireClient().pull(remotePath)

    @Synchronized
    fun currentEndpoint(): AdbEndpoint? = endpoint

    @Synchronized
    override fun close() {
        client?.close()
        client = null
        endpoint = null
    }

    private fun requireClient(): NativeAdbClient =
        client?.takeIf { it.isConnected() } ?: throw IllegalStateException("ADB is not connected")
}
