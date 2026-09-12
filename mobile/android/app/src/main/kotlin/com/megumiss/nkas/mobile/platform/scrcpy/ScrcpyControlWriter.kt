package com.megumiss.nkas.mobile.platform.scrcpy

import java.io.DataOutputStream
import java.io.OutputStream
import kotlin.math.roundToInt

/** Writes the scrcpy control-channel messages using the protocol's big-endian fields. */
class ScrcpyControlWriter(output: OutputStream) {
    private val data = DataOutputStream(output)

    @Synchronized
    fun injectKeycode(action: Int, keycode: Int, repeat: Int = 0, metaState: Int = 0) {
        data.writeByte(TYPE_INJECT_KEYCODE)
        data.writeByte(action)
        data.writeInt(keycode)
        data.writeInt(repeat)
        data.writeInt(metaState)
        data.flush()
    }

    @Synchronized
    fun injectText(text: String) {
        val bytes = text.toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_TEXT_BYTES) { "scrcpy text payload is too large" }
        data.writeByte(TYPE_INJECT_TEXT)
        data.writeInt(bytes.size)
        data.write(bytes)
        data.flush()
    }

    @Synchronized
    fun injectTouch(
        action: Int,
        pointerId: Long,
        x: Int,
        y: Int,
        screenWidth: Int,
        screenHeight: Int,
        pressure: Float = 1f,
        actionButton: Int = 0,
        buttons: Int = 0,
    ) {
        require(screenWidth in 1..0xffff && screenHeight in 1..0xffff)
        data.writeByte(TYPE_INJECT_TOUCH_EVENT)
        data.writeByte(action)
        data.writeLong(pointerId)
        data.writeInt(x)
        data.writeInt(y)
        data.writeShort(screenWidth)
        data.writeShort(screenHeight)
        data.writeShort(encodeUnsignedFixedPoint16(pressure))
        data.writeInt(actionButton)
        data.writeInt(buttons)
        data.flush()
    }

    @Synchronized
    fun pressBack(action: Int) {
        data.writeByte(TYPE_BACK_OR_SCREEN_ON)
        data.writeByte(action)
        data.flush()
    }

    @Synchronized
    fun setDisplayPower(on: Boolean) {
        data.writeByte(TYPE_SET_DISPLAY_POWER)
        data.writeBoolean(on)
        data.flush()
    }

    private fun encodeUnsignedFixedPoint16(value: Float): Int = value.coerceIn(0f, 1f).let {
        if (it >= 1f) 0xffff else (it * 65536f).roundToInt().coerceIn(0, 0xfffe)
    }

    companion object {
        const val TYPE_INJECT_KEYCODE = 0
        const val TYPE_INJECT_TEXT = 1
        const val TYPE_INJECT_TOUCH_EVENT = 2
        const val TYPE_BACK_OR_SCREEN_ON = 4
        const val TYPE_SET_DISPLAY_POWER = 10
        private const val MAX_TEXT_BYTES = 1 shl 20
    }
}
