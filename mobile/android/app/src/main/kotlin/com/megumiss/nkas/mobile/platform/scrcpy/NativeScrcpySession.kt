package com.megumiss.nkas.mobile.platform.scrcpy

import com.megumiss.nkas.mobile.platform.adb.AdbStream
import com.megumiss.nkas.mobile.platform.adb.NativeAdbManager
import java.io.Closeable
import java.io.DataInputStream
import java.io.EOFException
import java.io.IOException
import java.util.concurrent.ThreadLocalRandom
import java.util.concurrent.atomic.AtomicBoolean
import android.view.Surface

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
    val controlWriter: ScrcpyControlWriter? = controlStream?.let { ScrcpyControlWriter(it.outputStream) }

    private var videoThread: Thread? = null
    private var videoDecoder: NativeVideoDecoder? = null
    private var videoSurface: Surface? = null
    private val closed = AtomicBoolean(false)

    fun startVideo(surface: Surface, listener: VideoListener) {
        check(videoStream != null) { "scrcpy video is disabled" }
        check(videoThread == null) { "scrcpy video is already started" }
        videoSurface = surface
        videoThread = Thread({ readVideo(surface, listener) }, "nkas-scrcpy-video").apply {
            isDaemon = true
            start()
        }
    }

    private fun readVideo(surface: Surface, listener: VideoListener) {
        try {
            val reader = ScrcpyVideoReader(videoStream!!.inputStream)
            while (!closed.get()) {
                when (val item = reader.readNext()) {
                    is ScrcpyVideoSessionSize -> {
                        videoDecoder?.close()
                        videoDecoder = NativeVideoDecoder(videoMetadata!!.codecId, item.width, item.height, surface)
                            .also { it.start() }
                        listener.onSize(item.width, item.height)
                    }
                    is ScrcpyVideoPacket -> {
                        val decoder = videoDecoder ?: continue
                        var queued = false
                        repeat(20) {
                            if (decoder.queue(item)) {
                                queued = true
                                return@repeat
                            }
                            decoder.drain()
                            Thread.sleep(5L)
                        }
                        if (!queued) {
                            if (item.isKeyFrame) throw IOException("scrcpy decoder input stalled on key frame")
                            continue
                        }
                        while (decoder.drain() >= 0) {
                            // Drain all decoded frames available without blocking.
                        }
                    }
                }
            }
        } catch (error: Exception) {
            if (!closed.get()) listener.onError(error)
        } finally {
            videoDecoder?.close()
            videoDecoder = null
            if (!closed.get()) listener.onStopped()
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        videoStream?.close()
        videoThread?.interrupt()
        videoThread?.join(VIDEO_THREAD_JOIN_MS)
        videoThread = null
        videoDecoder?.close()
        videoDecoder = null
        videoSurface?.release()
        videoSurface = null
        controlStream?.close()
        videoStream?.takeUnless { it === controlStream }?.close()
        serverStream.close()
    }

    interface VideoListener {
        fun onSize(width: Int, height: Int)
        fun onError(error: Throwable)
        fun onStopped()
    }

    companion object {
        private const val VIDEO_THREAD_JOIN_MS = 500L
    }
}
