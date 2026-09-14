package com.megumiss.nkas.mobile.platform

import org.junit.Assert.*
import org.junit.Test

class BackendEntryTest {
    @Test fun localSourceDoesNotAcceptRemoteHosts() {
        assertTrue(BackendEntry.isLocalHost("127.0.0.1"))
        assertTrue(BackendEntry.isLocalHost("::1"))
        assertFalse(BackendEntry.isLocalHost("192.168.1.2"))
        assertFalse(BackendEntry.isLocalHost("127.0.0.1.example.com"))
    }

    @Test fun parsesOnlyACompletePrivateKey() {
        assertNull(BackendEntry.parseKey("disabled\n"))
        assertEquals("a".repeat(43), BackendEntry.parseKey("enabled\n" + "a".repeat(43) + "\n"))
        assertThrows(IllegalArgumentException::class.java) { BackendEntry.parseKey("enabled\nshort") }
        assertThrows(IllegalArgumentException::class.java) { BackendEntry.parseKey("enabled\n" + "a".repeat(43) + "\nextra") }
    }
}
