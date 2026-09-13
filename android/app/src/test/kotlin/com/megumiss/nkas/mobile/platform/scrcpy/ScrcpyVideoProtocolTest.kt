package com.megumiss.nkas.mobile.platform.scrcpy

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScrcpyVideoProtocolTest {
    @Test
    fun parsesConfigKeyFrameAndPts() {
        val bytes = packet(flags = CONFIG_FLAG or KEY_FRAME_FLAG, pts = 1234, payload = byteArrayOf(1, 2, 3))
        val result = ScrcpyVideoReader(ByteArrayInputStream(bytes)).readNext() as ScrcpyVideoPacket
        assertEquals(1234L, result.ptsUs)
        assertTrue(result.isConfig)
        assertTrue(result.isKeyFrame)
        assertArrayEquals(byteArrayOf(1, 2, 3), result.payload)
    }

    @Test
    fun parsesSessionDimensions() {
        val output = ByteArrayOutputStream()
        DataOutputStream(output).use { data ->
            data.writeLong(SESSION_FLAG or 1080L)
            data.writeInt(1920)
        }
        val result = ScrcpyVideoReader(ByteArrayInputStream(output.toByteArray())).readNext()
            as ScrcpyVideoSessionSize
        assertEquals(ScrcpyVideoSessionSize(1080, 1920), result)
    }

    private fun packet(flags: Long, pts: Long, payload: ByteArray): ByteArray {
        val output = ByteArrayOutputStream()
        DataOutputStream(output).use { data ->
            data.writeLong(flags or pts)
            data.writeInt(payload.size)
            data.write(payload)
        }
        return output.toByteArray()
    }

    private companion object {
        const val CONFIG_FLAG = 1L shl 62
        const val KEY_FRAME_FLAG = 1L shl 61
        const val SESSION_FLAG = 1L shl 63
    }
}
