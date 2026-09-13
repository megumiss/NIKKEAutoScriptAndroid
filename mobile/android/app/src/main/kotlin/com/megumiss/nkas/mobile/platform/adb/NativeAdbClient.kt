package com.megumiss.nkas.mobile.platform.adb

import android.util.Log
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.DataInputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Minimal ordinary TCP ADB client used by the native scrcpy integration. */
class NativeAdbClient(
    private val endpoint: AdbEndpoint,
    private val keyStore: AdbKeyStore,
    private val connectTimeoutMs: Int = 10_000,
) : Closeable {
    private val nextLocalId = AtomicInteger(1)
    private val streams = ConcurrentHashMap<Int, AdbStream>()
    private val writeLock = Any()
    private var maxPayload = AdbProtocol.MAX_PAYLOAD
    private var socket: Socket? = null
    private var input: DataInputStream? = null
    private var output: OutputStream? = null
    private var reader: Thread? = null
    @Volatile private var closed = true
    private var keyPair: AdbKeyPair? = null

    @Synchronized
    @Throws(IOException::class)
    fun connect() {
        if (!closed) return
        val newSocket = Socket()
        socket = newSocket
        closed = false
        try {
            newSocket.connect(InetSocketAddress(endpoint.host, endpoint.port), connectTimeoutMs)
            newSocket.soTimeout = connectTimeoutMs
            input = DataInputStream(newSocket.getInputStream())
            output = newSocket.getOutputStream()
            keyPair = keyStore.loadOrCreate()
            handshake()
            newSocket.soTimeout = 0
            reader = Thread(::readLoop, "nkas-adb-reader").apply { isDaemon = true; start() }
        } catch (error: Exception) {
            close()
            if (error is IOException) throw error
            throw IOException("ADB handshake failed", error)
        }
    }

    fun isConnected(): Boolean = !closed && socket?.isConnected == true && !socket!!.isClosed

    @Throws(IOException::class)
    fun shell(command: String): String = openStream("shell:$command").use {
        it.inputStream.readBytes().toString(Charsets.UTF_8)
    }

    @Throws(IOException::class)
    fun openStream(service: String): AdbStream {
        checkConnected()
        val localId = nextLocalId.getAndIncrement()
        val stream = AdbStream(localId, maxPayload) { command, arg0, arg1, data -> send(command, arg0, arg1, data) }
        streams[localId] = stream
        try {
            send(OPEN, localId, 0, (service + "\u0000").toByteArray(Charsets.UTF_8))
            stream.awaitOpen(15_000)
            return stream
        } catch (error: Exception) {
            streams.remove(localId)
            stream.close()
            if (error is IOException) throw error
            throw IOException("ADB stream open failed", error)
        }
    }

    @Throws(IOException::class)
    fun push(data: ByteArray, remotePath: String, unixMode: Int = 420) {
        ByteArrayInputStream(data).use { input ->
            openStream("sync:").use { stream ->
                val out = stream.outputStream
                out.writeAscii("SEND")
                out.writeIntLe("$remotePath,$unixMode".toByteArray(Charsets.UTF_8).size)
                out.write("$remotePath,$unixMode".toByteArray(Charsets.UTF_8))
                val chunk = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(chunk)
                    if (count <= 0) break
                    out.writeAscii("DATA")
                    out.writeIntLe(count)
                    out.write(chunk, 0, count)
                }
                out.writeAscii("DONE")
                out.writeIntLe((System.currentTimeMillis() / 1000).toInt())
                out.flush()
                expectSyncOkay(stream.inputStream, "push")
            }
        }
    }

    @Throws(IOException::class)
    fun pull(remotePath: String): ByteArray {
        val output = ByteArrayOutputStream()
        openStream("sync:").use { stream ->
            val out = stream.outputStream
            out.writeAscii("RECV")
            val path = remotePath.toByteArray(Charsets.UTF_8)
            out.writeIntLe(path.size)
            out.write(path)
            out.flush()
            val input = stream.inputStream
            while (true) {
                val id = input.readAscii(4)
                val length = input.readIntLe()
                when (id) {
                    "DATA" -> {
                        if (length !in 0..MAX_SYNC_PAYLOAD) throw IOException("ADB pull returned invalid chunk length $length")
                        output.write(ByteArray(length).also { input.readFully(it) })
                    }
                    "DONE" -> return output.toByteArray()
                    "FAIL" -> throw IOException("ADB pull failed: ${input.readUtf8(length)}")
                    else -> throw IOException("ADB pull returned unexpected sync id $id")
                }
            }
        }
    }

    @Synchronized
    override fun close() {
        if (closed) return
        closed = true
        streams.values.forEach { it.forceClose() }
        streams.clear()
        runCatching { socket?.close() }
        socket = null
        input = null
        output = null
        reader?.interrupt()
        reader = null
    }

    @Throws(IOException::class)
    private fun handshake() {
        send(CNXN, ADB_VERSION, MAX_PAYLOAD, "host::\u0000".toByteArray(Charsets.UTF_8))
        var signatureSent = false
        while (true) {
            val message = receive()
            when (message.command) {
                CNXN -> {
                    if (message.arg1 <= 0) throw IOException("ADB returned an invalid maximum payload")
                    maxPayload = minOf(MAX_PAYLOAD, message.arg1)
                    return
                }
                STLS -> {
                    if (message.arg0 != STLS_VERSION) {
                        throw IOException("ADB returned unsupported STLS version ${message.arg0}")
                    }
                    send(STLS, STLS_VERSION, 0, ByteArray(0))
                    upgradeToTls()
                }
                AUTH -> {
                    when (message.arg0) {
                        AUTH_TOKEN -> {
                            val pair = keyPair ?: throw IOException("ADB key is not initialized")
                            if (!signatureSent) {
                                send(AUTH, AUTH_SIGNATURE, 0, pair.signToken(message.payload))
                                signatureSent = true
                            } else {
                                send(AUTH, AUTH_RSAPUBLICKEY, 0, pair.adbPublicKey)
                            }
                        }
                        else -> throw IOException("ADB returned unsupported AUTH type ${message.arg0}")
                    }
                }
                else -> throw IOException("ADB returned unexpected command ${commandName(message.command)}")
            }
        }
    }

    @Throws(IOException::class)
    private fun upgradeToTls() {
        val currentSocket = socket ?: throw IOException("ADB socket is not initialized")
        val pair = keyPair ?: throw IOException("ADB key is not initialized")
        try {
            val tlsSocket = AdbTlsIdentity.upgrade(currentSocket, endpoint.host, endpoint.port, pair)
            socket = tlsSocket
            input = DataInputStream(tlsSocket.inputStream)
            output = tlsSocket.outputStream
        } catch (error: Exception) {
            throw if (error is IOException) error else IOException("ADB TLS upgrade failed", error)
        }
    }

    private fun readLoop() {
        try {
            while (!closed) {
                when (val message = receive()) {
                    else -> when (message.command) {
                        OKAY -> streams[message.arg1]?.onOkay(message.arg0)
                        WRTE -> {
                            val stream = streams[message.arg1]
                            if (stream == null) send(CLSE, message.arg1, message.arg0, ByteArray(0))
                            else stream.onData(message.payload)
                        }
                        CLSE -> streams.remove(message.arg1)?.let {
                            it.forceClose()
                            send(CLSE, message.arg1, message.arg0, ByteArray(0))
                        }
                        else -> Log.w(TAG, "Ignoring ADB command ${commandName(message.command)}")
                    }
                }
            }
        } catch (_: IOException) {
            // Closing the transport below wakes every waiting stream.
        } finally {
            close()
        }
    }

    @Throws(IOException::class)
    private fun send(command: Int, arg0: Int, arg1: Int, payload: ByteArray) {
        synchronized(writeLock) {
            checkConnected()
            val data = output ?: throw IOException("ADB output is closed")
            data.write(AdbProtocol.encode(command, arg0, arg1, payload))
            data.flush()
        }
    }

    @Throws(IOException::class)
    private fun receive(): AdbMessage {
        val data = input ?: throw IOException("ADB input is closed")
        return AdbProtocol.decode(data)
    }

    private fun checkConnected() {
        if (closed) throw IOException("ADB client is not connected")
    }

    companion object {
        private const val TAG = "NkasNativeAdb"
        private const val ADB_VERSION = 0x01000000
        private const val MAX_PAYLOAD = AdbProtocol.MAX_PAYLOAD
        private const val MAX_SYNC_PAYLOAD = 16 * 1024 * 1024
        private const val CNXN = 0x4e584e43
        private const val STLS = 0x534c5453
        private const val AUTH = 0x48545541
        private const val OPEN = 0x4e45504f
        private const val OKAY = 0x59414b4f
        private const val CLSE = 0x45534c43
        private const val WRTE = 0x45545257
        private const val AUTH_TOKEN = 1
        private const val AUTH_SIGNATURE = 2
        private const val AUTH_RSAPUBLICKEY = 3
        private const val STLS_VERSION = 0x01000000

        private fun commandName(command: Int): String = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(command).array().toString(Charsets.US_ASCII)
    }
}

class AdbStream internal constructor(
    private val localId: Int,
    private val maxPayload: Int = 64 * 1024,
    private val writeTimeoutMs: Long = 15_000,
    private val sender: (Int, Int, Int, ByteArray) -> Unit,
) : Closeable {
    private val opened = CountDownLatch(1)
    private var openOkay = false
    private val queue = ArrayBlockingQueue<Any>(8)
    private val writeState = Object()
    private val writeLock = Any()
    private var writeReady = false
    @Volatile private var remoteId = 0
    @Volatile private var closed = false
    val inputStream: InputStream = StreamInput()
    val outputStream: OutputStream = StreamOutput()

    internal fun onOkay(remote: Int) {
        synchronized(writeState) {
            if (closed || remote == 0) return
            if (remoteId != 0 && remoteId != remote) throw IOException("ADB stream ID changed")
            remoteId = remote
            writeReady = true
            if (!openOkay) {
                openOkay = true
                opened.countDown()
            }
            writeState.notifyAll()
        }
    }

    internal fun onData(data: ByteArray) {
        if (!closed && !queue.offer(data)) throw IOException("ADB peer exceeded the receive window")
    }

    internal fun forceClose() {
        synchronized(writeState) {
            closed = true
            queue.offer(END)
            opened.countDown()
            writeState.notifyAll()
        }
    }

    fun awaitOpen(timeoutMs: Long) {
        if (!opened.await(timeoutMs, TimeUnit.MILLISECONDS)) throw IOException("ADB stream open timed out")
        if (!openOkay) throw IOException("ADB stream rejected by device")
    }

    override fun close() {
        if (closed) return
        forceClose()
        if (remoteId != 0) runCatching { sender(CLSE, localId, remoteId, ByteArray(0)) }
    }

    private inner class StreamInput : InputStream() {
        private var chunk = ByteArray(0)
        private var offset = 0
        private var eof = false
        override fun read(buffer: ByteArray, off: Int, len: Int): Int {
            if (off < 0 || len < 0 || len > buffer.size - off) throw IndexOutOfBoundsException()
            if (len == 0) return 0
            if (eof) return -1
            while (offset >= chunk.size) {
                if (closed && queue.isEmpty()) { eof = true; return -1 }
                val next = queue.take()
                if (next === END) { eof = true; return -1 }
                chunk = next as ByteArray
                offset = 0
                if (chunk.isEmpty() && !closed) sender(OKAY, localId, remoteId, ByteArray(0))
            }
            val count = minOf(len, chunk.size - offset)
            chunk.copyInto(buffer, off, offset, offset + count)
            offset += count
            // Acknowledge after consumption so a slow decoder applies backpressure.
            if (offset == chunk.size && !closed) sender(OKAY, localId, remoteId, ByteArray(0))
            return count
        }
        override fun read(): Int = ByteArray(1).let { if (read(it, 0, 1) < 0) -1 else it[0].toInt() and 0xff }
    }

    private inner class StreamOutput : OutputStream() {
        override fun write(value: Int) = write(byteArrayOf(value.toByte()))
        override fun write(buffer: ByteArray, off: Int, len: Int) {
            if (off < 0 || len < 0 || len > buffer.size - off) throw IndexOutOfBoundsException()
            synchronized(writeLock) {
                if (closed) throw IOException("ADB stream is closed")
                var position = off
                var remaining = len
                while (remaining > 0) {
                    awaitWriteReady()
                    synchronized(writeState) { writeReady = false }
                    val count = minOf(maxPayload, remaining)
                    sender(WRTE, localId, remoteId, buffer.copyOfRange(position, position + count))
                    awaitWriteReady()
                    position += count
                    remaining -= count
                }
            }
        }
    }

    private fun awaitWriteReady() {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(writeTimeoutMs)
        synchronized(writeState) {
            while (!writeReady && !closed) {
                val remaining = deadline - System.nanoTime()
                if (remaining <= 0) throw IOException("ADB stream write timed out")
                TimeUnit.NANOSECONDS.timedWait(writeState, remaining)
            }
            if (closed) throw IOException("ADB stream is closed")
        }
    }

    private companion object {
        const val END = "adb-stream-end"
        const val CLSE = 0x45534c43
        const val WRTE = 0x45545257
        const val OKAY = 0x59414b4f
    }
}

private fun OutputStream.writeAscii(value: String) = write(value.toByteArray(Charsets.US_ASCII))
private fun OutputStream.writeIntLe(value: Int) {
    write(value and 0xff)
    write(value shr 8 and 0xff)
    write(value shr 16 and 0xff)
    write(value shr 24 and 0xff)
}

private fun InputStream.readAscii(length: Int): String = ByteArray(length).also { readFully(it) }.toString(Charsets.US_ASCII)
private fun InputStream.readIntLe(): Int {
    val bytes = ByteArray(4).also { readFully(it) }
    return ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).int
}
private fun InputStream.readUtf8(length: Int): String {
    if (length !in 0..16 * 1024 * 1024) throw IOException("Invalid ADB sync message length $length")
    return ByteArray(length).also { readFully(it) }.toString(Charsets.UTF_8)
}
private fun InputStream.readFully(buffer: ByteArray) {
    var offset = 0
    while (offset < buffer.size) {
        val count = read(buffer, offset, buffer.size - offset)
        if (count < 0) throw EOFException("Unexpected EOF while reading ADB data")
        if (count == 0) throw IOException("ADB stream returned no data")
        offset += count
    }
}

private fun expectSyncOkay(input: InputStream, operation: String) {
    val id = input.readAscii(4)
    val length = input.readIntLe()
    if (id != "OKAY") throw IOException("ADB $operation failed: ${if (length > 0) input.readUtf8(length) else id}")
    if (length > 0) input.readFully(ByteArray(length))
}
