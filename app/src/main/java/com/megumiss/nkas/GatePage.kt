package com.megumiss.nkas

import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.view.Gravity
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

/** Star 验证页：由 GateActivity 迁移为单 Activity 内的页面渲染器。 */
class GatePage(private val activity: Activity, private val navigate: (String) -> Unit) {
    private lateinit var content: LinearLayout
    private lateinit var status: TextView
    private lateinit var action: Button

    fun show(container: FrameLayout) {
        val scroll = ScrollView(activity).apply { isFillViewport = true; setBackgroundColor(Ui.bg) }
        content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(42), dp(24), dp(32))
        }
        scroll.addView(content)
        container.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        renderCurrent()
    }

    private fun renderCurrent() {
        AccessGate.storedLicense(activity)?.let(::renderAuthorized) ?: renderWaiting()
    }

    private fun renderWaiting() {
        content.removeAllViews()
        val panel = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(26), dp(24), dp(24))
            background = Ui.rounded(activity, Ui.card, 12)
        }
        panel.addView(ImageView(activity).apply {
            setImageResource(R.mipmap.ic_launcher)
            contentDescription = activity.getString(R.string.app_name)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
        }, LinearLayout.LayoutParams(-1, dp(72)))
        panel.addView(TextView(activity).apply {
            text = "Star 验证"
            textSize = 24f
            setTextColor(Ui.text)
            setTypeface(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, dp(8))
        })
        panel.addView(TextView(activity).apply {
            text = "使用 NKAS 前需要 Star 本项目，感谢你的支持。"
            textSize = 14f
            setTextColor(Ui.text2)
            gravity = Gravity.CENTER
        })
        panel.addView(TextView(activity).apply {
            text = "megumiss/NIKKEAutoScript"
            textSize = 15f
            setTextColor(Ui.accent)
            gravity = Gravity.CENTER
            setPadding(0, dp(18), 0, dp(18))
        })
        status = TextView(activity).apply { textSize = 13f; setTextColor(Ui.text2); gravity = Gravity.CENTER; setPadding(0, dp(8), 0, dp(12)) }
        panel.addView(status)
        action = Button(activity).apply {
            text = "前往 GitHub 验证 Star"
            textSize = 14f
            Ui.stylePrimary(activity, this)
            setOnClickListener { beginAuthorization() }
        }
        panel.addView(action, LinearLayout.LayoutParams(-1, dp(50)))
        val openRepository = Button(activity).apply {
            text = "打开项目仓库"
            textSize = 13f
            Ui.styleSecondary(activity, this)
            setOnClickListener { openExternal(GateConfig.REPOSITORY_URL) }
        }
        panel.addView(openRepository, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(10) })
        content.addView(panel, LinearLayout.LayoutParams(-1, -2))
        status.text = "尚未验证 Star"
    }

    private fun renderAuthorized(license: AccessGate.License) {
        content.removeAllViews()
        val panel = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(26), dp(24), dp(24)); background = Ui.rounded(activity, Ui.card, 12) }
        panel.addView(ImageView(activity).apply { setImageResource(R.mipmap.ic_launcher); contentDescription = activity.getString(R.string.app_name); scaleType = ImageView.ScaleType.CENTER_INSIDE }, LinearLayout.LayoutParams(-1, dp(72)))
        panel.addView(TextView(activity).apply { text = "Star 验证已通过"; textSize = 24f; setTextColor(Ui.text); setTypeface(Typeface.DEFAULT, Typeface.BOLD); gravity = Gravity.CENTER; setPadding(0, dp(16), 0, dp(8)) })
        panel.addView(TextView(activity).apply { text = "GitHub 账号：${license.username}\n验证有效期至：${formatDate(license.expiresAt)}"; textSize = 14f; setTextColor(Ui.text2); gravity = Gravity.CENTER; setPadding(0, dp(8), 0, dp(20)) })
        panel.addView(TextView(activity).apply { text = "✓ 已确认 Star megumiss/NIKKEAutoScript"; textSize = 14f; setTextColor(Ui.green); gravity = Gravity.CENTER; setPadding(0, 0, 0, dp(18)) })
        val openSetup = Button(activity).apply { text = "打开初始化"; textSize = 14f; Ui.stylePrimary(activity, this); setOnClickListener { navigate("setup") } }
        panel.addView(openSetup, LinearLayout.LayoutParams(-1, dp(50)))
        val refresh = Button(activity).apply { text = "重新验证 Star"; textSize = 13f; Ui.styleSecondary(activity, this); setOnClickListener { beginAuthorization() } }
        panel.addView(refresh, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(10) })
        content.addView(panel, LinearLayout.LayoutParams(-1, -2))
    }

    /** 处理 nkas://auth 验证回调；非回调 Intent 时按本地验证状态渲染。 */
    fun handleIntent(intent: Intent?) {
        val data = intent?.data ?: run {
            renderCurrent()
            return
        }
        if (data.scheme != "nkas" || data.host != "auth") return
        val state = data.getQueryParameter("state")
        if (!AccessGate.consumeOAuthState(activity, state)) {
            showError("验证回调无效，请重新验证")
            return
        }
        val token = data.getQueryParameter("key")
        data.getQueryParameter("error")?.let { errorCode ->
            showError(
                when (errorCode) {
                    "repository_not_starred" -> "当前 GitHub 账号尚未 Star 项目，请完成 Star 后重试"
                    "oauth_cancelled" -> "GitHub 验证已取消"
                    "oauth_not_configured" -> "Star 验证服务尚未配置，请联系项目维护者"
                    else -> "GitHub 验证失败，请稍后重试"
                },
            )
            return
        }
        val license = token?.let { AccessGate.saveLicense(activity, it) }
        if (license != null) renderAuthorized(license) else showError("验证密钥无效或已过期，请重新验证")
    }

    private fun beginAuthorization() {
        val state = UUID.randomUUID().toString()
        AccessGate.saveOAuthState(activity, state)
        action.isEnabled = false
        status.text = "正在打开 GitHub 验证页面…"
        runCatching { openExternal(GateConfig.authorizationUrl(state).toString()) }
            .onFailure { action.isEnabled = true; showError("无法打开浏览器，请检查系统浏览器") }
    }

    private fun showError(message: String) {
        if (!::status.isInitialized) return
        status.text = message
        status.setTextColor(Ui.red)
        if (::action.isInitialized) action.isEnabled = true
    }

    private fun openExternal(url: String) = activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    private fun formatDate(epoch: Long) = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneId.systemDefault()).format(Instant.ofEpochSecond(epoch))
    private fun dp(value: Int) = Ui.dp(activity, value)
}
