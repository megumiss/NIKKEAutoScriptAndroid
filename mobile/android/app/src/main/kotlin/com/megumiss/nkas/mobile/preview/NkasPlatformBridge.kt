package com.megumiss.nkas.mobile.preview

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.annotation.Keep
import com.megumiss.nkas.mobile.preview.platform.AccessGate
import com.megumiss.nkas.mobile.preview.platform.AdbPairingService
import com.megumiss.nkas.mobile.preview.platform.BootstrapService
import com.megumiss.nkas.mobile.preview.platform.GateConfig
import com.megumiss.nkas.mobile.preview.platform.LogStore
import com.megumiss.nkas.mobile.preview.platform.SettingsStore
import com.megumiss.nkas.mobile.preview.platform.TermuxBridge
import com.megumiss.nkas.mobile.preview.platform.TermuxInstaller
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

    fun register(engine: FlutterEngine) {
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
        val bridge = TermuxBridge(activity)
        val base = linkedMapOf<String, Any?>(
            "termuxInstalled" to bridge.isInstalled(),
            "runCommandPermission" to hasRunCommandPermission(),
            "wirelessDebug" to isWirelessDebugEnabled(),
            "authorized" to AccessGate.isAuthorized(activity),
            "serial" to SettingsStore.serial(activity),
        )
        if (!bridge.isInstalled() || !hasRunCommandPermission() || !isWirelessDebugEnabled()) {
            result.success(base)
            return
        }
        BootstrapService(activity).checkArtifacts { command ->
            val output = command.stdout + if (command.stderr.isBlank()) "" else "\n${command.stderr}"
            base["artifacts"] = parseArtifactOutput(output)
            base["commandExitCode"] = command.exitCode
            main.post { result.success(base) }
        }
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
        if (!isWirelessDebugEnabled()) {
            result.error("wireless_debug_required", "请先开启无线调试", null)
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
            activity.startService(AdbPairingService.startIntent(activity, code.ifBlank { null }))
            LogStore.log("pair", "Flutter 页面启动无线调试配对")
            result.success(mapOf("started" to true))
        }.onFailure { result.error("pair_failed", it.message ?: "无法启动配对服务", null) }
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
    }
}
