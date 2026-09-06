package com.megumiss.nkas

import android.app.Activity
import android.content.Intent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.net.Uri
import android.view.View
import android.view.Gravity
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.app.AlertDialog
import android.util.Log
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.Locale

/**
 * 初始化页：由 SetupActivity 迁移为单 Activity 内的页面渲染器。
 * hide() 等价于旧实现的 finish()：停止轮询；show() 等价于重新进入页面：重置状态并重新检查。
 */
class SetupPage(private val activity: Activity, private val navigate: (String) -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var content: LinearLayout
    private lateinit var status: TextView
    private lateinit var action: Button
    private lateinit var floatingHost: FrameLayout
    private var serialInput: EditText? = null
    private var pairAddressInput: EditText? = null
    private var pairCodeInput: EditText? = null
    private var checking = false
    private var destroyed = false
    private var visible = false
    private var bootstrapActive = false
    private var artifactChecking = false
    private var termuxDownloadActive = false
    private var expandedLogKey: String? = null
    private var bootstrapStageIndex = -1
    private var initialNoticeShowing = false
    private val artifactState = mutableMapOf<String, Boolean>()
    private val steps = linkedMapOf<String, Step>()

    fun show(container: FrameLayout) {
        visible = true
        bootstrapActive = false
        artifactChecking = false
        termuxDownloadActive = false
        checking = false
        bootstrapStageIndex = -1
        initialNoticeShowing = false
        expandedLogKey = null
        serialInput = null
        pairAddressInput = null
        pairCodeInput = null
        artifactState.clear()
        steps.clear()
        val root = FrameLayout(activity)
        val scroll = ScrollView(activity).apply { isFillViewport = true }
        content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(24), dp(24), dp(170)) }
        scroll.addView(content)
        root.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        floatingHost = FrameLayout(activity).apply { setBackgroundColor(Ui.bg) }
        root.addView(floatingHost, FrameLayout.LayoutParams(-1, dp(78), Gravity.BOTTOM))
        container.addView(root, FrameLayout.LayoutParams(-1, -1))
        renderSetup()
        refreshState()
    }

    fun hide() {
        visible = false
        handler.removeCallbacksAndMessages(null)
    }

    fun destroy() {
        destroyed = true
        hide()
        executor.shutdownNow()
    }

    fun onResume() {
        if (visible && ::content.isInitialized) refreshState()
    }

    private fun renderSetup() {
        content.removeAllViews()
        heading("初始化", "准备 Termux、NKAS 服务和本地 Web UI\n请开启 Termux 和 NKAS 的自启动、关联启动，并允许后台运行")
        status = TextView(activity).apply { textSize = 14f; setTextColor(Ui.text2); setPadding(0, 0, 0, dp(16)); visibility = View.GONE }
        content.addView(status)
        section("环境准备")
        step("Termux", termuxDetail(), "termux")
        val permissionStep = step("Android 外部命令权限", "系统权限：Run commands in Termux environment", "permission")
        permissionHint(permissionStep.wrapper)
        val termuxSettingStep = step("Termux 外部应用开关", "Termux 配置 allow-external-apps=true", "termux_setting")
        manualCommand(termuxSettingStep.wrapper)
        step("无线调试", "开启并检查 Android 无线调试", "wireless")
        val adbStep = step("ADB 设备连接", "Termux 中必须能看到状态为 device 的设备", "adb_device")
        serialInput = serialEditor(adbStep.wrapper)
        pairEditor(adbStep.wrapper)
        section("项目安装")
        step("Termux 工具", "安装 bash、git、adb、curl 等工具", "tools")
        step("NKAS 源码", "下载并更新项目文件", "source")
        step("项目配置", "写入本地设备和 Web UI 配置", "config")
        step("容器", "安装包含 Python 运行环境的 NKAS 容器", "container")
        step("容器服务", "启动本地服务和 Web UI", "service")
        setProjectBlocked()
        action = Button(activity).apply { text = "开始安装"; textSize = 14f; isAllCaps = false; setOnClickListener { onAction() }; elevation = dp(6).toFloat() }
        setActionEnabled(false)
        floatingHost.removeAllViews()
        floatingHost.addView(action, FrameLayout.LayoutParams(-1, dp(52)).apply { leftMargin = dp(24); rightMargin = dp(24); topMargin = dp(10) })
    }

    private fun serialEditor(parent: LinearLayout): EditText {
        parent.addView(TextView(activity).apply {
            text = "优先自动发现已授权设备；只有自动发现不到时，才使用这里填写的 Serial。"
            textSize = 12f
            setTextColor(Ui.text2)
            setPadding(0, dp(8), 0, dp(6))
        })
        val input = EditText(activity).apply {
            setText(SettingsStore.serial(activity))
            hint = "Serial（可留空使用自动检测）"
            textSize = 13f
            setSingleLine(true)
            setTextColor(Ui.text)
            setHintTextColor(Ui.text2)
            inputType = android.text.InputType.TYPE_CLASS_TEXT
            setPadding(dp(12), 0, dp(12), 0)
            background = rounded(Ui.card2, 6)
        }
        parent.addView(input, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(6) })
        parent.addView(Button(activity).apply {
            text = "保存并重新检查"
            textSize = 12f
            Ui.styleSecondary(activity, this)
            setOnClickListener {
                val value = input.text.toString().trim()
                if (value.isNotBlank() && !value.matches(Regex("[A-Za-z0-9._:-]+"))) {
                    status.text = "Serial 格式不正确，请填写设备序列号或 IP:端口。"
                    return@setOnClickListener
                }
                SettingsStore.setSerial(activity, value)
                status.text = "已保存 Serial，正在检查 Termux 设备连接……"
                refreshState()
            }
        }, LinearLayout.LayoutParams(-1, dp(42)).apply { topMargin = dp(8) })
        return input
    }

    private fun pairEditor(parent: LinearLayout) {
        parent.addView(TextView(activity).apply {
            text = "需要配对时，在 Android 的无线调试页面查看配对地址和配对码；配对命令由 Termux 执行。"
            textSize = 12f
            setTextColor(Ui.text2)
            setPadding(0, dp(12), 0, dp(6))
        })
        val address = EditText(activity).apply {
            hint = "配对地址，例如 192.168.1.20:37099"
            textSize = 13f
            setSingleLine(true)
            setTextColor(Ui.text)
            setHintTextColor(Ui.text2)
            inputType = android.text.InputType.TYPE_CLASS_TEXT
            setPadding(dp(12), 0, dp(12), 0)
            background = rounded(Ui.card2, 6)
        }
        val code = EditText(activity).apply {
            hint = "配对码"
            textSize = 13f
            setSingleLine(true)
            setTextColor(Ui.text)
            setHintTextColor(Ui.text2)
            inputType = android.text.InputType.TYPE_CLASS_NUMBER
            setPadding(dp(12), 0, dp(12), 0)
            background = rounded(Ui.card2, 6)
        }
        pairAddressInput = address
        pairCodeInput = code
        parent.addView(address, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(6) })
        parent.addView(code, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(8) })
        parent.addView(Button(activity).apply {
            text = "执行配对"
            textSize = 12f
            Ui.styleSecondary(activity, this)
            setOnClickListener { pairDevice() }
        }, LinearLayout.LayoutParams(-1, dp(42)).apply { topMargin = dp(8) })
    }

    private fun pairDevice() {
        if (bootstrapActive || artifactChecking) return
        val address = pairAddressInput?.text?.toString()?.trim().orEmpty()
        val code = pairCodeInput?.text?.toString()?.trim().orEmpty()
        if (!address.matches(Regex("[A-Za-z0-9._:-]+:[0-9]{1,5}"))) {
            status.visibility = View.VISIBLE
            status.text = "配对地址格式不正确，请填写无线调试显示的 IP:端口。"
            return
        }
        if (!code.matches(Regex("[0-9]{4,8}"))) {
            status.visibility = View.VISIBLE
            status.text = "配对码格式不正确，请填写无线调试显示的数字配对码。"
            return
        }
        status.visibility = View.VISIBLE
        status.text = "正在通过 Termux 执行 ADB 配对……"
        setActionEnabled(false)
        TermuxBridge(activity).pairDevice(address, code) { result ->
            handler.post {
                if (!visible) return@post
                val output = (result.stdout + if (result.stderr.isNotBlank()) "\n${result.stderr}" else "").trim()
                setStepLog("adb_device", output.ifBlank { "adb pair 返回码：${result.exitCode}" }, true)
                status.text = if (result.exitCode == 0) "ADB 配对完成，正在检查设备连接……" else "ADB 配对失败，请展开 ADB 设备日志查看返回结果。"
                refreshState()
            }
        }
    }

    private fun manualCommand(parent: LinearLayout) {
        parent.addView(TextView(activity).apply { text = "在 Termux 中执行以下命令，然后完全退出并重新打开 Termux。页面会根据实际配置自动更新状态。"; textSize = 12f; setTextColor(Ui.text2); setPadding(0, dp(8), 0, dp(6)) })
        val command = "mkdir -p ~/.termux\necho 'allow-external-apps=true' > ~/.termux/termux.properties"
        parent.addView(TextView(activity).apply { text = command; textSize = 12f; setTextColor(Ui.text); typeface = Typeface.MONOSPACE; setPadding(dp(10), dp(10), dp(10), dp(10)); background = rounded(Ui.card2, 6) })
        val actions = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val open = Button(activity).apply { text = "打开 Termux"; textSize = 12f; Ui.styleSecondary(activity, this); setOnClickListener { activity.packageManager.getLaunchIntentForPackage("com.termux")?.let { activity.startActivity(it) } } }
        val copy = Button(activity).apply { text = "复制命令"; textSize = 12f; Ui.styleSecondary(activity, this); setOnClickListener { (activity.getSystemService(Activity.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Termux 命令", command)); text = "已复制" } }
        actions.addView(open, LinearLayout.LayoutParams(0, dp(42), 1f)); actions.addView(copy, LinearLayout.LayoutParams(0, dp(42), 1f).apply { leftMargin = dp(8) })
        parent.addView(actions, LinearLayout.LayoutParams(-1, dp(42)).apply { topMargin = dp(8) })
    }

    private fun permissionHint(parent: LinearLayout) {
        parent.addView(TextView(activity).apply {
            text = "部分系统不会弹出授权框，需要在系统设置中手动允许 NKAS 使用 Run commands in Termux environment。"
            textSize = 12f
            setTextColor(Ui.text2)
            setPadding(0, dp(8), 0, dp(6))
        })
        parent.addView(Button(activity).apply {
            text = "打开应用权限设置"
            textSize = 12f
            Ui.styleSecondary(activity, this)
            setOnClickListener { openRunCommandSettings() }
        }, LinearLayout.LayoutParams(-1, dp(42)))
    }

    private fun openRunCommandSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        runCatching { activity.startActivity(intent) }
            .onFailure { activity.startActivity(Intent(Settings.ACTION_SETTINGS)) }
    }

    private fun heading(main: String, sub: String) {
        content.addView(TextView(activity).apply { text = main; textSize = 26f; setTextColor(Ui.text); setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        content.addView(TextView(activity).apply { text = sub; textSize = 14f; setTextColor(Ui.text2); setPadding(0, dp(6), 0, dp(20) ) })
    }

    private fun section(label: String) { content.addView(TextView(activity).apply { text = label.uppercase(); textSize = 11f; setTextColor(Ui.text2); setTypeface(Typeface.DEFAULT, Typeface.BOLD); setPadding(0, dp(8), 0, dp(8)) }) }

    private data class Step(val dot: TextView, val state: TextView, val progress: ProgressBar, val key: String, val wrapper: LinearLayout, val detail: TextView, val log: TextView)
    private fun step(name: String, detail: String, key: String): Step {
        val wrapper = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(14), dp(10), dp(14), dp(10)); background = rounded(Ui.card, 10) }
        val row = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val dot = TextView(activity).apply { text = "○"; textSize = 22f; setTextColor(Ui.text2); gravity = Gravity.CENTER }
        val labels = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        labels.addView(TextView(activity).apply { text = name; textSize = 15f; setTextColor(Ui.text) })
        val detailView = TextView(activity).apply { text = detail; textSize = 12f; setTextColor(Ui.text2); setPadding(0, dp(3), 0, 0) }
        labels.addView(detailView)
        val state = TextView(activity).apply { textSize = 12f; setTextColor(Ui.text2); gravity = Gravity.CENTER }
        val progress = ProgressBar(activity).apply { isIndeterminate = true; visibility = View.GONE }
        val log = TextView(activity).apply { textSize = 11f; setTextColor(Ui.text2); setPadding(dp(10), dp(8), dp(10), dp(8)); background = rounded(Ui.card2, 6); visibility = View.GONE; typeface = Typeface.MONOSPACE; maxLines = 12 }
        val statusBox = FrameLayout(activity).apply {
            addView(progress, FrameLayout.LayoutParams(dp(28), dp(28), Gravity.END or Gravity.CENTER_VERTICAL))
            addView(state, FrameLayout.LayoutParams(-1, -2, Gravity.CENTER_VERTICAL))
        }
        row.addView(dot, LinearLayout.LayoutParams(dp(30), dp(30))); row.addView(labels, LinearLayout.LayoutParams(0, -2, 1f)); row.addView(statusBox, LinearLayout.LayoutParams(dp(64), dp(30)))
        wrapper.addView(row); wrapper.addView(log, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
        val item = Step(dot, state, progress, key, wrapper, detailView, log)
        steps[key] = item
        content.addView(wrapper, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(8) })
        return item
    }

    private fun setStep(key: String, done: Boolean, label: String) {
        val info = steps[key] ?: return
        info.dot.text = if (done) "✓" else "○"
        info.dot.setTextColor(if (done) Ui.green else Ui.text2)
        val running = !done && label == "执行中"
        info.progress.visibility = if (running) View.VISIBLE else View.GONE
        info.state.text = if (running) "" else label
        info.state.setTextColor(if (done) Ui.green else Ui.text2)
        if (done) {
            info.log.visibility = View.GONE
            if (expandedLogKey == key) expandedLogKey = null
        }
    }

    private fun setStepDetail(key: String, value: String) {
        steps[key]?.detail?.text = value
    }

    private fun termuxDetail(): String {
        val version = runCatching {
            activity.packageManager.getPackageInfo("com.termux", 0).versionName
        }.getOrNull()?.takeIf { it.isNotBlank() }
        return if (version == null) "需要安装官方 Termux" else "已安装版本：Termux v$version"
    }

    private fun setStepLog(key: String, value: String, expanded: Boolean = true) {
        val info = steps[key] ?: return
        info.log.text = value.takeLast(5000)
        if (expanded && value.isNotBlank()) {
            steps.values.forEach { other ->
                if (other.key != key) other.log.visibility = View.GONE
            }
            expandedLogKey = key
            info.log.visibility = View.VISIBLE
        } else {
            info.log.visibility = View.GONE
            if (expandedLogKey == key) expandedLogKey = null
        }
    }

    private fun applyBootstrapLog(raw: String) {
        if (raw.isBlank()) return
        val state = raw.substringAfter("---STATE---", "").substringBefore("---LOG---").trim().lowercase(Locale.ROOT)
        val log = raw.substringAfter("---LOG---", "").substringBefore("---SERVICE---").trim()
        val service = raw.substringAfter("---SERVICE---", "").trim()
        val mapping = listOf("installing-termux-tools" to "tools", "cloning-nkas" to "source", "creating-config" to "config", "installing-container" to "container", "starting-nkas" to "service")
        var active: String? = null
        val currentIndex = mapping.indexOfFirst { it.first == state }
        if (currentIndex >= 0 && bootstrapStageIndex > currentIndex) return
        if (currentIndex >= 0) bootstrapStageIndex = currentIndex
        mapping.forEach { (stage, key) ->
            if (state == stage) active = key
            val stageIndex = mapping.indexOfFirst { it.first == stage }
            val done = state == "ready" || (currentIndex >= 0 && currentIndex > stageIndex)
            setStep(key, done, if (done) "完成" else if (state == stage) "执行中" else "等待")
        }
        active?.let { setStepLog(it, log.ifBlank { "正在执行……" }, true) }
        if (service.isNotBlank()) setStepLog("service", service, active == "service")
        if (bootstrapActive && active != null && state != "failed" && state != "ready") {
            status.text = "安装正在执行，当前步骤日志会持续更新……"
            action.text = "安装中"
            setActionEnabled(false)
        }
        if (state == "failed") {
            bootstrapActive = false
            val failed = active ?: mapping.firstOrNull { (stage, _) -> log.contains("stage $stage") }?.second ?: "tools"
            setStep(failed, false, "失败")
            setStepLog(failed, log.ifBlank { raw }, true)
            status.text = "安装失败，当前步骤日志已展开。"
            setActionEnabled(true)
            action.text = "重试当前安装"
        }
        if (state == "ready") {
            bootstrapActive = false
            status.text = "安装脚本已结束，正在重新检查实际产物……"
            refreshState()
        }
    }

    private fun refreshState() {
        if (!::status.isInitialized) return
        status.visibility = View.VISIBLE
        if (bootstrapActive || artifactChecking) {
            setActionEnabled(false)
            return
        }
        setActionEnabled(true)
        action.setOnClickListener { onAction() }
        if (!AccessGate.isAuthorized(activity)) {
            setProjectBlocked()
            status.text = "尚未完成项目授权，初始化安装功能已锁定。"
            action.text = "前往项目授权"
            action.setOnClickListener { navigate("gate") }
            setActionEnabled(true)
            return
        }
        val bridge = TermuxBridge(activity)
        val installed = bridge.isInstalled()
        val permission = activity.checkSelfPermission(TermuxBridge.RUN_COMMAND_PERMISSION) == PackageManager.PERMISSION_GRANTED
        val wireless = isWirelessDebugEnabled()
        setStepDetail("termux", termuxDetail())
        setStep("termux", installed, if (installed) "已安装" else "待安装")
        setStep("permission", permission, if (permission) "已授权" else "待授权")
        setStep("wireless", wireless, if (wireless) "已开启" else "待开启")
        if (!installed) {
            setProjectBlocked()
            status.text = "项目授权已完成，但还未检测到 Termux，请先下载并安装官方版本。"
            action.text = if (termuxDownloadActive) "正在下载 Termux…" else "下载并安装 Termux"
            action.setOnClickListener { downloadLatestTermux() }
            setActionEnabled(!termuxDownloadActive)
            return
        }
        if (!permission) {
            setProjectBlocked()
            status.text = "项目授权已完成，还需要授予 NKAS 调用 Termux 的外部命令权限。"
            action.text = "授权 Termux 外部命令"
            action.setOnClickListener { onAction() }
            setActionEnabled(true)
            return
        }
        if (!wireless) {
            setProjectBlocked()
            status.text = "项目授权已完成，请先开启 Android 无线调试，完成后再继续项目安装。"
            action.text = "打开无线调试设置"
            action.setOnClickListener { openWirelessSettings() }
            setActionEnabled(true)
            return
        }
        artifactChecking = true
        status.text = "正在检查实际产物，不读取上次保存的状态……"
        setActionEnabled(false)
        BootstrapService(activity).checkArtifacts { result ->
            handler.post {
                artifactChecking = false
                if (bootstrapActive || !visible) return@post
                val output = result.stdout + if (result.stderr.isNotBlank()) "\n[stderr]\n${result.stderr}" else ""
                applyArtifactResults(output, result.exitCode)
            }
        }
    }

    private fun onAction() {
        if (bootstrapActive || artifactChecking || checking || initialNoticeShowing) return
        if (!AccessGate.isAuthorized(activity)) {
            status.text = "使用安装功能前需要先 Star 本项目并完成授权。"
            return
        }
        val bridge = TermuxBridge(activity)
        if (!bridge.isInstalled()) { downloadLatestTermux(); return }
        if (activity.checkSelfPermission(TermuxBridge.RUN_COMMAND_PERMISSION) != PackageManager.PERMISSION_GRANTED) { activity.requestPermissions(arrayOf(TermuxBridge.RUN_COMMAND_PERMISSION), RUN_COMMAND_REQUEST); return }
        if (!isWirelessDebugEnabled()) { openWirelessSettings(); return }
        val prefs = activity.getSharedPreferences(PREFS_NAME, Activity.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_INITIAL_NOTICE_SHOWN, false)) {
            showInitialNotice()
            return
        }
        beginInitializationCheck()
    }

    private fun showInitialNotice() {
        initialNoticeShowing = true
        setActionEnabled(false)
        AlertDialog.Builder(activity)
            .setTitle("安装前提醒")
            .setMessage("安装可能需要较长时间。执行期间请保持 NKAS Mobile 始终在前台，并确保网络连接稳定；切换到其他应用或断网可能导致下载失败。")
            .setNegativeButton("取消") { _, _ ->
                initialNoticeShowing = false
                setActionEnabled(true)
            }
            .setPositiveButton("继续安装") { _, _ ->
                activity.getSharedPreferences(PREFS_NAME, Activity.MODE_PRIVATE).edit().putBoolean(KEY_INITIAL_NOTICE_SHOWN, true).apply()
                initialNoticeShowing = false
                beginInitializationCheck()
            }
            .setOnCancelListener {
                initialNoticeShowing = false
                setActionEnabled(true)
            }
            .show()
    }

    private fun downloadLatestTermux() {
        if (termuxDownloadActive || destroyed || !visible) return
        termuxDownloadActive = true
        action.text = "正在下载 Termux…"
        setActionEnabled(false)
        status.visibility = View.VISIBLE
        setStepLog("termux", "正在获取与你的设备架构匹配的最新 Termux…", true)
        executor.execute {
            try {
                val asset = findTermuxAsset()
                val apk = File(activity.cacheDir, "termux-latest.apk")
                downloadFile(asset.second, apk) { percent ->
                    handler.post {
                        if (visible && termuxDownloadActive) {
                            setStepLog("termux", "正在下载 Termux\n进度：${percent}%", true)
                        }
                    }
                }
                handler.post {
                    if (!visible) return@post
                    termuxDownloadActive = false
                    launchApkInstaller(apk)
                    setStepLog("termux", "Termux 安装包下载完成，请在系统安装确认页完成安装。", true)
                    status.text = "Termux 安装包已下载，请在系统安装确认页完成安装。"
                    action.text = "重新检查"
                    action.setOnClickListener { refreshState() }
                    setActionEnabled(true)
                }
            } catch (error: Exception) {
                Log.e(TAG, "Termux download failed", error)
                handler.post {
                    if (!visible) return@post
                    termuxDownloadActive = false
                    val message = error.message ?: "网络或 Release 资产不可用"
                    setStepLog("termux", "Termux 下载失败：$message", true)
                    status.text = "Termux 下载失败：$message"
                    action.text = "重试下载 Termux"
                    action.setOnClickListener { downloadLatestTermux() }
                    setActionEnabled(true)
                }
            }
        }
    }

    private fun findTermuxAsset(): Pair<String, String> {
        val abi = Build.SUPPORTED_ABIS.firstOrNull()?.lowercase(Locale.ROOT)
            ?: throw IllegalStateException("无法识别设备架构")
        val archTokens = when {
            abi.contains("arm64") || abi.contains("aarch64") -> listOf("arm64-v8a", "aarch64")
            abi.contains("armeabi") || abi == "arm" -> listOf("armeabi-v7a", "arm")
            abi.contains("x86_64") || abi.contains("amd64") -> listOf("x86_64", "amd64")
            abi.contains("x86") -> listOf("x86")
            else -> throw IllegalStateException("Termux 不支持当前设备架构：$abi")
        }
        findLatestAssetFromReleasePage(archTokens.firstOrNull())?.let { return it }
        return findLatestAssetFromApi(abi, archTokens)
    }

    private fun findLatestAssetFromReleasePage(architecture: String?): Pair<String, String>? {
        if (architecture.isNullOrBlank()) return null
        val connection = (URL(TERMUX_RELEASE_PAGE).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 20_000
            instanceFollowRedirects = true
            requestMethod = "GET"
            setRequestProperty("User-Agent", "NKAS-Mobile")
        }
        try {
            if (connection.responseCode !in 200..299) return null
            val tag = Regex("/releases/tag/([^/?#]+)").find(connection.url.toString())?.groupValues?.get(1)
                ?: return null
            val candidates = listOf(
                "termux-app_${tag}+github-debug_${architecture}.apk",
                "termux-app_${tag}+github-debug_universal.apk",
                "termux-app_${tag}+github-release_${architecture}.apk",
                "termux-app_${tag}+github-release_universal.apk",
            )
            for (name in candidates) {
                val url = "https://github.com/termux/termux-app/releases/download/$tag/$name"
                if (isAssetAvailable(url)) return name to url
            }
            return null
        } finally {
            connection.disconnect()
        }
    }

    private fun isAssetAvailable(url: String): Boolean {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 15_000
            instanceFollowRedirects = true
            requestMethod = "HEAD"
            setRequestProperty("User-Agent", "NKAS-Mobile")
        }
        return try {
            connection.responseCode in 200..299
        } finally {
            connection.disconnect()
        }
    }

    private fun findLatestAssetFromApi(abi: String, archTokens: List<String>): Pair<String, String> {
        val connection = (URL(TERMUX_RELEASE_API).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 20_000
            requestMethod = "GET"
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "NKAS-Mobile")
        }
        try {
            if (connection.responseCode !in 200..299) {
                val detail = connection.errorStream?.bufferedReader()?.use { it.readText() }?.take(160).orEmpty()
                throw IllegalStateException("GitHub API 返回 HTTP ${connection.responseCode}${if (detail.isBlank()) "" else "：$detail"}")
            }
            val release = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val assets = release.optJSONArray("assets") ?: throw IllegalStateException("最新 Release 没有可用资产")
            var fallback: Pair<String, String>? = null
            for (index in 0 until assets.length()) {
                val item = assets.optJSONObject(index) ?: continue
                val name = item.optString("name").lowercase(Locale.ROOT)
                val url = item.optString("browser_download_url")
                if (!name.startsWith("termux-app") || !name.endsWith(".apk") || url.isBlank()) continue
                if (archTokens.any { token -> name.contains(token) }) return item.optString("name") to url
                if (!name.contains("source") && !name.contains("debug")) fallback = item.optString("name") to url
            }
            return fallback ?: throw IllegalStateException("最新 Release 没有匹配 $abi 的 Termux APK")
        } finally {
            connection.disconnect()
        }
    }

    private fun downloadFile(url: String, target: File, onProgress: (Int) -> Unit) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            requestMethod = "GET"
            setRequestProperty("User-Agent", "NKAS-Mobile")
        }
        try {
            if (connection.responseCode !in 200..299) {
                val detail = connection.errorStream?.bufferedReader()?.use { it.readText() }?.take(160).orEmpty()
                throw IllegalStateException("下载返回 HTTP ${connection.responseCode}${if (detail.isBlank()) "" else "：$detail"}")
            }
            val total = connection.contentLengthLong
            var received = 0L
            var lastPercent = -1
            target.outputStream().use { output ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(32 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        received += count
                        if (total > 0) {
                            val percent = ((received * 100) / total).toInt()
                            if (percent != lastPercent) { lastPercent = percent; onProgress(percent) }
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun launchApkInstaller(apk: File) {
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }

    private fun beginInitializationCheck() {
        val bridge = TermuxBridge(activity)
        status.text = "正在重新检查实际产物……"
        setActionEnabled(false)
        artifactChecking = true
        bridge.checkArtifacts { check ->
            handler.post {
                artifactChecking = false
                if (!visible) return@post
                val output = check.stdout + if (check.stderr.isNotBlank()) "\n[stderr]\n${check.stderr}" else ""
                applyArtifactResults(output, check.exitCode)
                if (artifactState["termux_setting"] == true && (artifactState["service"] != true || artifactState["config"] != true || SettingsStore.settingsChanged(activity))) startBootstrap()
            }
        }
    }

    private fun isWirelessDebugEnabled(): Boolean = try {
        android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R && Settings.Global.getInt(activity.contentResolver, "adb_wifi_enabled", 0) == 1
    } catch (_: Settings.SettingNotFoundException) {
        false
    }

    private fun openWirelessSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
        runCatching { activity.startActivity(intent) }.onFailure { activity.startActivity(Intent(Settings.ACTION_SETTINGS)) }
    }

    private fun setProjectBlocked() {
        listOf("adb_device", "tools", "source", "config", "container", "service").forEach { key ->
            setStep(key, false, "等待环境")
        }
    }

    private fun setActionEnabled(enabled: Boolean) {
        action.isEnabled = enabled
        // 与 Web 的 .btn:disabled 一致：保留主按钮样式，仅用透明度表达禁用
        Ui.stylePrimary(activity, action, 12)
        action.alpha = if (enabled) 1f else 0.4f
    }

    private fun startBootstrap() {
        status.text = "正在恢复安装，日志会显示在当前步骤中……"; setActionEnabled(false); bootstrapActive = true; bootstrapStageIndex = -1; setStepLog("tools", "正在请求 Termux 恢复安装脚本……", true)
        val result = BootstrapService(activity).start { result ->
            handler.post {
                if (!visible) return@post
                if (result.exitCode != 0) {
                    val output = result.stdout + "\n" + result.stderr
                    if (result.exitCode == -2) {
                        status.text = "安装仍在执行，当前步骤日志会持续更新……"
                        action.text = "安装中"
                        setActionEnabled(false)
                        pollLog()
                        return@post
                    }
                    if (output.contains("bootstrap already running")) {
                        status.text = "已有安装任务正在执行，继续等待其完成……"
                        action.text = "安装中"
                        setActionEnabled(false)
                        pollLog()
                        return@post
                    }
                    bootstrapActive = false
                    status.text = "Termux 命令返回失败，详见日志。"
                    setActionEnabled(true)
                    action.text = "重试安装"
                    pollLogOnce()
                }
            }
        }
        if (result.isFailure) {
            status.text = "Termux 拒绝了外部命令。请确认已设置 allow-external-apps=true，并重启 Termux。"
            setActionEnabled(true)
            setStep("termux_setting", false, "待设置")
            setStep("tools", false, "未执行")
            return
        }
        handler.postDelayed({ pollBackend() }, 1800)
        handler.postDelayed({ pollLog() }, 700)
    }

    private fun pollBackend() {
        if (destroyed || !visible || checking) return
        checking = true
        executor.execute {
            val ready = try { (URL(SettingsStore.webUiApiUrl(activity, "/api/system/status")).openConnection() as HttpURLConnection).apply { connectTimeout = 1500; readTimeout = 1500; requestMethod = "GET" }.responseCode == 200 } catch (_: Exception) { false }
            handler.post {
                if (destroyed || !visible) return@post
                checking = false
                if (ready) {
                    if (bootstrapActive) {
                        status.text = "Web UI 已响应，等待安装脚本完成最后检查……"
                        handler.postDelayed({ pollBackend() }, 3500)
                    } else {
                        bootstrapActive = false
                        refreshState()
                    }
                } else if (bootstrapActive) {
                    status.text = "安装仍在执行，当前步骤日志会持续更新……"
                    handler.postDelayed({ pollBackend() }, 3500)
                } else {
                    status.text = "服务尚未就绪，请展开失败步骤查看日志后重试。"
                    action.text = "重试安装"
                    setActionEnabled(true)
                    handler.postDelayed({ pollBackend() }, 3500)
                }
            }
        }
    }

    private fun pollLogOnce() {
        BootstrapService(activity).readLog { result -> handler.post { if (visible) applyBootstrapLog(result.stdout + if (result.stderr.isNotBlank()) "\n[stderr]\n${result.stderr}" else "") } }
    }

    private fun pollLog() {
        if (destroyed || !visible || !bootstrapActive) return
        BootstrapService(activity).readLog { result ->
            handler.post {
                if (!visible) return@post
                applyBootstrapLog(result.stdout + if (result.stderr.isNotBlank()) "\n[stderr]\n${result.stderr}" else "")
                if (bootstrapActive && !destroyed && visible) handler.postDelayed({ pollLog() }, 1400)
            }
        }
    }

    private fun applyArtifactResults(raw: String, exitCode: Int) {
        val values = raw.lineSequence()
            .mapNotNull { line -> line.trim().split('=', limit = 2).takeIf { it.size == 2 } }
            .associate { it[0] to (it[1] == "yes") }
        val expectedKeys = setOf("termux_setting", "adb_device", "tools", "source", "config", "container", "service")
        if (exitCode != 0 || !values.keys.containsAll(expectedKeys)) {
            val externalAppsRejected = raw.contains("allow-external-apps", ignoreCase = true) && exitCode != -2
            setProjectBlocked()
            if (externalAppsRejected) {
                setStep("termux_setting", false, "待设置")
                status.text = "Termux 拒绝了外部命令，请执行上方命令并完全重启 Termux。"
                action.text = "等待 Termux 设置"
                setActionEnabled(false)
            } else {
                setStep("termux_setting", false, "检查失败")
                status.text = "Termux 外部命令服务暂时未返回，配置并未被判定为失效，请稍后重新检查。"
                action.text = "重新检查"
                action.setOnClickListener { refreshState() }
                setActionEnabled(true)
            }
            return
        }
        artifactState.clear()
        artifactState.putAll(values)
        val detectedSerial = raw.lineSequence().firstOrNull { it.startsWith("adb_serial=") }
            ?.substringAfter('=')?.trim().orEmpty()
        if (detectedSerial.isNotBlank() && detectedSerial != "auto" && SettingsStore.serial(activity).isBlank()) {
            serialInput?.setText(detectedSerial)
        }
        val setting = values["termux_setting"] == true
        val adbDeviceReady = values["adb_device"] == true
        val toolsReady = values["tools"] == true
        val sourceReady = values["source"] == true
        val configReady = values["config"] == true
        val containerReady = values["container"] == true
        val serviceReady = values["service"] == true
        val wirelessReady = isWirelessDebugEnabled()
        setStep("termux_setting", setting, if (setting) "已检测" else "待设置")
        setStep("wireless", wirelessReady, if (wirelessReady) "已开启" else "待开启")
        setStep("adb_device", adbDeviceReady, if (adbDeviceReady) "已连接" else "待连接")
        setStep("tools", toolsReady, if (toolsReady) "已检测" else "待安装")
        setStep("source", sourceReady, if (sourceReady) "已检测" else "待下载")
        setStep("config", configReady, if (configReady) "已检测" else "待配置")
        setStep("container", containerReady, if (containerReady) "已检测" else "待安装")
        setStep("service", serviceReady, if (serviceReady) "运行中" else "未运行")
        when {
            !wirelessReady -> { status.text = "请先开启 Android 无线调试，环境准备完成后才能安装项目。"; action.text = "打开无线调试设置"; action.setOnClickListener { openWirelessSettings() }; setActionEnabled(false) }
            !setting -> {
                status.text = "未检测到 Termux 的 allow-external-apps=true，请执行上方命令并重启 Termux。"
                action.text = "等待 Termux 设置"
                setActionEnabled(false)
            }
            !toolsReady -> {
                status.text = "Termux 工具尚未安装，先安装 ADB、Git、curl 等环境工具。"
                action.text = "开始安装"
                action.setOnClickListener { onAction() }
                setActionEnabled(true)
            }
            !adbDeviceReady -> { status.text = "Termux 尚未连接已授权的 ADB 设备，请先完成无线调试配对；也可以在上方填写 Serial。"; action.text = "等待 ADB 设备"; setActionEnabled(false) }
            !configReady -> { status.text = "需要安装并应用 Android 设备配置。"; action.text = "开始安装"; action.setOnClickListener { onAction() } }
            serviceReady && SettingsStore.settingsChanged(activity) -> { status.text = "设置已变更，需要重新应用后才能启动服务。"; action.text = "应用设置并重启"; action.setOnClickListener { onAction() } }
            serviceReady -> { SettingsStore.markApplied(activity); status.text = "已检测到 NKAS Web UI 服务，可以打开 UI。"; action.text = "打开 NKAS UI"; action.setOnClickListener { navigate("ui") } }
            else -> { status.text = ""; action.text = "开始安装"; action.setOnClickListener { onAction() } }
        }
        setActionEnabled(wirelessReady && setting && adbDeviceReady)
    }

    private fun rounded(color: Int, radius: Int) = Ui.rounded(activity, color, radius)
    private fun dp(v: Int) = Ui.dp(activity, v)
    companion object {
        private const val TAG = "NkasSetupPage"
        private const val TERMUX_RELEASE_PAGE = "https://github.com/termux/termux-app/releases/latest"
        private const val TERMUX_RELEASE_API = "https://api.github.com/repos/termux/termux-app/releases/latest"
        private const val RUN_COMMAND_REQUEST = 1001
        private const val PREFS_NAME = "nkas_state"
        private const val KEY_INITIAL_NOTICE_SHOWN = "initial_notice_shown"
    }
}
