package com.megumiss.nkas

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.widget.Button

/**
 * 与 Web UI 浅色主题对齐的设计令牌（来源：webui/src/styles/base.css 的 :root 变量）。
 * 原生页面统一从这里取色，避免各 Activity 各自硬编码导致风格漂移。
 */
object Ui {
    val bg = Color.rgb(0xEE, 0xF1, 0xF6)
    val card = Color.WHITE
    val card2 = Color.rgb(0xF5, 0xF7, 0xFB)
    val card3 = Color.rgb(0xE6, 0xEB, 0xF3)
    val border = Color.rgb(0xDD, 0xE3, 0xEC)
    val borderLight = Color.rgb(0xC2, 0xCD, 0xDC)
    val text = Color.rgb(0x21, 0x26, 0x2E)
    val text2 = Color.rgb(0x5F, 0x6A, 0x78)
    val text3 = Color.rgb(0x97, 0xA1, 0xAF)
    val accent = Color.rgb(0x2F, 0x8F, 0xD0)
    val accentSoft = Color.argb(26, 0x2F, 0x8F, 0xD0)
    // accentSoft 叠在白卡上的等效不透明色，用于悬浮按钮等底下有滚动内容的场景
    val accentSoftSolid = Color.rgb(0xEA, 0xF4, 0xFA)
    val accentBorder = Color.argb(122, 0x2F, 0x8F, 0xD0)
    val green = Color.rgb(0x1C, 0xAB, 0x72)
    val greenSoft = Color.argb(26, 0x1C, 0xAB, 0x72)
    val yellow = Color.rgb(0xBD, 0x7A, 0x18)
    val red = Color.rgb(0xD3, 0x45, 0x45)

    fun dp(context: Context, value: Int) = (value * context.resources.displayMetrics.density + 0.5f).toInt()

    fun rounded(context: Context, color: Int, radiusDp: Int, strokeColor: Int? = border): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(context, radiusDp).toFloat()
            strokeColor?.let { setStroke(dp(context, 1), it) }
        }

    /** 对应 Web 的 .btn.primary：浅 accent 底 + accent 加粗文字。 */
    fun stylePrimary(context: Context, button: Button, radiusDp: Int = 10) {
        button.isAllCaps = false
        button.setTextColor(accent)
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD)
        button.background = ripple(context, rounded(context, accentSoftSolid, radiusDp, accentBorder), radiusDp, Color.argb(56, 0x2F, 0x8F, 0xD0))
    }

    /** 对应 Web 的 .btn：中性底 + 细边框，hover 时才转 accent。 */
    fun styleSecondary(context: Context, button: Button, radiusDp: Int = 10) {
        button.isAllCaps = false
        button.setTextColor(text)
        button.background = ripple(context, rounded(context, card3, radiusDp, borderLight), radiusDp, Color.argb(31, 0x2F, 0x8F, 0xD0))
    }

    private fun ripple(context: Context, content: GradientDrawable, radiusDp: Int, color: Int): RippleDrawable {
        val mask = GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = dp(context, radiusDp).toFloat() }
        return RippleDrawable(ColorStateList.valueOf(color), content, mask)
    }
}
