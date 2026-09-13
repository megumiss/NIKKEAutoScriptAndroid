package com.megumiss.nkas.mobile.platform.scrcpy

import java.io.DataInputStream
import java.io.EOFException
import java.io.InputStream

data class ScrcpyVideoPacket(
    val payload: ByteArray,
    val ptsUs: Long,
    val isConfig: Boolean,
    val isKeyFrame: Boolean,
)

internal data class ScrcpyVideoSessionSize(val width: Int, val height: Int)

internal class ScrcpyVideoReader(private val input: InputStream) {
    private val data = DataInputStream(input)

    fun readNext(): Any {
        val header = ByteArray(12)
        try {
            data.readFully(header)
        } catch (error: EOFException) {
            throw error
        }
        val ptsAndFlags = readLongBe(header, 0)
        val session = ptsAndFlags and SESSION_FLAG != 0L
        if (session) {
            val width = readIntBe(header, 4)
            val height = readIntBe(header, 8)
            require(width > 0 && height > 0) { "scrcpy session size is invalid: ${width}x$height" }
            return ScrcpyVideoSessionSize(width, height)
        }
        val length = readIntBe(header, 8)
        require(length in 0..MAX_PACKET_SIZE) { "scrcpy video packet size is invalid: $length" }
        val payload = ByteArray(length)
        data.readFully(payload)
        return ScrcpyVideoPacket(
            payload = payload,
            ptsUs = ptsAndFlags and PTS_MASK,
            isConfig = ptsAndFlags and CONFIG_FLAG != 0L,
            isKeyFrame = ptsAndFlags and KEY_FRAME_FLAG != 0L,
        )
    }

    private fun readLongBe(bytes: ByteArray, offset: Int): Long {
        var value = 0L
        repeat(8) { value = (value shl 8) or (bytes[offset + it].toLong() and 0xff) }
        return value
    }

    private fun readIntBe(bytes: ByteArray, offset: Int): Int =
        ((bytes[offset].toInt() and 0xff) shl 24) or
            ((bytes[offset + 1].toInt() and 0xff) shl 16) or
            ((bytes[offset + 2].toInt() and 0xff) shl 8) or
            (bytes[offset + 3].toInt() and 0xff)

    companion object {
        private const val SESSION_FLAG = 1L shl 63
        private const val CONFIG_FLAG = 1L shl 62
        private const val KEY_FRAME_FLAG = 1L shl 61
        private const val PTS_MASK = (1L shl 61) - 1
        private const val MAX_PACKET_SIZE = 32 * 1024 * 1024
    }
}
