package com.megumiss.nkas.mobile.platform.adb

import java.io.ByteArrayInputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class AdbProtocolTest {
    @Test
    fun roundTripsMessageWithLittleEndianFields() {
        val payload = byteArrayOf(0, 1, 127, -1)
        val encoded = AdbProtocol.encode(CNXN, 7, 9, payload)
        val decoded = AdbProtocol.decode(ByteArrayInputStream(encoded))

        assertEquals(CNXN, decoded.command)
        assertEquals(7, decoded.arg0)
        assertEquals(9, decoded.arg1)
        assertArrayEquals(payload, decoded.payload)
        assertEquals(CNXN, ByteBuffer.wrap(encoded, 0, 4).order(ByteOrder.LITTLE_ENDIAN).int)
    }

    @Test(expected = IOException::class)
    fun rejectsInvalidMagic() {
        val encoded = AdbProtocol.encode(CNXN, 0, 0, ByteArray(0))
        encoded[20] = 0
        AdbProtocol.decode(ByteArrayInputStream(encoded))
    }

    @Test(expected = IOException::class)
    fun rejectsInvalidChecksum() {
        val encoded = AdbProtocol.encode(CNXN, 0, 0, byteArrayOf(1, 2, 3))
        encoded[16] = (encoded[16].toInt() xor 1).toByte()
        AdbProtocol.decode(ByteArrayInputStream(encoded))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsOversizedPayload() {
        AdbProtocol.encode(CNXN, 0, 0, ByteArray(AdbProtocol.MAX_PAYLOAD + 1))
    }

    @Test
    fun checksumIncludesUnsignedPayloadBytes() {
        val encoded = AdbProtocol.encode(CNXN, 0, 0, byteArrayOf(-1, -2))
        val checksum = ByteBuffer.wrap(encoded, 16, 4).order(ByteOrder.LITTLE_ENDIAN).int
        assertEquals(509, checksum)
    }

    private companion object {
        const val CNXN = 0x4e584e43
    }
}
