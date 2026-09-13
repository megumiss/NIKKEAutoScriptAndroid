package com.megumiss.nkas.mobile.platform.adb

import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo
import org.bouncycastle.cert.X509v3CertificateBuilder
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import org.conscrypt.Conscrypt
import java.io.ByteArrayInputStream
import java.math.BigInteger
import java.net.Socket
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Security
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.Date
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509TrustManager

/** Creates the mutual-TLS identity expected by Android 11+ adbd. */
internal object AdbTlsIdentity {
    fun upgrade(socket: Socket, host: String, port: Int, keyPair: AdbKeyPair): SSLSocket {
        val context = createContext(keyPair)
        val sslSocket = context.socketFactory.createSocket(socket, host, port, true) as SSLSocket
        sslSocket.enabledProtocols = arrayOf("TLSv1.3")
        sslSocket.startHandshake()
        return sslSocket
    }

    private fun createContext(keyPair: AdbKeyPair): SSLContext {
        val conscrypt = Conscrypt.newProviderBuilder().build()
        if (Security.getProvider(conscrypt.name) == null) Security.insertProviderAt(conscrypt, 1)
        val bc = BouncyCastleProvider()
        if (Security.getProvider(bc.name) == null) Security.addProvider(bc)

        val certificate = createCertificate(keyPair.privateKey, keyPair.publicKey)
        val keyManagers = arrayOf(AdbKeyManager(keyPair.privateKey, certificate))
        val trustManagers = arrayOf<TrustManager>(TrustAllManager)
        return SSLContext.getInstance("TLSv1.3", conscrypt).apply {
            init(keyManagers, trustManagers, SecureRandom())
        }
    }

    private fun createCertificate(privateKey: PrivateKey, publicKey: java.security.PublicKey): X509Certificate {
        val now = System.currentTimeMillis()
        val signer = JcaContentSignerBuilder("SHA256withRSA")
            .setProvider(BouncyCastleProvider.PROVIDER_NAME)
            .build(privateKey)
        val subject = X500Name("CN=00")
        val builder = X509v3CertificateBuilder(
            subject,
            BigInteger.ONE,
            Date(now - 24 * 60 * 60 * 1000L),
            Date(now + 3650L * 24 * 60 * 60 * 1000L),
            subject,
            SubjectPublicKeyInfo.getInstance(publicKey.encoded),
        )
        val encoded = builder.build(signer).encoded
        return CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(encoded)) as X509Certificate
    }

    private object TrustAllManager : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }

    private class AdbKeyManager(
        private val privateKey: PrivateKey,
        private val certificate: X509Certificate,
    ) : X509ExtendedKeyManager() {
        private val alias = "adbkey"

        override fun chooseClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out java.security.Principal>?,
            socket: Socket?,
        ): String = alias

        override fun chooseEngineClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out java.security.Principal>?,
            engine: SSLEngine?,
        ): String = alias

        override fun getCertificateChain(alias: String?): Array<X509Certificate>? =
            if (alias == this.alias) arrayOf(certificate) else null

        override fun getPrivateKey(alias: String?): PrivateKey? =
            if (alias == this.alias) privateKey else null

        override fun getClientAliases(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
        ): Array<String> = arrayOf(alias)

        override fun getServerAliases(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
        ): Array<String>? = null

        override fun chooseServerAlias(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
            socket: Socket?,
        ): String? = null

        override fun chooseEngineServerAlias(
            keyType: String?,
            issuers: Array<out java.security.Principal>?,
            engine: SSLEngine?,
        ): String? = null
    }
}
