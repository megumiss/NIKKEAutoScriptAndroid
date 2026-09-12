package com.megumiss.nkas.mobile.platform.scrcpy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScrcpyServerCommandTest {
    @Test
    fun buildsMinimalVideoControlCommand() {
        val command = ScrcpyServerCommand.build(
            remotePath = "/data/local/tmp/scrcpy-server.jar",
            version = "4.1",
            scid = 0x1234,
            options = ScrcpyServerOptions(),
        )
        assertEquals(
            "CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / " +
                "com.genymobile.scrcpy.Server 4.1 scid=1234 tunnel_forward=true audio=false",
            command,
        )
    }

    @Test
    fun includesDisabledChannelsAndLimits() {
        val command = ScrcpyServerCommand.build(
            "/data/local/tmp/server.jar",
            "4.1",
            7,
            ScrcpyServerOptions(video = false, audio = false, control = true, maxSize = 1080, videoBitRate = 8_000_000),
        )
        assertTrue(command.contains("video=false"))
        assertTrue(command.contains("audio=false"))
        assertTrue(command.contains("max_size=1080"))
        assertTrue(command.contains("video_bit_rate=8000000"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsShellUnsafeVersion() {
        ScrcpyServerCommand.build("/tmp/server.jar", "4.1;id", 1, ScrcpyServerOptions())
    }

    @Test
    fun formatsSocketNameAsEightHexDigits() {
        assertEquals("scrcpy_00000007", ScrcpyServerCommand.socketName(7))
    }
}
