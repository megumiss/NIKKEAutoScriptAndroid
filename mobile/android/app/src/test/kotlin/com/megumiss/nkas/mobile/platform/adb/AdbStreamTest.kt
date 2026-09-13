package com.megumiss.nkas.mobile.platform.adb

import java.io.IOException
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AdbStreamTest {
    @Test(timeout = 5_000)
    fun eachWriteWaitsForItsOwnAcknowledgement() {
        val packets = LinkedBlockingQueue<ByteArray>()
        val stream = AdbStream(7, 4096, 1000) { command, local, remote, payload ->
            assertEquals(0x45545257, command)
            assertEquals(7, local)
            assertEquals(42, remote)
            packets.add(payload)
        }
        val executor = Executors.newSingleThreadExecutor()
        try {
            stream.onOkay(42)
            val data = ByteArray(5000) { it.toByte() }
            val write = executor.submit { stream.outputStream.write(data) }
            assertArrayEquals(data.copyOfRange(0, 4096), packets.poll(1, TimeUnit.SECONDS))
            assertNull(packets.poll(100, TimeUnit.MILLISECONDS))
            stream.onOkay(42)
            assertArrayEquals(data.copyOfRange(4096, 5000), packets.poll(1, TimeUnit.SECONDS))
            stream.onOkay(42)
            write.get(1, TimeUnit.SECONDS)
        } finally {
            stream.forceClose()
            executor.shutdownNow()
        }
    }

    @Test(timeout = 5_000)
    fun receiveWindowOpensOnlyAfterThePayloadIsConsumed() {
        val commands = mutableListOf<Int>()
        val stream = AdbStream(7) { command, _, _, _ -> commands.add(command) }
        stream.onOkay(42)
        stream.onData(byteArrayOf(1, 2))
        assertTrue(commands.isEmpty())
        assertEquals(1, stream.inputStream.read())
        assertTrue(commands.isEmpty())
        assertEquals(2, stream.inputStream.read())
        assertEquals(listOf(0x59414b4f), commands)
        stream.forceClose()
        assertEquals(-1, stream.inputStream.read())
        assertEquals(-1, stream.inputStream.read())
    }

    @Test(timeout = 5_000)
    fun closingUnblocksAWriterWaitingForAnAcknowledgement() {
        val packets = LinkedBlockingQueue<Int>()
        val stream = AdbStream(7) { command, _, _, _ -> packets.add(command) }
        val executor = Executors.newSingleThreadExecutor()
        try {
            stream.onOkay(42)
            val write = executor.submit { stream.outputStream.write(1) }
            assertEquals(0x45545257, packets.poll(1, TimeUnit.SECONDS))
            stream.forceClose()
            val error = assertThrows(ExecutionException::class.java) { write.get(1, TimeUnit.SECONDS) }
            assertTrue(error.cause is IOException)
        } finally {
            stream.forceClose()
            executor.shutdownNow()
        }
    }
}
