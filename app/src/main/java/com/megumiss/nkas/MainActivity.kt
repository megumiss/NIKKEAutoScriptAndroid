package com.megumiss.nkas

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * 应用唯一 Activity：5 个页面（授权/初始化/UI/设置/关于）均为 content 切换，
 * 避免多 Activity 互跳造成的返回栈不一致与页面重建开销。
 */
class MainActivity : Activity() {
    private lateinit var shell: DrawerShell.Built
    private lateinit var gatePage: GatePage
    private lateinit var setupPage: SetupPage
    private lateinit var settingsPage: SettingsPage
    private lateinit var uiPage: UiPage
    private var currentPage = ""
    private var notificationsStarted = false

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.statusBarColor = Ui.bg
        window.navigationBarColor = Ui.bg
        shell = DrawerShell.build(this, ::navigate)
        setContentView(shell.root)
        gatePage = GatePage(this, ::navigate)
        setupPage = SetupPage(this, ::navigate)
        settingsPage = SettingsPage(this)
        uiPage = UiPage(this)
        navigate("gate")
        gatePage.handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (currentPage != "gate") navigate("gate")
        gatePage.handleIntent(intent)
    }

    private fun navigate(key: String) {
        if (key == "setup" && !notificationsStarted) {
            notificationsStarted = true
            startInstanceNotifications()
        }
        if (currentPage == "setup" && key != "setup") setupPage.hide()
        currentPage = key
        shell.select(key)
        shell.content.removeAllViews()
        when (key) {
            "gate" -> gatePage.show(shell.content)
            "setup" -> setupPage.show(shell.content)
            "ui" -> uiPage.show(shell.content)
            "settings" -> settingsPage.show(shell.content)
            "about" -> renderAbout()
        }
    }

    private fun renderAbout() {
        val scroll = ScrollView(this).apply { isFillViewport = true }
        val content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(24), dp(24), dp(28)) }
        scroll.addView(content)
        val appVersion = runCatching { packageManager.getPackageInfo(packageName, 0).versionName ?: "未知" }.getOrDefault("未知")
        content.addView(TextView(this).apply { text = "关于 NKAS Mobile"; textSize = 26f; setTextColor(Ui.text); setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        content.addView(TextView(this).apply { text = "NIKKEAutoScript 的 Android 控制端"; textSize = 14f; setTextColor(Ui.text2); setPadding(0, dp(6), 0, dp(20)) })
        val aboutText = "NKAS 是一款免费开源软件，如果你在任何渠道付费购买了 NKAS，请退款。\n\n" +
            "项目\n" +
            "项目地址：https://github.com/megumiss/NIKKEAutoScript\n" +
            "详细指南：https://github.com/megumiss/NIKKEAutoScript/wiki\n\n" +
            "寻求帮助\n" +
            "如果在使用过程中遇到问题，您可以通过以下方式获取帮助：\n" +
            "提交问题：https://github.com/megumiss/NIKKEAutoScript/issues\n" +
            "划水 QQ 群：823265807\n\n" +
            "支持项目\n" +
            "如果喜欢本项目，可以送作者一杯蜜雪冰城。\n" +
            "您的支持就是作者开发和维护项目的动力。\n\n" +
            "使用风险与免责声明\n" +
            "NKAS 是一款基于截图与模拟输入的自动化工具。使用此类工具可能违反游戏用户协议，可能导致账号受到处罚（包括但不限于警告、限制或封禁）。使用 NKAS 即表示您已知晓并自行承担上述风险；因使用本软件造成的任何损失，作者概不负责。\n\n" +
            "版本：${appVersion}"
        content.addView(TextView(this).apply { text = aboutText; textSize = 14f; setTextColor(Ui.text2); setPadding(dp(16), dp(16), dp(16), dp(16)); background = Ui.rounded(this@MainActivity, Ui.card, 10) })
        shell.content.addView(scroll, android.widget.FrameLayout.LayoutParams(-1, -1))
    }

    private fun startInstanceNotifications() {
        InstanceNotificationService.start(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), NOTIFICATION_REQUEST)
        }
    }

    override fun onResume() {
        super.onResume()
        if (currentPage == "setup") setupPage.onResume()
    }

    override fun onBackPressed() {
        if (currentPage == "ui" && uiPage.goBack()) return
        if (currentPage != "gate") {
            navigate("gate")
            return
        }
        super.onBackPressed()
    }

    override fun onDestroy() {
        setupPage.destroy()
        uiPage.destroy()
        super.onDestroy()
    }

    private fun dp(value: Int) = Ui.dp(this, value)
    companion object {
        private const val NOTIFICATION_REQUEST = 1002
    }
}
