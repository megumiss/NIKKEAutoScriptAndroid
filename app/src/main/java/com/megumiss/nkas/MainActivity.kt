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
        content.addView(TextView(this).apply { text = "关于 NKAS Mobile"; textSize = 26f; setTextColor(Ui.text); setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        content.addView(TextView(this).apply { text = "NIKKEAutoScript 的 Android 控制端"; textSize = 14f; setTextColor(Ui.text2); setPadding(0, dp(6), 0, dp(20)) })
        content.addView(TextView(this).apply { text = "应用负责初始化 Termux 环境，并通过本地 Web UI 管理 NKAS。\n\n包名：com.megumiss.nkas.mobile\n版本：0.2.9\n\n不会自动启动 NIKKE 游戏。"; textSize = 14f; setTextColor(Ui.text2); setPadding(dp(16), dp(16), dp(16), dp(16)); background = Ui.rounded(this@MainActivity, Ui.card, 10) })
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
