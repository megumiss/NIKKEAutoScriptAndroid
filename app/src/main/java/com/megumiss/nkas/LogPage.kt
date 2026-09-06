package com.megumiss.nkas

import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** 日志页：应用事件日志（LogStore）+ Termux 侧安装/服务日志。 */
class LogPage(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var scroll: ScrollView
    private lateinit var logView: TextView

    fun show(container: FrameLayout) {
        val root = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Ui.bg) }
        val header = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL }
        val titles = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        titles.addView(TextView(activity).apply { text = "日志"; textSize = 26f; setTextColor(Ui.text); setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        titles.addView(TextView(activity).apply { text = "初始化与应用事件记录"; textSize = 14f; setTextColor(Ui.text2); setPadding(0, Ui.dp(activity, 6), 0, 0) })
        header.addView(titles, LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(Button(activity).apply {
            text = "刷新"
            textSize = 12f
            Ui.styleSecondary(activity, this)
            setOnClickListener { reload() }
        }, LinearLayout.LayoutParams(-2, Ui.dp(activity, 40)))
        root.addView(header, LinearLayout.LayoutParams(-1, -2).apply {
            setMargins(Ui.dp(activity, 24), Ui.dp(activity, 24), Ui.dp(activity, 24), Ui.dp(activity, 12))
        })
        logView = TextView(activity).apply {
            textSize = 11f
            setTextColor(Ui.text2)
            typeface = Typeface.MONOSPACE
            setTextIsSelectable(true)
            setPadding(Ui.dp(activity, 16), Ui.dp(activity, 12), Ui.dp(activity, 16), Ui.dp(activity, 24))
        }
        scroll = ScrollView(activity).apply { addView(logView) }
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        container.addView(root, FrameLayout.LayoutParams(-1, -1))
        reload()
    }

    private fun reload() {
        val appLog = "── 应用事件 ──\n" + LogStore.text().ifBlank { "暂无" }
        logView.text = appLog
        val bridge = TermuxBridge(activity)
        if (!bridge.isInstalled() ||
            activity.checkSelfPermission(TermuxBridge.RUN_COMMAND_PERMISSION) != PackageManager.PERMISSION_GRANTED
        ) {
            logView.text = appLog + "\n\n── Termux 日志 ──\n（Termux 未安装或未授予外部命令权限，暂无法读取）"
            return
        }
        logView.text = appLog + "\n\n── Termux 日志 ──\n读取中……"
        bridge.readFullLogs { result ->
            handler.post {
                val output = result.stdout.trim()
                logView.text = appLog + "\n\n── Termux 日志 ──\n" +
                    if (result.exitCode == 0 && output.isNotBlank()) output else "读取失败或暂无日志"
                scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
            }
        }
    }
}
