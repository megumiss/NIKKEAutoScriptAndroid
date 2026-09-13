package com.megumiss.nkas.mobile.platform.adb

import android.content.Context
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.util.concurrent.atomic.AtomicLong

class NativeAdbManager(context: Context) : Closeable {
    private val keyStore = AdbKeyStore(File(context.filesDir, "native-adb"))
    private val localKeyStore = AdbKeyStore(File(context.filesDir, "native-adb/local"))
    private val lock = Any()
    private val generation = AtomicLong()
    @Volatile private var client: NativeAdbClient? = null
    @Volatile private var endpoint: AdbEndpoint? = null

    fun connect(rawEndpoint: String, localIdentity: Boolean = false, isCancelled: () -> Boolean = { false }): AdbEndpoint {
        val parsed = AdbEndpoint.parse(rawEndpoint)
        val token = generation.incrementAndGet()
        val next = NativeAdbClient(parsed, if (localIdentity) localKeyStore else keyStore)
        val previous = synchronized(lock) {
            val previous = client
            client = next
            endpoint = null
            previous
        }
        previous?.interrupt()
        previous?.close()
        try {
            if (generation.get() != token || isCancelled()) throw IOException("ADB connection cancelled")
            next.connect()
            synchronized(lock) {
                if (generation.get() != token) throw IOException("ADB connection cancelled")
                endpoint = parsed
            }
            return parsed
        } catch (error: Exception) {
            next.interrupt()
            next.close()
            synchronized(lock) { if (client === next) client = null }
            throw error
        }
    }

    fun connectLocalForward(localPort: Int): AdbEndpoint = connect("127.0.0.1:$localPort")
    fun shell(command: String): String = requireClient().shell(command)
    fun openShellStream(command: String): AdbStream = requireClient().openStream("shell:$command")
    fun openAbstractSocket(name: String): AdbStream = requireClient().openStream("localabstract:$name")
    fun push(data: ByteArray, remotePath: String, unixMode: Int = 420) = requireClient().push(data, remotePath, unixMode)
    fun pull(remotePath: String): ByteArray = requireClient().pull(remotePath)
    fun currentEndpoint(): AdbEndpoint? = endpoint
    fun importLocalIdentity(pem: String) = localKeyStore.importPem(pem)

    fun interrupt() {
        generation.incrementAndGet()
        client?.interrupt()
    }

    override fun close() {
        interrupt()
        val previous = synchronized(lock) {
            val previous = client
            client = null
            endpoint = null
            previous
        }
        previous?.interrupt()
        previous?.close()
    }

    private fun requireClient(): NativeAdbClient =
        client?.takeIf { it.isConnected() } ?: throw IllegalStateException("ADB is not connected")
}
