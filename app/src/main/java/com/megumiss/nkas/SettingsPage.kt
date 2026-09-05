package com.megumiss.nkas

import android.app.Activity
import android.graphics.Typeface
import android.view.Gravity
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView

/** 设置页：由 SettingsActivity 迁移为单 Activity 内的页面渲染器。 */
class SettingsPage(private val activity: Activity) {
    private lateinit var content: LinearLayout
    private lateinit var aptSpinner: Spinner
    private lateinit var repositorySpinner: Spinner
    private lateinit var dockerInput: EditText
    private lateinit var webUiInput: EditText
    private lateinit var status: TextView

    fun show(container: FrameLayout) {
        val scroll = ScrollView(activity).apply { isFillViewport = true }
        content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(24), dp(24), dp(28)) }
        scroll.addView(content)
        container.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        render()
    }

    private fun render() {
        content.removeAllViews()
        heading("设置", "选择初始化时使用的下载源和项目仓库")
        sourceLabel("WebUI 地址", "应用、初始化检查和 Termux 服务统一使用此地址")
        webUiInput = EditText(activity).apply {
            setText(SettingsStore.webUiUrl(activity))
            setTextColor(Ui.text)
            setHintTextColor(Ui.text2)
            textSize = 14f
            setSingleLine(true)
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
            setPadding(dp(12), 0, dp(12), 0)
            background = rounded(Ui.card, 8)
        }
        content.addView(webUiInput, LinearLayout.LayoutParams(-1, dp(50)).apply { bottomMargin = dp(18) })
        sourceLabel("项目仓库", "用于下载和更新 NIKKEAutoScript，默认使用国内项目镜像")
        repositorySpinner = spinner(SettingsStore.repositorySources)
        repositorySpinner.setSelection(SettingsStore.repositorySources.indexOfFirst { it.value == SettingsStore.repository(activity) }.coerceAtLeast(0))
        val repositoryBox = FrameLayout(activity).apply { background = rounded(Ui.card, 8) }
        repositoryBox.addView(repositorySpinner, FrameLayout.LayoutParams(-1, dp(50)))
        repositoryBox.addView(ImageView(activity).apply { setImageResource(R.drawable.ic_arrow_drop_down); setColorFilter(Ui.text2) }, FrameLayout.LayoutParams(dp(24), dp(24), Gravity.END or Gravity.CENTER_VERTICAL).apply { rightMargin = dp(12) })
        content.addView(repositoryBox, LinearLayout.LayoutParams(-1, dp(50)).apply { bottomMargin = dp(18) })
        sourceLabel("Termux apt 源", "用于安装 Termux 工具，默认使用国内清华源")
        aptSpinner = spinner(SettingsStore.aptSources)
        aptSpinner.setSelection(SettingsStore.aptSources.indexOfFirst { it.value == SettingsStore.aptSource(activity) }.coerceAtLeast(0))
        // Spinner 默认背景与卡片风格不统一，这里用包装布局提供卡片底，Spinner 自身只留文字和箭头
        val spinnerBox = FrameLayout(activity).apply { background = rounded(Ui.card, 8) }
        spinnerBox.addView(aptSpinner, FrameLayout.LayoutParams(-1, dp(50)))
        spinnerBox.addView(ImageView(activity).apply { setImageResource(R.drawable.ic_arrow_drop_down); setColorFilter(Ui.text2) }, FrameLayout.LayoutParams(dp(24), dp(24), Gravity.END or Gravity.CENTER_VERTICAL).apply { rightMargin = dp(12) })
        content.addView(spinnerBox, LinearLayout.LayoutParams(-1, dp(50)).apply { bottomMargin = dp(18) })
        sourceLabel("Docker 镜像", "用于安装 NKAS 容器，默认使用毫秒镜像 docker.1ms.run")
        dockerInput = EditText(activity).apply {
            setText(SettingsStore.dockerImage(activity))
            setTextColor(Ui.text)
            setHintTextColor(Ui.text2)
            textSize = 14f
            setSingleLine(true)
            inputType = android.text.InputType.TYPE_CLASS_TEXT
            setPadding(dp(12), 0, dp(12), 0)
            background = rounded(Ui.card, 8)
        }
        content.addView(dockerInput, LinearLayout.LayoutParams(-1, dp(50)).apply { bottomMargin = dp(22) })
        val save = Button(activity).apply {
            text = "保存设置"
            textSize = 14f
            Ui.stylePrimary(activity, this)
            setOnClickListener { saveSettings() }
        }
        content.addView(save, LinearLayout.LayoutParams(-1, dp(48)))
        status = TextView(activity).apply { textSize = 13f; setTextColor(Ui.text2); setPadding(0, dp(14), 0, 0) }
        content.addView(status)
    }

    private fun sourceLabel(title: String, detail: String) {
        content.addView(TextView(activity).apply {
            text = title
            textSize = 15f
            setTextColor(Ui.text)
            setTypeface(Typeface.DEFAULT, Typeface.BOLD)
        })
        content.addView(TextView(activity).apply {
            text = detail
            textSize = 12f
            setTextColor(Ui.text2)
            setPadding(0, dp(4), 0, dp(8))
        })
    }

    private fun spinner(options: List<SourceChoice>): Spinner {
        val spinner = Spinner(activity)
        val adapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, options.map { it.label }).apply {
            setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        }
        spinner.adapter = adapter
        spinner.setPadding(dp(12), 0, dp(40), 0)
        spinner.background = null
        return spinner
    }

    private fun saveSettings() {
        val apt = SettingsStore.aptSources[aptSpinner.selectedItemPosition].value
        val repository = SettingsStore.repositorySources[repositorySpinner.selectedItemPosition].value
        val docker = dockerInput.text.toString().trim()
        val webUi = SettingsStore.normalizeWebUiUrl(webUiInput.text.toString())
        if (webUi == null) {
            status.text = "WebUI 地址格式不正确，例如：http://127.0.0.1:12271"
            webUiInput.requestFocus()
            return
        }
        if (!docker.matches(Regex("[A-Za-z0-9._/-]+:[A-Za-z0-9._-]+"))) {
            status.text = "Docker 镜像格式不正确，例如：docker.1ms.run/megumiss/nkas:latest"
            return
        }
        activity.getSharedPreferences(SettingsStore.PREFS_NAME, Activity.MODE_PRIVATE).edit()
            .putString("apt_source", apt)
            .putString("repository", repository)
            .putString("docker_image", docker)
            .putString("webui_url", webUi)
            .putBoolean("settings_changed", true)
            .apply()
        status.text = "已保存。下次安装或重试时将应用新的地址、仓库和源。"
    }

    private fun heading(main: String, sub: String) {
        content.addView(TextView(activity).apply { text = main; textSize = 26f; setTextColor(Ui.text); setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        content.addView(TextView(activity).apply { text = sub; textSize = 14f; setTextColor(Ui.text2); setPadding(0, dp(6), 0, dp(22)) })
    }

    private fun rounded(color: Int, radius: Int) = Ui.rounded(activity, color, radius)
    private fun dp(value: Int) = Ui.dp(activity, value)
}
