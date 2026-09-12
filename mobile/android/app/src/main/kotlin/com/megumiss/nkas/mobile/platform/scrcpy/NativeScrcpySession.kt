package com.megumiss.nkas.mobile.platform.scrcpy

import com.megumiss.nkas.mobile.platform.adb.AdbStream
import com.megumiss.nkas.mobile.platform.adb.NativeAdbManager
import java.io.Closeable
import java.io.DataInputStream
import java.io.EOFException
import java.io.IOException
import java.util.concurrent.ThreadLocalRandom

/** Starts the scrcpy server over an already connected native ADB session. */
class NativeScrcpyLauncher(
    private val adb: NativeAdbManager,
    private val serverVersion: String = ScrcpyServerCommand.DEFAULT_VERSION,
    private val remotePath: String = ScrcpyServerCommand.DEFAULT_REMOTE_PATH,
) {
    fun start(serverJar: ByteArray, options: ScrcpyServerOptions = ScrcpyServerOptions()): NativeScrcpySession {
        require(serverJar.isNotEmpty()) { "scrcpy server jar is empty" }
        val scid = ThreadLocalRandom.current().nextInt(1, 0x7fffffff)
        adb.push(serverJar, remotePath)
        val command = ScrcpyServerCommand.build(remotePath, serverVersion, scid, options)
        val serverStream = adb.openShellStream(command)
        try {
            val socketName = ScrcpyServerCommand.socketName(scid)
            val first = openWithRetry(socketName)
            val video = if (options.video) first else null
            val control = if (options.control) {
                if (video == null) first else openWithRetry(socketName)
            } else null
            val metadata = if (video != null) readVideoMetadata(video) else null
            return NativeScrcpySession(scid, command, serverStream, video, control, metadata)
        } catch (error: Exception) {
            serverStream.close()
            throw if (error is IOException) error else IOException("Unable to start scrcpy server", error)
        }
    }

    private fun openWithRetry(socketName: String): AdbStream {
        var lastError: Exception? = null
        repeat(MAX_SOCKET_ATTEMPTS) {
            try {
                return adb.openAbstractSocket(socketName)
            } catch (error: Exception) {
                lastError = error
                Thread.sleep(SOCKET_RETRY_DELAY_MS)
            }
        }
        throw IOException("Unable to connect to scrcpy socket $socketName", lastError)
    }

    private fun readVideoMetadata(stream: AdbStream): VideoMetadata {
        val input = DataInputStream(stream.inputStream)
        if (input.read() < 0) throw EOFException("scrcpy dummy byte missing")
        val deviceNameBytes = ByteArray(DEVICE_NAME_LENGTH)
        input.readFully(deviceNameBytes)
        val end = deviceNameBytes.indexOf(0)
        val length = if (end >= 0) end else deviceNameBytes.size
        return VideoMetadata(deviceNameBytes.copyOf(length).toString(Charsets.UTF_8), input.readInt())
    }

    companion object {
        private const val MAX_SOCKET_ATTEMPTS = 100
        private const val SOCKET_RETRY_DELAY_MS = 100L
        private const val DEVICE_NAME_LENGTH = 64
    }
}

data class VideoMetadata(val deviceName: String, val codecId: Int)

class NativeScrcpySession internal constructor(
    val scid: Int,
    val command: String,
    private val serverStream: AdbStream,
    val videoStream: AdbStream?,
    val controlStream: AdbStream?,
    val videoMetadata: VideoMetadata?,
) : Closeable {
    override fun close() {
        controlStream?.close()
        videoStream?.takeUnless { it === controlStream }?.close()
        serverStream.close()
    }
}
