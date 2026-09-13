package com.megumiss.nkas.mobile.platform.scrcpy

import android.media.MediaCodec
import android.media.MediaFormat
import android.view.Surface
import java.io.Closeable
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

/** Thin MediaCodec adapter; stream reading remains owned by NativeScrcpySession. */
class NativeVideoDecoder(
    private val codecId: Int,
    private val width: Int,
    private val height: Int,
    private val surface: Surface,
    private val onFrame: () -> Unit,
    private val onError: (Throwable) -> Unit,
) : Closeable {
    private var codec: MediaCodec? = null
    private val closed = AtomicBoolean(false)
    private var outputThread: Thread? = null

    fun start() {
        check(codec == null) { "video decoder is already started" }
        val mime = mimeForCodec(codecId)
        val format = MediaFormat.createVideoFormat(mime, width, height)
        val current = MediaCodec.createDecoderByType(mime)
        codec = current
        try {
            current.configure(format, surface, null, 0)
            current.start()
            outputThread = Thread({
                try {
                    val info = MediaCodec.BufferInfo()
                    while (!closed.get()) {
                        val index = current.dequeueOutputBuffer(info, 10_000)
                        if (index >= 0) {
                            current.releaseOutputBuffer(index, true)
                            onFrame()
                        }
                    }
                } catch (error: Exception) {
                    if (!closed.get()) onError(error)
                }
            }, "nkas-scrcpy-render").apply { isDaemon = true; start() }
        } catch (error: Exception) {
            close()
            throw error
        }
    }

    fun queue(packet: ScrcpyVideoPacket, timeoutUs: Long = 10_000): Boolean {
        val current = codec ?: throw IllegalStateException("video decoder is not started")
        val index = current.dequeueInputBuffer(timeoutUs)
        if (index < 0) return false
        val buffer = current.getInputBuffer(index) ?: throw IOException("Missing decoder input buffer")
        buffer.clear()
        if (packet.payload.size > buffer.remaining()) throw IOException("Video packet exceeds decoder capacity")
        buffer.put(packet.payload)
        val flags = if (packet.isConfig) MediaCodec.BUFFER_FLAG_CODEC_CONFIG else 0
        current.queueInputBuffer(index, 0, packet.payload.size, packet.ptsUs, flags)
        return true
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        if (Thread.currentThread() !== outputThread) outputThread?.join(1_000)
        outputThread = null
        codec?.let { runCatching { it.stop() }; runCatching { it.release() } }
        codec = null
    }

    private fun mimeForCodec(id: Int): String = when (id.toAscii()) {
        "h264" -> MediaFormat.MIMETYPE_VIDEO_AVC
        "h265", "hevc" -> MediaFormat.MIMETYPE_VIDEO_HEVC
        else -> throw IllegalArgumentException("Unsupported scrcpy video codec id: 0x${id.toUInt().toString(16)}")
    }

    private fun Int.toAscii(): String = buildString {
        repeat(4) { append(((this@toAscii ushr ((3 - it) * 8)) and 0xff).toChar()) }
    }
}
