package com.megumiss.nkas.mobile.platform.adb

import org.junit.Assert.assertEquals
import org.junit.Test

class AdbEndpointTest {
    @Test
    fun parsesHostAndPort() {
        assertEquals(AdbEndpoint("100.64.0.10", 5555), AdbEndpoint.parse("adb://100.64.0.10:5555"))
    }

    @Test
    fun preservesBracketedIpv6() {
        val endpoint = AdbEndpoint.parse("adb://[fd7a:115c:a1e0::10]:5555")
        assertEquals("fd7a:115c:a1e0::10", endpoint.host)
        assertEquals("adb://[fd7a:115c:a1e0::10]:5555", endpoint.toString())
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsNonAdbScheme() {
        AdbEndpoint.parse("tcp://127.0.0.1:5555")
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsMissingPort() {
        AdbEndpoint.parse("adb://127.0.0.1")
    }
}
