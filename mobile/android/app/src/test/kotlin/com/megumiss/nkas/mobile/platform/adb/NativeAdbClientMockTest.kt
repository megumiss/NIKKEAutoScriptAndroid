package com.megumiss.nkas.mobile.platform.adb

import java.io.ByteArrayOutputStream
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.IOException
import java.net.ServerSocket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeAdbClientMockTest {
    @Test(timeout = 10_000)
    fun interruptCancelsHandshakeWithoutWaitingForSocketTimeout() {
        val directory = Files.createTempDirectory("nkas-adb-cancel").toFile()
        val handshake = CountDownLatch(1)
        val failure = AtomicReference<Throwable>()
        val clientFailure = AtomicReference<Throwable>()
        ServerSocket(0).use { server ->
            server.soTimeout = 5_000
            val serverThread = thread(isDaemon = true) {
                try {
                    server.accept().use { socket ->
                        socket.soTimeout = 5_000
                        val input = DataInputStream(socket.getInputStream())
                        assertEquals(CNXN, AdbProtocol.decode(input).command)
                        handshake.countDown()
                        assertEquals(-1, input.read())
                    }
                } catch (error: Throwable) { failure.set(error) }
            }
            val client = NativeAdbClient(AdbEndpoint("127.0.0.1", server.localPort), AdbKeyStore(directory), 30_000)
            val clientThread = thread(isDaemon = true) {
                try { client.connect() } catch (error: Throwable) { clientFailure.set(error) }
            }
            try {
                assertTrue("client did not send CNXN", handshake.await(5, TimeUnit.SECONDS))
                client.interrupt()
                clientThread.join(2_000)
                assertFalse("cancel waited for the 30s handshake timeout", clientThread.isAlive)
                assertTrue(clientFailure.get() is IOException)
                assertFalse(client.isConnected())
                serverThread.join(2_000)
                assertFalse(serverThread.isAlive)
                failure.get()?.let { throw AssertionError("mock ADB server failed", it) }
            } finally {
                client.interrupt()
                client.close()
                directory.deleteRecursively()
            }
        }
    }

    @Test
    fun shellReadsRemoteOutput() = withClient(
        clientAction = { it.shell("getprop ro.product.model") },
        serverAction = { input, output ->
            val open = AdbProtocol.decode(input)
            assertEquals(OPEN, open.command)
            send(output, OKAY, REMOTE_ID, open.arg0)
            send(output, WRTE, REMOTE_ID, open.arg0, "model\n".toByteArray())
            assertEquals(OKAY, AdbProtocol.decode(input).command)
            send(output, CLSE, REMOTE_ID, open.arg0)
            assertEquals(CLSE, AdbProtocol.decode(input).command)
        },
    ).let { result ->
        assertEquals("model\n", result)
    }

    @Test
    fun pushUsesSyncSendDataDoneSequence() = withClient(
        peerMaxPayload = 4096,
        clientAction = { it.push(ByteArray(70_000) { 65 }, "/data/mock.txt") },
        serverAction = { input, output ->
            val open = AdbProtocol.decode(input)
            assertEquals(OPEN, open.command)
            send(output, OKAY, REMOTE_ID, open.arg0)
            val sync = ByteArrayOutputStream()
            while (true) {
                val message = AdbProtocol.decode(input)
                assertEquals(WRTE, message.command)
                assertTrue(message.payload.size <= 4096)
                sync.write(message.payload)
                send(output, OKAY, REMOTE_ID, open.arg0)
                val bytes = sync.toByteArray()
                if (bytes.size >= 8 && bytes.copyOfRange(bytes.size - 8, bytes.size - 4).contentEquals("DONE".toByteArray())) break
            }
            val bytes = sync.toByteArray()
            assertEquals("SEND", bytes.copyOfRange(0, 4).toString(Charsets.US_ASCII))
            val reader = DataInputStream(ByteArrayInputStream(bytes))
            reader.skipBytes(4)
            val pathSize = Integer.reverseBytes(reader.readInt())
            val path = ByteArray(pathSize).also(reader::readFully)
            assertEquals("/data/mock.txt,420", path.toString(Charsets.UTF_8))
            val payload = ByteArrayOutputStream()
            while (true) {
                val id = ByteArray(4).also(reader::readFully).toString(Charsets.US_ASCII)
                val size = Integer.reverseBytes(reader.readInt())
                if (id == "DONE") break
                assertEquals("DATA", id)
                payload.write(ByteArray(size).also(reader::readFully))
            }
            assertArrayEquals(ByteArray(70_000) { 65 }, payload.toByteArray())
            send(output, WRTE, REMOTE_ID, open.arg0, syncOkay())
            assertEquals(OKAY, AdbProtocol.decode(input).command)
            assertEquals(CLSE, AdbProtocol.decode(input).command)
        },
    ).also { result ->
        assertEquals(Unit, result)
    }

    @Test
    fun pullReadsSyncDataAndDone() = withClient(
        clientAction = { it.pull("/data/mock.txt") },
        serverAction = { input, output ->
            val open = AdbProtocol.decode(input)
            assertEquals(OPEN, open.command)
            send(output, OKAY, REMOTE_ID, open.arg0)
            val request = ByteArrayOutputStream()
            while (request.size() < 8 + "/data/mock.txt".length) {
                val message = AdbProtocol.decode(input)
                assertEquals(WRTE, message.command)
                request.write(message.payload)
                send(output, OKAY, REMOTE_ID, open.arg0)
            }
            assertEquals("RECV", request.toByteArray().copyOfRange(0, 4).toString(Charsets.US_ASCII))
            send(output, WRTE, REMOTE_ID, open.arg0, syncData("payload".toByteArray()))
            assertEquals(OKAY, AdbProtocol.decode(input).command)
            send(output, WRTE, REMOTE_ID, open.arg0, syncDone())
            assertEquals(OKAY, AdbProtocol.decode(input).command)
            assertEquals(CLSE, AdbProtocol.decode(input).command)
        },
    ).let { result ->
        assertArrayEquals("payload".toByteArray(), result)
    }

    @Test(timeout = 10_000)
    fun transportEofClearsConnectedStateAndUnblocksReads() = withClient(
        clientAction = { client ->
            val stream = client.openStream("shell:wait")
            assertEquals(-1, stream.inputStream.read())
            assertEquals(-1, stream.inputStream.read())
            assertFalse(client.isConnected())
        },
        serverAction = { input, output ->
            val open = AdbProtocol.decode(input)
            send(output, OKAY, REMOTE_ID, open.arg0)
        },
    )

    private fun <T> withClient(
        peerMaxPayload: Int = 256 * 1024,
        clientAction: (NativeAdbClient) -> T,
        serverAction: (DataInputStream, java.io.OutputStream) -> Unit,
    ): T {
        val server = ServerSocket(0)
        val failure = arrayOfNulls<Throwable>(1)
        val serverThread = thread(start = true, isDaemon = true) {
            try {
                server.accept().use { socket ->
                    socket.soTimeout = 5_000
                    val input = DataInputStream(socket.getInputStream())
                    val output = socket.getOutputStream()
                    val connect = AdbProtocol.decode(input)
                    assertEquals(CNXN, connect.command)
                    send(output, CNXN, 0x01000000, peerMaxPayload, "device::mock\u0000".toByteArray())
                    serverAction(input, output)
                }
            } catch (error: Throwable) {
                failure[0] = error
            }
        }
        val directory = Files.createTempDirectory("nkas-adb-mock").toFile()
        try {
            val result = NativeAdbClient(
                AdbEndpoint.parse("127.0.0.1:${server.localPort}"),
                AdbKeyStore(directory),
            ).use { client ->
                client.connect()
                clientAction(client)
            }
            serverThread.join(5_000)
            assertFalse("mock ADB server did not finish", serverThread.isAlive)
            failure[0]?.let { throw AssertionError("mock ADB server failed", it) }
            return result
        } finally {
            server.close()
            directory.deleteRecursively()
        }
    }

    private fun send(output: java.io.OutputStream, command: Int, arg0: Int, arg1: Int, payload: ByteArray = ByteArray(0)) {
        output.write(AdbProtocol.encode(command, arg0, arg1, payload))
        output.flush()
    }

    private fun syncOkay() = "OKAY".toByteArray() + ByteArray(4)

    private fun syncData(data: ByteArray): ByteArray =
        "DATA".toByteArray() + ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(data.size).array() + data

    private fun syncDone() = "DONE".toByteArray() + ByteArray(4)

    private companion object {
        const val CNXN = 0x4e584e43
        const val OPEN = 0x4e45504f
        const val OKAY = 0x59414b4f
        const val CLSE = 0x45534c43
        const val WRTE = 0x45545257
        const val REMOTE_ID = 42
    }
}
