package com.megumiss.nkas.mobile.platform.adb

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AdbEndpointTest {
    @Test
    fun parsesHostAndPort() {
        assertEquals(AdbEndpoint("100.64.0.10", 5555), AdbEndpoint.parse("adb://100.64.0.10:5555"))
    }

    @Test
    fun parsesLocalForwardWithoutScheme() {
        assertEquals(AdbEndpoint("127.0.0.1", 43127), AdbEndpoint.parse("127.0.0.1:43127"))
    }

    @Test
    fun normalizesLanEndpointWithOrWithoutScheme() {
        for (value in listOf("adb://192.168.31.219:5555", "192.168.31.219:5555", " 192.168.31.219:5555 ")) {
            assertEquals("adb://192.168.31.219:5555", AdbEndpoint.parse(value).toString())
        }
    }

    @Test
    fun parsesMagicDnsWithoutScheme() {
        assertEquals(AdbEndpoint("redroid.tailnet.ts.net", 5555), AdbEndpoint.parse("redroid.tailnet.ts.net:5555"))
    }

    @Test
    fun preservesBracketedIpv6() {
        val endpoint = AdbEndpoint.parse("adb://[fd7a:115c:a1e0::10]:5555")
        assertEquals("fd7a:115c:a1e0::10", endpoint.host)
        assertEquals("adb://[fd7a:115c:a1e0::10]:5555", endpoint.toString())
        assertEquals(endpoint, AdbEndpoint.parse("[fd7a:115c:a1e0::10]:5555"))
    }

    @Test
    fun rejectsMalformedBareEndpoints() {
        for (value in listOf("", ":5555", "host", "host:0", "host:65536", "fd7a::1:5555")) {
            assertThrows(value, IllegalArgumentException::class.java) { AdbEndpoint.parse(value) }
        }
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
