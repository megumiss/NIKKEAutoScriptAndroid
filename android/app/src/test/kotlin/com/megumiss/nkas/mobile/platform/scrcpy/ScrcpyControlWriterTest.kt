package com.megumiss.nkas.mobile.platform.scrcpy

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ScrcpyControlWriterTest {
    @Test
    fun validatesUtf8LimitBeforeWriting() {
        val output = ByteArrayOutputStream()
        val writer = ScrcpyControlWriter(output)
        writer.injectText("文".repeat(100))
        assertEquals(305, output.size())
        output.reset()
        assertThrows(IllegalArgumentException::class.java) { writer.injectText("文".repeat(101)) }
        assertEquals(0, output.size())
    }

    @Test
    fun rejectsOutOfBoundsTouchWithoutPartialPacket() {
        val output = ByteArrayOutputStream()
        val writer = ScrcpyControlWriter(output)
        assertThrows(IllegalArgumentException::class.java) { writer.injectTouch(0, 0, 1080, 0, 1080, 1920) }
        assertThrows(IllegalArgumentException::class.java) { writer.injectTouch(0, 0, 0, 0, 1080, 1920, Float.NaN) }
        assertEquals(0, output.size())
    }

    @Test
    fun writesOneTransportMessageAndReleasesPressureOnCancel() {
        var writes = 0
        val output = object : ByteArrayOutputStream() {
            override fun write(bytes: ByteArray, offset: Int, length: Int) {
                writes++
                super.write(bytes, offset, length)
            }
        }
        ScrcpyControlWriter(output).injectTouch(3, 0, 10, 20, 1080, 1920)
        assertEquals(1, writes)
        assertEquals(0, output.toByteArray()[22].toInt())
        assertEquals(0, output.toByteArray()[23].toInt())
    }

    @Test
    fun writesKeycodeInBigEndianOrder() {
        val output = ByteArrayOutputStream()
        ScrcpyControlWriter(output).injectKeycode(action = 0, keycode = 66, repeat = 2, metaState = 1)
        val input = DataInputStream(ByteArrayInputStream(output.toByteArray()))
        assertEquals(0, input.readUnsignedByte())
        assertEquals(0, input.readUnsignedByte())
        assertEquals(66, input.readInt())
        assertEquals(2, input.readInt())
        assertEquals(1, input.readInt())
    }

    @Test
    fun writesUtf8TextLengthAndPayload() {
        val output = ByteArrayOutputStream()
        ScrcpyControlWriter(output).injectText("你好")
        val input = DataInputStream(ByteArrayInputStream(output.toByteArray()))
        assertEquals(1, input.readUnsignedByte())
        assertEquals(6, input.readInt())
        val bytes = ByteArray(6).also(input::readFully)
        assertEquals("你好", bytes.toString(Charsets.UTF_8))
    }

    @Test
    fun writesTouchCoordinatesAndClampedPressure() {
        val output = ByteArrayOutputStream()
        ScrcpyControlWriter(output).injectTouch(2, 7L, 100, 200, 1080, 1920, pressure = 2f)
        val input = DataInputStream(ByteArrayInputStream(output.toByteArray()))
        assertEquals(2, input.readUnsignedByte())
        assertEquals(2, input.readUnsignedByte())
        assertEquals(7L, input.readLong())
        assertEquals(100, input.readInt())
        assertEquals(200, input.readInt())
        assertEquals(1080, input.readUnsignedShort())
        assertEquals(1920, input.readUnsignedShort())
        assertEquals(0xffff, input.readUnsignedShort())
    }
}
