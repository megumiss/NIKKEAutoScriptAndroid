package com.megumiss.nkas.mobile.platform

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import android.view.Surface
import com.megumiss.nkas.mobile.platform.adb.AdbEndpoint
import com.megumiss.nkas.mobile.platform.adb.NativeAdbManager
import com.megumiss.nkas.mobile.platform.scrcpy.NativeScrcpyLauncher
import com.megumiss.nkas.mobile.platform.scrcpy.NativeScrcpySession
import com.megumiss.nkas.mobile.platform.scrcpy.ScrcpyServerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

class NativeControlSession(
    context: Context,
    private val textures: TextureRegistry,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val queue = Executors.newSingleThreadExecutor { Thread(it, "nkas-native-session") }
    private val inputQueue = Executors.newSingleThreadExecutor { Thread(it, "nkas-native-input") }
    private val generation = AtomicLong()
    private val settings = NativeControlSettings(app)
    private val adb = NativeAdbManager(app)
    private val tsnet = NativeTsnet(app, settings)
    private val network = app.getSystemService(ConnectivityManager::class.java)
    @Volatile private var desired: Request? = null
    @Volatile private var session: NativeScrcpySession? = null
    @Volatile private var disposed = false
    @Volatile private var foreground = true
    @Volatile private var networkAvailable = network?.activeNetwork != null
    private var networkKey: String? = null
    private var texture: TextureRegistry.SurfaceTextureEntry? = null
    private var activeRequest: Request? = null
    @Volatile private var activeForwardId: String? = null
    private var startupTimeout: Runnable? = null
    private val retries = AtomicInteger()

    private data class Request(
        val id: String, val endpoint: String, val mode: String,
        val tailscale: Boolean, val options: ScrcpyServerOptions,
    )

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            // VPN 活动时会频繁刷新路由、DNS 和地址（onLinkPropertiesChanged），
            // 不能当作网络切换处理；只有默认网络本身更换才重建控制会话
            main.post { networkChanged("$network", true) }
        }
        override fun onLost(network: Network) {
            main.post { if (this@NativeControlSession.network?.activeNetwork == null) networkChanged(null, false) }
        }
    }

    init { network?.registerDefaultNetworkCallback(networkCallback) }

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method !in METHODS) return false
        if (disposed) { result.error("native_closed", "原生会话已关闭", null); return true }
        try {
            when (call.method) {
                "getNativeControlSettings" -> result.success(settings.snapshot())
                "saveNativeControlSettings", "tsnetConfigure", "tsnetClearState" -> {
                    desired = null
                    val token = interrupt("配置变更")
                    execute(call.method, result) {
                        ensureCurrent(token)
                        stop()
                        when (call.method) {
                            "saveNativeControlSettings" -> settings.save(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                            "tsnetConfigure" -> { tsnet.configure(call.argument<String>("authKey").orEmpty()); tsnetStatus() }
                            else -> { tsnet.clearState(); tsnetStatus() }
                        }
                    }
                }
                "tsnetStatus" -> execute(call.method, result) { tsnet.status() }
                "tsnetConnect" -> execute(call.method, result) { tsnet.connect(); tsnetStatus() }
                "tsnetStartForward" -> execute(call.method, result) {
                    val endpoint = AdbEndpoint.parse(call.argument<String>("endpoint").orEmpty())
                    startService()
                    try { tsnet.startForward(endpoint, call.argument<Int>("localPort") ?: 0).also { tsnetStatus() } }
                    catch (error: Exception) { stopServiceIfIdle(); throw error }
                }
                "tsnetStopForward" -> {
                    val id = call.argument<String>("id").orEmpty()
                    val token = if (id == activeForwardId) { desired = null; interrupt("停止视频转发") } else null
                    execute(call.method, result) {
                        if (token != null && isCurrent(token)) stop(closeTsnet = false)
                        tsnet.stopForward(id); stopServiceIfIdle(); tsnetStatus()
                    }
                }
                "tsnetStopAll", "tsnetClose", "nativeAdbClose", "nativeScrcpyStop" -> {
                    val requestId = call.argument<String>("requestId")
                    if (requestId != null && requestId != desired?.id) { result.success(true); return true }
                    desired = null
                    val token = interrupt("停止连接")
                    execute(call.method, result) {
                        if (isCurrent(token)) {
                            stop(closeTsnet = call.method != "tsnetStopAll")
                            if (call.method == "tsnetStopAll") {
                                tsnet.stopAll(); stopServiceIfIdle(); tsnetStatus()
                            }
                        }
                        true
                    }
                }
                "nativeAdbConnect" -> {
                    desired = null
                    val token = interrupt("新的 ADB 连接")
                    execute(call.method, result) {
                        ensureCurrent(token); stop(closeTsnet = false)
                        try {
                            val endpoint = AdbEndpoint.parse(call.argument<String>("endpoint").orEmpty())
                            val useTailscale = call.argument<Boolean>("useTailscale") == true
                            if (useTailscale) startService()
                            val route = if (useTailscale) route(endpoint) else endpoint.toString()
                            ensureCurrent(token)
                            adb.connect(route, isCancelled = { !isCurrent(token) })
                            ensureCurrent(token)
                            tsnetStatus()
                            mapOf("endpoint" to endpoint.toString())
                        } catch (error: Exception) { stop(closeTsnet = false); throw error }
                    }
                }
                "nativeAdbShell" -> execute(call.method, result) {
                    val command = call.argument<String>("command").orEmpty()
                    require(command.isNotBlank() && '\u0000' !in command) { "ADB 命令无效" }
                    adb.shell(command)
                }
                "nativeAdbPush" -> execute(call.method, result) {
                    val data = call.argument<ByteArray>("data") ?: throw IllegalArgumentException("缺少文件内容")
                    adb.push(data, call.argument<String>("remotePath").orEmpty(), call.argument<Int>("mode") ?: 420)
                    true
                }
                "nativeAdbPull" -> execute(call.method, result) { adb.pull(call.argument<String>("remotePath").orEmpty()) }
                "nativeScrcpyStart" -> {
                    val mode = call.argument<String>("mode") ?: settings.mode
                    require(mode in setOf("remote_adb", "local_virtual_display")) { "控制模式无效" }
                    val endpoint = call.argument<String>("endpoint")?.takeIf { it.isNotBlank() }
                        ?: if (mode == "local_virtual_display") SettingsStore.serial(app) else settings.endpoint
                    val parsed = AdbEndpoint.parse(endpoint)
                    require(mode != "local_virtual_display" || parsed.host in setOf("localhost", "127.0.0.1", "::1")) {
                        "本机虚拟屏幕需使用本机无线调试地址"
                    }
                    val options = ScrcpyServerOptions(video = call.argument<Boolean>("video") ?: true,
                        control = call.argument<Boolean>("control") ?: true, maxSize = call.argument<Int>("maxSize") ?: 0,
                        videoBitRate = call.argument<Int>("videoBitRate") ?: 0,
                        videoCodec = call.argument<String>("videoCodec") ?: "h264", newDisplay = mode == "local_virtual_display")
                    val token = interrupt("新的控制会话")
                    val request = Request(call.argument<String>("requestId") ?: token.toString(), endpoint, mode,
                        mode == "remote_adb" && (call.argument<Boolean>("useTailscale") ?: settings.tailscaleEnabled), options)
                    desired = request
                    retries.set(0)
                    execute(call.method, result) { start(request, token) }
                }
                else -> input(call, result)
            }
        } catch (error: Exception) { result.error(call.method, error.message, null) }
        return true
    }

    private fun start(request: Request, token: Long): Map<String, Any?> {
        ensureCurrent(token)
        stop(closeTsnet = false)
        ensureCurrent(token)
        check(foreground && (networkAvailable || request.mode == "local_virtual_display")) { "等待前台网络恢复" }
        activeRequest = request
        videoEvent(request, "connecting")
        val ready = AtomicBoolean(false)
        val videoWidth = AtomicInteger()
        val videoHeight = AtomicInteger()
        // Also covers an ADB metadata read that never finishes.
        val timeout = Runnable { if (isCurrent(token) && !ready.get()) fail(IOException("等待视频首帧超时"), token) }
        startupTimeout = timeout
        main.postDelayed(timeout, 90_000)
        var surface: Surface? = null
        try {
            startService()
            val endpoint = AdbEndpoint.parse(request.endpoint)
            val route = if (request.tailscale) route(endpoint) else endpoint.toString()
            tsnetStatus()
            ensureCurrent(token)
            if (request.mode == "local_virtual_display") importLocalIdentity(token)
            adb.connect(route, localIdentity = request.mode == "local_virtual_display", isCancelled = { !isCurrent(token) })
            ensureCurrent(token)
            val jar = app.assets.open("bin/scrcpy-server-v4.1").use { it.readBytes() }
            val running = NativeScrcpyLauncher(adb).start(jar, request.options)
            session = running
            ensureCurrent(token)
            if (request.options.video) {
                val output = onMain { textures.createSurfaceTexture() }
                texture = output
                surface = Surface(output.surfaceTexture())
                running.startVideo(surface, object : NativeScrcpySession.VideoListener {
                    override fun onSize(width: Int, height: Int) {
                        if (!isCurrent(token)) return
                        videoWidth.set(width); videoHeight.set(height)
                        main.post { if (isCurrent(token)) output.surfaceTexture().setDefaultBufferSize(width, height) }
                        videoEvent(request, "size", mapOf("width" to width, "height" to height))
                    }
                    override fun onFrame() {
                        if (isCurrent(token) && ready.compareAndSet(false, true)) {
                            retries.set(0)
                            main.removeCallbacks(timeout)
                            videoEvent(request, "started", mapOf("textureId" to output.id(), "width" to videoWidth.get(),
                                "height" to videoHeight.get(), "deviceName" to running.videoMetadata?.deviceName))
                        }
                    }
                    override fun onError(error: Throwable) = fail(error, token)
                    override fun onStopped() = fail(IOException("视频连接已断开"), token)
                })
            } else { ready.set(true); main.removeCallbacks(timeout) }
            running.startServerMonitor(object : NativeScrcpySession.ServerListener {
                override fun onLog(line: String) {
                    if (isCurrent(token)) emit(mapOf("type" to "scrcpyServer", "state" to "output",
                        "requestId" to request.id, "message" to line.take(2000)))
                }
                override fun onExit(error: Throwable?) = fail(error ?: IOException("scrcpy 服务已退出"), token)
            })
            ensureCurrent(token)
            return mapOf("scid" to running.scid, "requestId" to request.id, "command" to running.command,
                "video" to request.options.video, "control" to request.options.control,
                "textureId" to texture?.id(), "deviceName" to running.videoMetadata?.deviceName,
                "codecId" to running.videoMetadata?.codecId)
        } catch (error: Exception) {
            if (session == null) surface?.release()
            stop()
            if (isCurrent(token)) videoEvent(request, "failed", mapOf("error" to error.message))
            throw error
        }
    }

    private fun input(call: MethodCall, result: MethodChannel.Result) {
        val token = generation.get()
        val requestId = call.argument<String>("requestId")
        val writer = session?.controlWriter
        if (writer == null || (requestId != null && requestId != desired?.id)) {
            result.error("native_control", "控制会话未连接", null); return
        }
        inputQueue.execute {
            try {
                ensureCurrent(token)
                when (call.method) {
                    "nativeScrcpyBack" -> writer.pressBack(call.argument<Int>("action") ?: 0)
                    "nativeScrcpyText" -> writer.injectText(call.argument<String>("text").orEmpty())
                    "nativeScrcpyKeycode" -> writer.injectKeycode(call.argument<Int>("action") ?: 0,
                        call.argument<Int>("keycode") ?: 0, call.argument<Int>("repeat") ?: 0, call.argument<Int>("metaState") ?: 0)
                    "nativeScrcpyTouch" -> writer.injectTouch(call.argument<Int>("action") ?: 0,
                        call.argument<Number>("pointerId")?.toLong() ?: 0L, call.argument<Int>("x") ?: 0,
                        call.argument<Int>("y") ?: 0, call.argument<Int>("screenWidth") ?: 0,
                        call.argument<Int>("screenHeight") ?: 0, call.argument<Number>("pressure")?.toFloat() ?: 1f,
                        call.argument<Int>("actionButton") ?: 0, call.argument<Int>("buttons") ?: 0)
                }
                main.post { result.success(true) }
            } catch (error: Exception) {
                if (error is IOException) fail(error, token)
                main.post { result.error("native_control", error.message, null) }
            }
        }
    }

    private fun route(endpoint: AdbEndpoint): String {
        val forward = tsnet.startForward(endpoint)
        activeForwardId = forward.getValue("id") as String
        return "127.0.0.1:${forward.getValue("localPort")}"
    }

    private fun stop(closeTsnet: Boolean = true) {
        startupTimeout?.let(main::removeCallbacks)
        startupTimeout = null
        val previous = session
        val previousRequest = activeRequest
        activeRequest = null
        session = null
        adb.interrupt()
        previous?.close()
        texture?.let { output -> onMain { output.release() } }
        texture = null
        adb.close()
        if (closeTsnet) tsnet.close() else activeForwardId?.let(tsnet::stopForward)
        activeForwardId = null
        stopServiceIfIdle()
        tsnetStatus()
        if (previousRequest != null) videoEvent(previousRequest, "stopped")
    }

    private fun importLocalIdentity(token: Long) {
        val latch = CountDownLatch(1)
        val response = AtomicReference<TermuxBridge.CommandResult>()
        onMain { TermuxBridge(app).readAdbIdentity { response.set(it); latch.countDown() } }
        var attempts = 0
        while (!latch.await(100, TimeUnit.MILLISECONDS)) {
            ensureCurrent(token)
            if (++attempts >= 130) throw IOException("读取本机 ADB 配对身份超时")
        }
        ensureCurrent(token)
        val value = response.getAndSet(null)
        if (value?.exitCode != 0) throw IOException("请先完成 Termux 无线调试配对")
        try { adb.importLocalIdentity(value.stdout) }
        catch (_: Exception) { throw IOException("无法读取本机 ADB 配对身份，请重新配对") }
    }

    private fun fail(error: Throwable, token: Long) {
        if (disposed || !generation.compareAndSet(token, token + 1)) return
        adb.interrupt(); tsnet.interrupt("连接失败重连")
        queue.execute {
            if (!isCurrent(token + 1)) return@execute
            val request = desired
            stop()
            if (isCurrent(token + 1) && request != null) {
                videoEvent(request, "failed", mapOf("error" to (error.message ?: "原生连接已断开")))
                val attempt = retries.incrementAndGet()
                if (attempt <= 3) scheduleReconnect(token + 1, (1L shl (attempt - 1)) * 1000)
            }
        }
    }

    private fun networkChanged(key: String?, available: Boolean) {
        if (disposed || (networkKey == key && networkAvailable == available)) return
        networkKey = key; networkAvailable = available
        emit(mapOf("type" to "nativeNetwork", "state" to if (available) "connected" else "disconnected"))
        val request = desired ?: return
        if (request.mode == "local_virtual_display") return
        val token = interrupt("网络变化")
        queue.execute {
            if (!isCurrent(token)) return@execute
            stop()
            videoEvent(request, if (available) "reconnecting" else "waiting")
            if (available) scheduleReconnect(token, 750)
        }
    }

    fun setForeground(active: Boolean) {
        foreground = active
        if (active && desired != null && session == null) scheduleReconnect(generation.get(), 750)
    }

    private fun scheduleReconnect(token: Long, delay: Long) {
        main.postDelayed({
            val request = desired
            if (!isCurrent(token) || !foreground || request == null ||
                (!networkAvailable && request.mode != "local_virtual_display")) return@postDelayed
            queue.execute {
                if (isCurrent(token) && session == null) {
                    try { start(request, token) }
                    catch (error: Exception) { fail(error, token) }
                }
            }
        }, delay)
    }

    fun close() {
        if (disposed) return
        disposed = true
        desired = null
        interrupt("会话关闭")
        network?.unregisterNetworkCallback(networkCallback)
        inputQueue.shutdown()
        queue.execute { stop() }
        queue.shutdown()
    }

    private fun interrupt(reason: String): Long {
        val token = generation.incrementAndGet()
        adb.interrupt(); tsnet.interrupt(reason)
        return token
    }
    private fun isCurrent(token: Long) = !disposed && generation.get() == token
    private fun ensureCurrent(token: Long) { if (!isCurrent(token)) throw IOException("控制会话已取消") }
    private fun startService() = onMain { app.startForegroundService(ScrcpySessionService.start(app)) }
    private fun stopServiceIfIdle() {
        if (session == null && tsnet.status()["forwardCount"] == 0) app.stopService(ScrcpySessionService.start(app))
    }
    private fun tsnetStatus(): Map<String, Any> = tsnet.status().also { emit(it + ("type" to "tsnet")) }
    private fun videoEvent(request: Request, state: String, values: Map<String, Any?> = emptyMap()) =
        emit(mapOf("type" to "scrcpyVideo", "state" to state, "requestId" to request.id) + values)

    private fun execute(code: String, result: MethodChannel.Result, operation: () -> Any?) {
        queue.execute {
            try { val value = operation(); main.post { result.success(value) } }
            catch (error: Exception) { main.post { result.error(code, error.message, null) } }
        }
    }
    private fun <T> onMain(operation: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return operation()
        val task = FutureTask(operation)
        main.post(task)
        return task.get()
    }

    companion object {
        private val METHODS = setOf("getNativeControlSettings", "saveNativeControlSettings", "tsnetConfigure",
            "tsnetConnect", "tsnetStartForward", "tsnetStopForward", "tsnetStopAll", "tsnetClose", "tsnetStatus",
            "tsnetClearState", "nativeAdbConnect", "nativeAdbShell", "nativeAdbPush", "nativeAdbPull", "nativeAdbClose",
            "nativeScrcpyStart", "nativeScrcpyStop", "nativeScrcpyBack", "nativeScrcpyText", "nativeScrcpyKeycode", "nativeScrcpyTouch")
    }
}
