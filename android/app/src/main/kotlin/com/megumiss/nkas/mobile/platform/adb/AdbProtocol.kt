package com.megumiss.nkas.mobile.platform.adb

import java.io.DataInputStream
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

internal data class AdbMessage(
    val command: Int,
    val arg0: Int,
    val arg1: Int,
    val payload: ByteArray,
)

internal object AdbProtocol {
    const val MAX_PAYLOAD = 256 * 1024

    fun encode(command: Int, arg0: Int, arg1: Int, payload: ByteArray): ByteArray {
        require(payload.size <= MAX_PAYLOAD) { "ADB payload is too large: ${payload.size}" }
        val checksum = payload.fold(0) { sum, byte -> sum + (byte.toInt() and 0xff) }
        return ByteBuffer.allocate(24 + payload.size)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putInt(command)
            .putInt(arg0)
            .putInt(arg1)
            .putInt(payload.size)
            .putInt(checksum)
            .putInt(command xor -1)
            .put(payload)
            .array()
    }

    @Throws(IOException::class)
    fun decode(input: InputStream): AdbMessage {
        val data = DataInputStream(input)
        val header = ByteArray(24)
        data.readFully(header)
        val buffer = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        val command = buffer.int
        val arg0 = buffer.int
        val arg1 = buffer.int
        val length = buffer.int
        val checksum = buffer.int
        val magic = buffer.int
        if (magic != (command xor -1) || length !in 0..MAX_PAYLOAD) {
            throw IOException("Invalid ADB message header")
        }
        val payload = ByteArray(length)
        data.readFully(payload)
        val actual = payload.fold(0) { sum, byte -> sum + (byte.toInt() and 0xff) }
        if (actual != checksum) throw IOException("Invalid ADB message checksum")
        return AdbMessage(command, arg0, arg1, payload)
    }
}
