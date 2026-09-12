package com.megumiss.nkas.mobile

import android.content.Intent
import android.net.Uri
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Surface
import androidx.annotation.Keep
import com.megumiss.nkas.mobile.platform.AccessGate
import com.megumiss.nkas.mobile.platform.AdbMdns
import com.megumiss.nkas.mobile.platform.AdbPairingService
import com.megumiss.nkas.mobile.platform.BootstrapService
import com.megumiss.nkas.mobile.platform.GateConfig
import com.megumiss.nkas.mobile.platform.LogStore
import com.megumiss.nkas.mobile.platform.SettingsStore
import com.megumiss.nkas.mobile.platform.TermuxBridge
import com.megumiss.nkas.mobile.platform.TermuxInstaller
import com.megumiss.nkas.mobile.platform.adb.NativeAdbManager
import com.megumiss.nkas.mobile.platform.scrcpy.NativeScrcpyLauncher
import com.megumiss.nkas.mobile.platform.scrcpy.NativeScrcpySession
import com.megumiss.nkas.mobile.platform.scrcpy.ScrcpyServerOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.UUID

/** Bridges the existing Android STAR/Termux flow to the Flutter UI. */
@Keep
class NkasPlatformBridge(private val activity: FlutterActivity) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var installer: TermuxInstaller? = null
    private var connectMdns: AdbMdns? = null
    private var nativeAdb: NativeAdbManager? = null
    private var nativeScrcpy: NativeScrcpySession? = null
    private var textureRegistry: TextureRegistry? = null
    private var scrcpyTexture: TextureRegistry.SurfaceTextureEntry? = null
    private var connectivity: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val nativeExecutor: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "nkas-native-platform").apply { isDaemon = true }
    }

    fun register(engine: FlutterEngine) {
        textureRegistry = engine.renderer
        registerNetworkCallback()
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler(this)
        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(this)
    }

    fun handleIntent(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme != "nkas" || data.host != "auth" || data.path != "/callback") return
        val state = data.getQueryParameter("state")
        if (!AccessGate.consumeOAuthState(activity, state)) {
            emit(mapOf("type" to "star", "ok" to false, "error" to "验证回调无效，请重新验证"))
            return
        }
        val error = data.getQueryParameter("error")
        if (!error.isNullOrBlank()) {
            val message = when (error) {
                "repository_not_starred" -> "当前 GitHub 账号尚未 Star 项目，请完成 Star 后重试"
                "oauth_cancelled" -> "GitHub 验证已取消"
                "oauth_not_configured" -> "Star 验证服务尚未配置，请联系项目维护者"
                else -> "GitHub 验证失败，请稍后重试"
            }
            emit(mapOf("type" to "star", "ok" to false, "error" to message))
            return
        }
        val license = data.getQueryParameter("key")?.let { AccessGate.saveLicense(activity, it) }
        if (license == null) {
            emit(mapOf("type" to "star", "ok" to false, "error" to "验证密钥无效或已过期，请重新验证"))
            return
        }
        emit(starMap(license))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStarStatus" -> result.success(currentStar())
            "beginStarVerification" -> beginStar(result)
            "clearStarAuthorization" -> {
                AccessGate.clear(activity)
                result.success(currentStar())
            }
            "getSetupStatus" -> checkSetup(result)
            "startSetup" -> startSetup(result)
            "downloadTermux" -> downloadTermux(result)
            "requestRunCommandPermission" -> {
                activity.requestPermissions(arrayOf(TermuxBridge.RUN_COMMAND_PERMISSION), RUN_COMMAND_REQUEST)
                result.success(true)
            }
            "openAppSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
                runCatching { activity.startActivity(intent) }
                    .onFailure { activity.startActivity(Intent(Settings.ACTION_SETTINGS)) }
                result.success(true)
            }
            "openTermux" -> {
                val intent = activity.packageManager.getLaunchIntentForPackage("com.termux")
                if (intent == null) result.error("termux_missing", "未安装 Termux", null)
                else {
                    activity.startActivity(intent)
                    result.success(true)
                }
            }
            "pairDevice" -> pairDevice(call, result)
            "getAppLog" -> result.success(LogStore.text())
            "openWirelessSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                runCatching { activity.startActivity(intent) }
                    .onFailure { activity.startActivity(Intent(Settings.ACTION_SETTINGS)) }
                result.success(true)
            }
            "getSerial" -> result.success(SettingsStore.serial(activity))
            "setSerial" -> {
                val value = call.argument<String>("serial")?.trim().orEmpty()
                SettingsStore.setSerial(activity, value)
                result.success(value)
            }
            "getNkasSerial" -> readNkasSerial(result)
            "setNkasSerial" -> writeNkasSerial(call, result)
            "nativeAdbConnect" -> nativeAdbConnect(call, result)
            "nativeAdbShell" -> nativeAdbShell(call, result)
            "nativeAdbPush" -> nativeAdbPush(call, result)
            "nativeAdbPull" -> nativeAdbPull(call, result)
            "nativeScrcpyStart" -> nativeScrcpyStart(call, result)
            "nativeScrcpyStop" -> {
                stopNativeScrcpy()
                result.success(true)
            }
            "nativeScrcpyBack" -> nativeScrcpy?.controlWriter?.pressBack(call.argument<Int>("action") ?: 0)
                ?.let { result.success(true) } ?: result.error("native_scrcpy", "scrcpy 未启动", null)
            "nativeScrcpyText" -> nativeScrcpy?.controlWriter?.injectText(call.argument<String>("text").orEmpty())
                ?.let { result.success(true) } ?: result.error("native_scrcpy", "scrcpy 未启动", null)
            "nativeScrcpyKeycode" -> nativeScrcpyKeycode(call, result)
            "nativeScrcpyTouch" -> nativeScrcpyTouch(call, result)
            "nativeAdbClose" -> {
                nativeAdb?.close()
                nativeAdb = null
                result.success(true)
            }
            "getInitialNoticeShown" -> result.success(
                activity.getSharedPreferences(SETUP_PREFS_NAME, 0)
                    .getBoolean(KEY_INITIAL_NOTICE_SHOWN, false),
            )
            "setInitialNoticeShown" -> {
                activity.getSharedPreferences(SETUP_PREFS_NAME, 0).edit()
                    .putBoolean(KEY_INITIAL_NOTICE_SHOWN, true)
                    .apply()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun currentStar(): Map<String, Any?> =
        AccessGate.storedLicense(activity)?.let(::starMap)
            ?: mapOf("type" to "star", "authorized" to false)

    private fun starMap(license: AccessGate.License): Map<String, Any?> = mapOf(
        "type" to "star",
        "authorized" to true,
        "ok" to true,
        "username" to license.username,
        "repository" to license.repository,
        "expiresAt" to license.expiresAt,
    )

    private fun beginStar(result: MethodChannel.Result) {
        val state = UUID.randomUUID().toString()
        AccessGate.saveOAuthState(activity, state)
        val intent = Intent(Intent.ACTION_VIEW, GateConfig.authorizationUrl(state))
        runCatching {
            activity.startActivity(intent)
            result.success(mapOf("started" to true, "state" to state))
        }.onFailure {
            result.error("browser_unavailable", "无法打开浏览器，请检查系统浏览器", null)
        }
    }

    private fun checkSetup(result: MethodChannel.Result) {
        ensureConnectDiscovery()
        val bridge = TermuxBridge(activity)
        val base = linkedMapOf<String, Any?>(
            "termuxInstalled" to bridge.isInstalled(),
            "termuxVersion" to termuxVersion(),
            "runCommandPermission" to hasRunCommandPermission(),
            "wirelessDebug" to isWirelessDebugEnabled(),
            "authorized" to AccessGate.isAuthorized(activity),
            "serial" to SettingsStore.serial(activity),
        )
        if (!bridge.isInstalled() || !hasRunCommandPermission()) {
            result.success(base)
            return
        }
        BootstrapService(activity).checkArtifacts { command ->
            val output = command.stdout + if (command.stderr.isBlank()) "" else "\n${command.stderr}"
            base["artifacts"] = parseArtifactOutput(output)
            base["commandExitCode"] = command.exitCode
            base["adbConnect"] = output.lineSequence()
                .firstOrNull { it.startsWith("adb_connect=") }
                ?.substringAfter('=')
                ?.trim()
                .orEmpty()
            main.post { result.success(base) }
        }
    }

    private fun ensureConnectDiscovery() {
        if (connectMdns != null) return
        connectMdns = AdbMdns(activity, AdbMdns.TLS_CONNECT) { port ->
            main.post {
                if (port <= 0) return@post
                val serial = "127.0.0.1:$port"
                if (SettingsStore.serial(activity) != serial) {
                    SettingsStore.setSerial(activity, serial)
                    LogStore.log("adb", "mDNS 自动发现连接端口：$port")
                    emit(mapOf("type" to "setupNotice", "message" to "已通过 mDNS 自动发现无线调试端口：$port"))
                    emit(mapOf("type" to "setupSerial", "serial" to serial))
                }
            }
        }.apply { start() }
    }

    private fun startSetup(result: MethodChannel.Result) {
        if (!AccessGate.isAuthorized(activity)) {
            result.error("star_required", "请先完成 STAR 验证", null)
            return
        }
        val bridge = TermuxBridge(activity)
        if (!bridge.isInstalled()) {
            result.error("termux_missing", "未安装 Termux", null)
            return
        }
        if (!hasRunCommandPermission()) {
            result.error("run_command_permission", "未授权 Termux 外部命令", null)
            return
        }
        LogStore.log("bootstrap", "Flutter 页面开始执行安装脚本")
        val started = BootstrapService(activity).start { command ->
            val output = command.stdout + if (command.stderr.isBlank()) "" else "\n${command.stderr}"
            emit(mapOf(
                "type" to "setupCommand",
                "exitCode" to command.exitCode,
                "output" to output.takeLast(6000),
            ))
            if (command.exitCode != 0 && command.exitCode != -2) {
                emit(mapOf("type" to "setup", "state" to "failed", "message" to output.takeLast(1000)))
            }
        }
        started.fold(
            onSuccess = { result.success(mapOf("started" to true)) },
            onFailure = { result.error("start_failed", it.message ?: "无法启动 Termux 安装脚本", null) },
        )
        pollSetupLog()
    }

    private fun pollSetupLog() {
        BootstrapService(activity).readLog { command ->
            val output = command.stdout + if (command.stderr.isBlank()) "" else "\n${command.stderr}"
            emit(mapOf("type" to "setupLog", "output" to output.takeLast(12000)))
            if (output.contains("state=installing-") || output.contains("state=cloning-") ||
                output.contains("state=creating-") || output.contains("state=installing-container") ||
                output.contains("state=starting-nkas")) {
                main.postDelayed({ pollSetupLog() }, 2000)
            } else if (output.contains("state=ready")) {
                emit(mapOf("type" to "setup", "state" to "ready"))
            } else if (output.contains("state=failed")) {
                emit(mapOf(
                    "type" to "setup",
                    "state" to "failed",
                    "message" to output.takeLast(1000),
                ))
            }
        }
    }

    private fun pairDevice(call: MethodCall, result: MethodChannel.Result) {
        val code = call.argument<String>("code")?.trim().orEmpty()
        val serial = call.argument<String>("serial")?.trim().orEmpty()
        if (serial.isNotBlank()) SettingsStore.setSerial(activity, serial)
        val validCode = code.isBlank() || code.matches(Regex("[0-9]{4,8}"))
        if (!validCode) {
            result.error("invalid_pair_code", "配对码格式不正确", null)
            return
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                activity.requestPermissions(
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_REQUEST,
                )
            }
            activity.startService(AdbPairingService.startIntent(activity, code.ifBlank { null }))
            LogStore.log("pair", "Flutter 页面启动无线调试配对")
            result.success(mapOf("started" to true))
        }.onFailure { result.error("pair_failed", it.message ?: "无法启动配对服务", null) }
    }

    private fun readNkasSerial(result: MethodChannel.Result) {
        TermuxBridge(activity).readNkasSerial { command ->
            main.post {
                if (command.exitCode == 0) result.success(command.stdout.trim())
                else result.error("read_nkas_serial", command.stderr.ifBlank { "无法读取 nkas.json 的 Serial" }, null)
            }
        }
    }

    fun close() {
        unregisterNetworkCallback()
        stopNativeScrcpy()
        nativeAdb?.close()
        nativeAdb = null
        nativeExecutor.shutdownNow()
    }

    private fun writeNkasSerial(call: MethodCall, result: MethodChannel.Result) {
        val serial = call.argument<String>("serial")?.trim().orEmpty()
        TermuxBridge(activity).writeNkasSerial(serial) { command ->
            main.post {
                if (command.exitCode == 0) result.success(true)
                else result.error("write_nkas_serial", command.stderr.ifBlank { "无法更新 nkas.json 的 Serial" }, null)
            }
        }
    }

    private fun nativeAdbConnect(call: MethodCall, result: MethodChannel.Result) {
        val endpoint = call.argument<String>("endpoint")?.trim().orEmpty()
        if (endpoint.isBlank()) {
            result.error("native_adb_endpoint", "ADB 地址不能为空", null)
            return
        }
        runCatching {
            (nativeAdb ?: NativeAdbManager(activity).also { nativeAdb = it }).connect(endpoint)
        }.fold(
            onSuccess = { parsed -> result.success(mapOf("endpoint" to parsed.toString())) },
            onFailure = { error -> result.error("native_adb_connect", error.message ?: "ADB 连接失败", null) },
        )
    }

    private fun nativeAdbShell(call: MethodCall, result: MethodChannel.Result) {
        val command = call.argument<String>("command")?.trim().orEmpty()
        if (command.isBlank()) {
            result.error("native_adb_command", "ADB shell 命令不能为空", null)
            return
        }
        runCatching { (nativeAdb ?: throw IllegalStateException("ADB is not connected")).shell(command) }
            .fold(
                onSuccess = result::success,
                onFailure = { error -> result.error("native_adb_shell", error.message ?: "ADB shell 失败", null) },
            )
    }

    private fun nativeAdbPush(call: MethodCall, result: MethodChannel.Result) {
        val data = call.argument<ByteArray>("data")
        val remotePath = call.argument<String>("remotePath")?.trim().orEmpty()
        if (data == null || remotePath.isBlank()) {
            result.error("native_adb_push_args", "ADB push 参数不完整", null)
            return
        }
        val mode = call.argument<Int>("unixMode") ?: 420
        runCatching { (nativeAdb ?: throw IllegalStateException("ADB is not connected")).push(data, remotePath, mode) }
            .fold(
                onSuccess = { result.success(true) },
                onFailure = { error -> result.error("native_adb_push", error.message ?: "ADB push 失败", null) },
            )
    }

    private fun nativeAdbPull(call: MethodCall, result: MethodChannel.Result) {
        val remotePath = call.argument<String>("remotePath")?.trim().orEmpty()
        if (remotePath.isBlank()) {
            result.error("native_adb_pull_args", "ADB pull 路径不能为空", null)
            return
        }
        runCatching { (nativeAdb ?: throw IllegalStateException("ADB is not connected")).pull(remotePath) }
            .fold(
                onSuccess = result::success,
                onFailure = { error -> result.error("native_adb_pull", error.message ?: "ADB pull 失败", null) },
            )
    }

    private fun nativeScrcpyStart(call: MethodCall, result: MethodChannel.Result) {
        val endpoint = call.argument<String>("endpoint")?.trim().orEmpty()
        if (endpoint.isBlank()) {
            result.error("native_scrcpy_endpoint", "ADB 地址不能为空", null)
            return
        }
        val options = ScrcpyServerOptions(
            video = call.argument<Boolean>("video") ?: true,
            audio = false,
            control = call.argument<Boolean>("control") ?: true,
            maxSize = call.argument<Int>("maxSize") ?: 0,
            videoBitRate = call.argument<Int>("videoBitRate") ?: 0,
        )
        if (options.video && textureRegistry == null) {
            result.error("native_scrcpy_texture", "Flutter Texture 尚未注册", null)
            return
        }
        stopNativeScrcpy()
        scrcpyTexture = if (options.video) textureRegistry!!.createSurfaceTexture() else null
        val surface = scrcpyTexture?.let { Surface(it.surfaceTexture()) }
        nativeExecutor.execute {
            runCatching {
                val manager = nativeAdb ?: NativeAdbManager(activity).also { nativeAdb = it }
                manager.connect(endpoint)
                val jar = activity.assets.open("bin/scrcpy-server-v4.1").use { it.readBytes() }
                NativeScrcpyLauncher(manager).start(jar, options).also { session ->
                    nativeScrcpy = session
                    if (surface != null) {
                        session.startVideo(surface, object : NativeScrcpySession.VideoListener {
                            override fun onSize(width: Int, height: Int) {
                                emit(mapOf("type" to "scrcpyVideo", "state" to "size", "width" to width, "height" to height))
                            }

                            override fun onError(error: Throwable) {
                                emit(mapOf("type" to "scrcpyVideo", "state" to "error", "error" to (error.message ?: "视频解码失败")))
                            }

                            override fun onStopped() {
                                emit(mapOf("type" to "scrcpyVideo", "state" to "stopped"))
                            }
                        })
                    }
                }
            }.fold(
                onSuccess = { session ->
                    main.post {
                        emit(mapOf(
                            "type" to "scrcpyVideo",
                            "state" to "started",
                            "textureId" to scrcpyTexture?.id(),
                            "deviceName" to session.videoMetadata?.deviceName,
                            "codecId" to session.videoMetadata?.codecId,
                        ))
                        result.success(mapOf(
                            "scid" to session.scid,
                            "command" to session.command,
                            "deviceName" to session.videoMetadata?.deviceName,
                            "codecId" to session.videoMetadata?.codecId,
                            "textureId" to scrcpyTexture?.id(),
                            "video" to (session.videoStream != null),
                            "control" to (session.controlStream != null),
                        ))
                    }
                },
                onFailure = { error ->
                    if (nativeScrcpy == null) surface?.release()
                    nativeScrcpy?.close()
                    nativeScrcpy = null
                    scrcpyTexture?.release()
                    scrcpyTexture = null
                    main.post { result.error("native_scrcpy_start", error.message ?: "scrcpy 启动失败", null) }
                },
            )
        }
    }

    private fun stopNativeScrcpy() {
        val hadSession = nativeScrcpy != null || scrcpyTexture != null
        nativeScrcpy?.close()
        nativeScrcpy = null
        scrcpyTexture?.release()
        scrcpyTexture = null
        if (hadSession) emit(mapOf("type" to "scrcpyVideo", "state" to "stopped"))
    }

    private fun registerNetworkCallback() {
        if (networkCallback != null) return
        val manager = activity.getSystemService(ConnectivityManager::class.java) ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                emit(mapOf("type" to "nativeNetwork", "state" to "available"))
            }

            override fun onLost(network: Network) {
                if (nativeScrcpy != null) {
                    stopNativeScrcpy()
                    emit(mapOf("type" to "scrcpyVideo", "state" to "error", "error" to "网络连接已断开"))
                }
                emit(mapOf("type" to "nativeNetwork", "state" to "lost"))
            }
        }
        runCatching { manager.registerDefaultNetworkCallback(callback) }
            .onSuccess {
                connectivity = manager
                networkCallback = callback
            }
    }

    private fun unregisterNetworkCallback() {
        val manager = connectivity
        val callback = networkCallback
        if (manager != null && callback != null) runCatching { manager.unregisterNetworkCallback(callback) }
        connectivity = null
        networkCallback = null
    }

    private fun nativeScrcpyKeycode(call: MethodCall, result: MethodChannel.Result) {
        val writer = nativeScrcpy?.controlWriter
        if (writer == null) {
            result.error("native_scrcpy", "scrcpy 未启动", null)
            return
        }
        writer.injectKeycode(
            call.argument<Int>("action") ?: 0,
            call.argument<Int>("keycode") ?: 0,
            call.argument<Int>("repeat") ?: 0,
            call.argument<Int>("metaState") ?: 0,
        )
        result.success(true)
    }

    private fun nativeScrcpyTouch(call: MethodCall, result: MethodChannel.Result) {
        val writer = nativeScrcpy?.controlWriter
        if (writer == null) {
            result.error("native_scrcpy", "scrcpy 未启动", null)
            return
        }
        writer.injectTouch(
            action = call.argument<Int>("action") ?: 0,
            pointerId = call.argument<Number>("pointerId")?.toLong() ?: 0L,
            x = call.argument<Int>("x") ?: 0,
            y = call.argument<Int>("y") ?: 0,
            screenWidth = call.argument<Int>("screenWidth") ?: 1,
            screenHeight = call.argument<Int>("screenHeight") ?: 1,
            pressure = call.argument<Number>("pressure")?.toFloat() ?: 1f,
            actionButton = call.argument<Int>("actionButton") ?: 0,
            buttons = call.argument<Int>("buttons") ?: 0,
        )
        result.success(true)
    }

    private fun downloadTermux(result: MethodChannel.Result) {
        if (TermuxBridge(activity).isInstalled()) {
            result.success(mapOf("installed" to true))
            return
        }
        if (installer != null) {
            result.success(mapOf("started" to true))
            return
        }
        installer = TermuxInstaller(activity).also { current ->
            current.download(
                onProgress = { progress -> emit(mapOf("type" to "termuxDownload", "progress" to progress)) },
                onComplete = { asset ->
                    installer = null
                    emit(mapOf("type" to "termuxDownload", "progress" to 100, "message" to "已下载 $asset，请完成系统安装"))
                },
                onError = { message ->
                    installer = null
                    emit(mapOf("type" to "termuxDownload", "error" to message))
                },
            )
        }
        result.success(mapOf("started" to true))
    }

    private fun parseArtifactOutput(output: String): Map<String, Boolean> = buildMap {
        output.lineSequence().forEach { line ->
            val separator = line.indexOf('=')
            if (separator <= 0) return@forEach
            val key = line.substring(0, separator).trim()
            val value = line.substring(separator + 1).trim().equals("yes", ignoreCase = true)
            if (key in ARTIFACT_KEYS) put(key, value)
        }
    }

    private fun hasRunCommandPermission() =
        activity.checkSelfPermission(TermuxBridge.RUN_COMMAND_PERMISSION) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    private fun termuxVersion(): String? = runCatching {
        activity.packageManager.getPackageInfo("com.termux", 0).versionName
    }.getOrNull()

    private fun isWirelessDebugEnabled(): Boolean = try {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            Settings.Global.getInt(activity.contentResolver, "adb_wifi_enabled", 0) == 1
    } catch (_: Settings.SettingNotFoundException) {
        false
    }

    private fun emit(value: Map<String, Any?>) {
        main.post { events?.success(value) }
    }

    companion object {
        const val CHANNEL = "com.megumiss.nkas/platform"
        const val EVENTS = "com.megumiss.nkas/platform_events"
        private val ARTIFACT_KEYS = setOf(
            "termux_setting", "tools", "source", "config", "container", "service", "adb_device",
        )
        private const val RUN_COMMAND_REQUEST = 1001
        private const val NOTIFICATION_REQUEST = 1002
        private const val SETUP_PREFS_NAME = "nkas_state"
        private const val KEY_INITIAL_NOTICE_SHOWN = "initial_notice_shown"
    }
}
