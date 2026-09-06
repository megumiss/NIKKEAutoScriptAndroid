package com.megumiss.nkas

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.drawerlayout.widget.DrawerLayout

object DrawerShell {
    data class Built(val root: DrawerLayout, val content: FrameLayout, val select: (String) -> Unit)

    fun build(activity: Activity, onNavigate: (String) -> Unit): Built {
        val drawer = DrawerLayout(activity)
        drawer.setBackgroundColor(Ui.bg)
        val main = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Ui.bg) }
        val toolbar = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(activity, 4), 0, dp(activity, 16), 0); setBackgroundColor(Ui.card) }
        val menu = ImageButton(activity).apply { setImageResource(R.drawable.ic_menu); setColorFilter(Ui.text2); setBackgroundColor(Color.TRANSPARENT); contentDescription = "打开导航"; setOnClickListener { drawer.openDrawer(Gravity.LEFT) } }
        toolbar.addView(menu, LinearLayout.LayoutParams(dp(activity, 48), dp(activity, 48)))
        toolbar.addView(brandLogo(activity), LinearLayout.LayoutParams(dp(activity, 26), dp(activity, 26)))
        toolbar.addView(TextView(activity).apply { text = "NKAS Mobile"; textSize = 16f; setTextColor(Ui.text); setTypeface(Typeface.DEFAULT, Typeface.BOLD) }, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(activity, 10) })
        val divider = View(activity).apply { setBackgroundColor(Ui.border) }
        val content = FrameLayout(activity)
        main.addView(toolbar, LinearLayout.LayoutParams(-1, dp(activity, 56)))
        main.addView(divider, LinearLayout.LayoutParams(-1, dp(activity, 1)))
        main.addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
        drawer.addView(main, DrawerLayout.LayoutParams(-1, -1))

        val panel = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(activity, 12), dp(activity, 24), dp(activity, 12), dp(activity, 16)); setBackgroundColor(Ui.card) }
        val header = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(activity, 8), 0, 0, dp(activity, 20)) }
        header.addView(brandLogo(activity), LinearLayout.LayoutParams(dp(activity, 40), dp(activity, 40)))
        val headerLabels = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        headerLabels.addView(TextView(activity).apply { text = "NKAS Mobile"; textSize = 17f; setTextColor(Ui.text); setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        headerLabels.addView(TextView(activity).apply { text = "NIKKEAutoScript 控制端"; textSize = 12f; setTextColor(Ui.text3); setPadding(0, dp(activity, 2), 0, 0) })
        header.addView(headerLabels, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = dp(activity, 12) })
        panel.addView(header)

        val items = mutableMapOf<String, TextView>()
        listOf("Star 验证" to "gate", "初始化" to "setup", "NKAS UI" to "ui", "设置" to "settings", "日志" to "log", "关于" to "about").forEach { (label, key) ->
            val item = TextView(activity).apply {
                text = label
                textSize = 15f
                setPadding(dp(activity, 14), dp(activity, 13), 0, dp(activity, 13))
                setOnClickListener { drawer.closeDrawer(Gravity.LEFT); onNavigate(key) }
            }
            items[key] = item
            panel.addView(item, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(activity, 2) })
        }
        drawer.addDrawerListener(object : DrawerLayout.SimpleDrawerListener() {})
        val params = DrawerLayout.LayoutParams(dp(activity, 280), -1).apply { gravity = Gravity.LEFT }
        drawer.addView(panel, params)
        return Built(drawer, content) { selected -> items.forEach { (key, view) -> styleItem(activity, view, key == selected) } }
    }

    private fun styleItem(activity: Activity, view: TextView, active: Boolean) {
        view.setTextColor(if (active) Ui.accent else Ui.text2)
        view.setTypeface(Typeface.DEFAULT, if (active) Typeface.BOLD else Typeface.NORMAL)
        val fill = GradientDrawable().apply { setColor(if (active) Ui.accentSoft else Color.TRANSPARENT); cornerRadius = dp(activity, 10).toFloat() }
        val mask = GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = dp(activity, 10).toFloat() }
        view.background = RippleDrawable(ColorStateList.valueOf(Ui.accentSoft), fill, mask)
    }

    private fun brandLogo(activity: Activity) = ImageView(activity).apply {
        setImageResource(R.drawable.ic_brand)
        contentDescription = activity.getString(R.string.app_name)
        scaleType = ImageView.ScaleType.FIT_CENTER
    }

    private fun dp(activity: Activity, value: Int) = Ui.dp(activity, value)
}
