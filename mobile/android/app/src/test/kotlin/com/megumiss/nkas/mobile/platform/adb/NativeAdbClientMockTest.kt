package com.megumiss.nkas.mobile.platform.adb

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.net.ServerSocket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import kotlin.concurrent.thread
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class NativeAdbClientMockTest {
    @Test
    fun shellReadsRemoteOutput() = withClient(
        clientAction = { it.shell("getprop ro.product.model") },
        serverAction = { input, output ->
            val open = AdbProtocol.decode(input)
            assertEquals(OPEN, open.command)
            send(output, OKAY, REMOTE_ID, open.arg0)
            send(output, WRTE, REMOTE_ID, open.arg0, "model\n".toByteArray())
            send(output, CLSE, REMOTE_ID, open.arg0)
            input.readMessageIgnoringClientAck()
        },
    ).let { result ->
        assertEquals("model\n", result)
    }

    @Test
    fun pushUsesSyncSendDataDoneSequence() = withClient(
        clientAction = { it.push("payload".toByteArray(), "/data/mock.txt") },
        serverAction = { input, output ->
            val open = AdbProtocol.decode(input)
            assertEquals(OPEN, open.command)
            send(output, OKAY, REMOTE_ID, open.arg0)
            val sync = ByteArrayOutputStream()
            while (true) {
                val message = AdbProtocol.decode(input)
                sync.write(message.payload)
                if (sync.toByteArray().containsAscii("DONE")) break
            }
            val bytes = sync.toByteArray()
            assertEquals("SEND", bytes.copyOfRange(0, 4).toString(Charsets.US_ASCII))
            send(output, WRTE, REMOTE_ID, open.arg0, syncOkay())
            input.readMessageIgnoringClientAck()
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
            val request = AdbProtocol.decode(input)
            assertEquals("RECV", request.payload.copyOfRange(0, 4).toString(Charsets.US_ASCII))
            send(output, WRTE, REMOTE_ID, open.arg0, syncData("payload".toByteArray()))
            send(output, WRTE, REMOTE_ID, open.arg0, syncDone())
            var acknowledgements = 0
            while (acknowledgements < 2) {
                if (input.readMessageIgnoringClientAck()?.command == OKAY) acknowledgements++
            }
        },
    ).let { result ->
        assertArrayEquals("payload".toByteArray(), result)
    }

    private fun <T> withClient(
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
                    send(output, CNXN, 0, 256 * 1024, "device::mock\u0000".toByteArray())
                    serverAction(input, output)
                }
            } catch (error: Throwable) {
                failure[0] = error
            }
        }
        val directory = Files.createTempDirectory("nkas-adb-mock").toFile()
        try {
            val client = NativeAdbClient(
                AdbEndpoint("127.0.0.1", server.localPort),
                AdbKeyStore(directory),
            )
            client.connect()
            val result = clientAction(client)
            client.close()
            serverThread.join(5_000)
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

    private fun ByteArray.containsAscii(value: String): Boolean =
        indexOfSubsequence(value.toByteArray(Charsets.US_ASCII)) >= 0

    private fun ByteArray.indexOfSubsequence(needle: ByteArray): Int =
        (0..size - needle.size).firstOrNull { start -> needle.indices.all { this[start + it] == needle[it] } } ?: -1

    private fun DataInputStream.readMessageIgnoringClientAck() =
        runCatching { AdbProtocol.decode(this) }.getOrNull()

    private companion object {
        const val CNXN = 0x4e584e43
        const val OPEN = 0x4e45504f
        const val OKAY = 0x59414b4f
        const val CLSE = 0x45534c43
        const val WRTE = 0x45545257
        const val REMOTE_ID = 42
    }
}
