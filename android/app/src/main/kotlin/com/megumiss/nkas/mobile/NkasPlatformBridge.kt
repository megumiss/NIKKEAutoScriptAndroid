package com.megumiss.nkas.mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.annotation.Keep
import com.megumiss.nkas.mobile.platform.AccessGate
import com.megumiss.nkas.mobile.platform.BackendEntry
import com.megumiss.nkas.mobile.platform.AdbMdns
import com.megumiss.nkas.mobile.platform.AdbPairingService
import com.megumiss.nkas.mobile.platform.BootstrapLog
import com.megumiss.nkas.mobile.platform.BootstrapService
import com.megumiss.nkas.mobile.platform.GateConfig
import com.megumiss.nkas.mobile.platform.LogStore
import com.megumiss.nkas.mobile.platform.NativeControlSession
import com.megumiss.nkas.mobile.platform.SettingsStore
import com.megumiss.nkas.mobile.platform.TermuxBridge
import com.megumiss.nkas.mobile.platform.TermuxInstaller
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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
    private var nativeSession: NativeControlSession? = null

    fun register(engine: FlutterEngine) {
        nativeSession = NativeControlSession(activity, engine.renderer, ::emit)
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
        if (nativeSession?.handle(call, result) == true) return
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
            "restartNkasService" -> restartNkasService(result)
            "startNkasService" -> startNkasService(result)
            "stopNkasService" -> stopNkasService(result)
            "getLocalBackendEntry" -> readLocalBackendEntry(result)
            "setNkasSerial" -> writeNkasSerial(call, result)
            "getInitConfig" -> result.success(
                mapOf(
                    "webUiUrl" to SettingsStore.webUiUrl(activity),
                    "repository" to SettingsStore.repository(activity),
                    "aptSource" to SettingsStore.aptSource(activity),
                    "dockerImage" to SettingsStore.dockerImage(activity),
                    "repositorySources" to SettingsStore.repositorySources.map {
                        mapOf("label" to it.label, "value" to it.value)
                    },
                    "aptSources" to SettingsStore.aptSources.map {
                        mapOf("label" to it.label, "value" to it.value)
                    },
                ),
            )
            "saveInitConfig" -> saveInitConfig(call, result)
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

    private fun saveInitConfig(call: MethodCall, result: MethodChannel.Result) {
        val webUi = SettingsStore.normalizeWebUiUrl(call.argument<String>("webUiUrl").orEmpty())
        if (webUi == null) {
            result.error("invalid_webui", "WebUI 地址格式不正确，例如：http://127.0.0.1:12271", null)
            return
        }
        val repository = call.argument<String>("repository")?.trim().orEmpty()
        if (SettingsStore.repositorySources.none { it.value == repository }) {
            result.error("invalid_repository", "项目仓库不在可选列表中", null)
            return
        }
        val apt = call.argument<String>("aptSource")?.trim().orEmpty()
        if (SettingsStore.aptSources.none { it.value == apt }) {
            result.error("invalid_apt", "Termux apt 源不在可选列表中", null)
            return
        }
        val docker = call.argument<String>("dockerImage")?.trim().orEmpty()
        if (!docker.matches(Regex("[A-Za-z0-9._/-]+:[A-Za-z0-9._-]+"))) {
            result.error("invalid_docker", "Docker 镜像格式不正确，例如：docker.io/megumiss/nkas:latest", null)
            return
        }
        activity.getSharedPreferences(SettingsStore.PREFS_NAME, 0).edit()
            .putString("apt_source", apt)
            .putString("repository", repository)
            .putString("docker_image", docker)
            .putString("webui_url", webUi)
            .apply()
        result.success(true)
    }

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
            when (BootstrapLog.state(command.stdout)) {
                "ready" -> emit(mapOf("type" to "setup", "state" to "ready"))
                "failed" -> emit(mapOf(
                    "type" to "setup",
                    "state" to "failed",
                    "message" to output.takeLast(1000),
                ))
                // The first read can precede the state file; retry incomplete reads too.
                else -> main.postDelayed({ pollSetupLog() }, 2000)
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

    private fun restartNkasService(result: MethodChannel.Result) {
        TermuxBridge(activity).restartService { command ->
            main.post {
                if (command.exitCode == 0) result.success(command.stdout.trim())
                else result.error("restart_failed", command.stderr.ifBlank { command.stdout }.ifBlank { "重启 NKAS 服务失败" }, null)
            }
        }
    }

    private fun startNkasService(result: MethodChannel.Result) {
        TermuxBridge(activity).startService { command ->
            main.post {
                if (command.exitCode == 0) result.success(command.stdout.trim())
                else result.error("start_failed", command.stderr.ifBlank { command.stdout }.ifBlank { "启动 NKAS 服务失败" }, null)
            }
        }
    }

    private fun stopNkasService(result: MethodChannel.Result) {
        TermuxBridge(activity).stopService { command ->
            main.post {
                if (command.exitCode == 0) result.success(command.stdout.trim())
                else result.error("stop_failed", command.stderr.ifBlank { command.stdout }.ifBlank { "停止 NKAS 服务失败" }, null)
            }
        }
    }

    private fun readLocalBackendEntry(result: MethodChannel.Result) {
        val bridge = TermuxBridge(activity)
        val baseUrl = SettingsStore.webUiUrl(activity)
        if (!BackendEntry.isLocalHost(SettingsStore.webUiHost(activity)) ||
            !bridge.isInstalled() || !hasRunCommandPermission() || !AccessGate.isAuthorized(activity)) {
            result.error("local_entry_unavailable", "请先完成本机 Termux 部署与授权", null)
            return
        }
        bridge.readBackendEntry { command ->
            main.post {
                if (command.exitCode != 0) {
                    result.error("local_entry_unavailable", "无法读取本机安全入口，请检查 Termux 部署", null)
                } else {
                    try {
                        result.success(mapOf("baseUrl" to baseUrl, "key" to BackendEntry.parseKey(command.stdout)))
                    } catch (_: IllegalArgumentException) {
                        result.error("local_entry_invalid", "本机安全入口数据无效", null)
                    }
                }
            }
        }
    }

    fun close() {
        connectMdns?.stop()
        connectMdns = null
        nativeSession?.close()
        nativeSession = null
    }

    fun setForeground(active: Boolean) { nativeSession?.setForeground(active) }

    private fun writeNkasSerial(call: MethodCall, result: MethodChannel.Result) {
        val serial = call.argument<String>("serial")?.trim().orEmpty()
        TermuxBridge(activity).writeNkasSerial(serial) { command ->
            main.post {
                if (command.exitCode == 0) result.success(true)
                else result.error("write_nkas_serial", command.stderr.ifBlank { "无法更新 nkas.json 的 Serial" }, null)
            }
        }
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
