package com.megumiss.nkas.mobile.platform.scrcpy

import android.media.MediaCodec
import android.media.MediaFormat
import android.view.Surface
import java.io.Closeable

/** Thin MediaCodec adapter; stream reading remains owned by NativeScrcpySession. */
class NativeVideoDecoder(
    private val codecId: Int,
    private val width: Int,
    private val height: Int,
    private val surface: Surface,
) : Closeable {
    private var codec: MediaCodec? = null

    fun start() {
        check(codec == null) { "video decoder is already started" }
        val mime = mimeForCodec(codecId)
        val format = MediaFormat.createVideoFormat(mime, width, height)
        codec = MediaCodec.createDecoderByType(mime).also {
            it.configure(format, surface, null, 0)
            it.start()
        }
    }

    fun queue(packet: ScrcpyVideoPacket, timeoutUs: Long = 10_000): Boolean {
        val current = codec ?: throw IllegalStateException("video decoder is not started")
        val index = current.dequeueInputBuffer(timeoutUs)
        if (index < 0) return false
        val buffer = current.getInputBuffer(index) ?: return false
        buffer.clear()
        buffer.put(packet.payload)
        current.queueInputBuffer(index, 0, packet.payload.size, packet.ptsUs, 0)
        return true
    }

    fun drain(render: Boolean = true, timeoutUs: Long = 0): Int {
        val current = codec ?: throw IllegalStateException("video decoder is not started")
        val info = MediaCodec.BufferInfo()
        val index = current.dequeueOutputBuffer(info, timeoutUs)
        if (index >= 0) current.releaseOutputBuffer(index, render)
        return index
    }

    override fun close() {
        codec?.let { runCatching { it.stop() }; runCatching { it.release() } }
        codec = null
    }

    private fun mimeForCodec(id: Int): String = when (id.toAscii()) {
        "h264" -> MediaFormat.MIMETYPE_VIDEO_AVC
        "h265", "hevc" -> MediaFormat.MIMETYPE_VIDEO_HEVC
        else -> throw IllegalArgumentException("Unsupported scrcpy video codec id: 0x${id.toUInt().toString(16)}")
    }

    private fun Int.toAscii(): String = buildString {
        repeat(4) { append(((this@toAscii ushr (it * 8)) and 0xff).toChar()) }
    }
}
