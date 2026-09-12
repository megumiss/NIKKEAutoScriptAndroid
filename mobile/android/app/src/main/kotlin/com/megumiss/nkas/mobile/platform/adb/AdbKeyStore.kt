package com.megumiss.nkas.mobile.platform.adb

import java.io.File
import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.interfaces.RSAPublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

data class AdbKeyPair(
    val privateKey: PrivateKey,
    val publicKey: PublicKey,
    val name: String,
) {
    val adbPublicKey: ByteArray by lazy { encodeAdbPublicKey(publicKey as RSAPublicKey, name) }
}

/** Stores the client identity in app-private storage for ordinary ADB AUTH. */
class AdbKeyStore(private val directory: File, private val keyName: String = "nkas-mobile") {
    fun loadOrCreate(): AdbKeyPair {
        val privateFile = File(directory, "adbkey.pk8")
        val publicFile = File(directory, "adbkey.pub.der")
        directory.mkdirs()
        val keyFactory = KeyFactory.getInstance("RSA")
        if (privateFile.isFile && publicFile.isFile) {
            val privateKey = keyFactory.generatePrivate(PKCS8EncodedKeySpec(privateFile.readBytes()))
            val publicKey = keyFactory.generatePublic(X509EncodedKeySpec(publicFile.readBytes()))
            return AdbKeyPair(privateKey, publicKey, keyName)
        }

        val generated = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        privateFile.writeBytes(generated.private.encoded)
        publicFile.writeBytes(generated.public.encoded)
        privateFile.setReadable(false, false)
        privateFile.setReadable(true, true)
        publicFile.setReadable(true, true)
        return AdbKeyPair(generated.private, generated.public, keyName)
    }
}

internal fun encodeAdbPublicKey(publicKey: RSAPublicKey, name: String): ByteArray {
    val words = 64
    val modulusBytes = 256
    val two32 = BigInteger.ONE.shiftLeft(32)
    val mask32 = two32.subtract(BigInteger.ONE)
    val modulus = publicKey.modulus
    val modulusLE = littleEndianWords(padBigEndian(modulus, modulusBytes), words)
    val r = BigInteger.ONE.shiftLeft(modulusBytes * 8)
    val rrLE = littleEndianWords(padBigEndian(r.multiply(r).mod(modulus), modulusBytes), words)
    val n0inv = modulus.and(mask32).modInverse(two32).negate().mod(two32).toInt()
    val body = ByteBuffer.allocate(4 + 4 + modulusBytes + modulusBytes + 4)
        .order(ByteOrder.LITTLE_ENDIAN)
        .putInt(words)
        .putInt(n0inv)
        .put(modulusLE)
        .put(rrLE)
        .putInt(publicKey.publicExponent.toInt())
        .array()
    return (Base64.getEncoder().encodeToString(body) + " $name\u0000")
        .toByteArray(Charsets.UTF_8)
}

private fun padBigEndian(value: BigInteger, size: Int): ByteArray {
    val raw = value.toByteArray().let { if (it.firstOrNull() == 0.toByte()) it.copyOfRange(1, it.size) else it }
    require(raw.size <= size) { "RSA value is too large" }
    return ByteArray(size).also { raw.copyInto(it, size - raw.size) }
}

private fun littleEndianWords(bigEndian: ByteArray, words: Int): ByteArray {
    val output = ByteArray(words * 4)
    for (word in 0 until words) {
        val offset = bigEndian.size - (word + 1) * 4
        for (byte in 0 until 4) output[word * 4 + byte] = bigEndian[offset + 3 - byte]
    }
    return output
}
