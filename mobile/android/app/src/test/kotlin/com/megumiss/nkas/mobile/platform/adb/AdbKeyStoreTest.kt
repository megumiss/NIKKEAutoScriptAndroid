package com.megumiss.nkas.mobile.platform.adb

import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AdbKeyStoreTest {
    @Test
    fun persistsKeyAndEncodesAdbPublicKeyLayout() {
        val directory = Files.createTempDirectory("nkas-adb-key").toFile()
        try {
            val first = AdbKeyStore(directory).loadOrCreate()
            val second = AdbKeyStore(directory).loadOrCreate()
            assertEquals(first.publicKey.encoded.toList(), second.publicKey.encoded.toList())
            assertEquals(first.privateKey.encoded.toList(), second.privateKey.encoded.toList())

            val encoded = first.adbPublicKey.toString(Charsets.UTF_8)
            assertTrue(encoded.endsWith(" nkas-mobile\u0000"))
            val body = Base64.getDecoder().decode(encoded.substringBefore(' '))
            assertEquals(524, body.size)
            val buffer = ByteBuffer.wrap(body).order(ByteOrder.LITTLE_ENDIAN)
            assertEquals(64, buffer.int)
            buffer.int
            val modulus = ByteArray(256).also(buffer::get)
            val rr = ByteArray(256).also(buffer::get)
            assertTrue(modulus.any { it.toInt() != 0 })
            assertTrue(rr.any { it.toInt() != 0 })
            assertEquals(BigInteger.valueOf(65537L).toInt(), buffer.int)
        } finally {
            directory.deleteRecursively()
        }
    }
}
