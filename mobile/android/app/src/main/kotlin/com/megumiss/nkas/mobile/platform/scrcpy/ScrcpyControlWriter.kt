package com.megumiss.nkas.mobile.platform.scrcpy

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.OutputStream
import kotlin.math.roundToInt

class ScrcpyControlWriter(private val output: OutputStream) {
    fun injectKeycode(action: Int, keycode: Int, repeat: Int = 0, metaState: Int = 0) {
        require(action in 0..1 && keycode >= 0 && repeat >= 0) { "Invalid key event" }
        write {
            writeByte(TYPE_INJECT_KEYCODE); writeByte(action)
            writeInt(keycode); writeInt(repeat); writeInt(metaState)
        }
    }

    fun injectText(text: String) {
        val bytes = text.toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_TEXT_BYTES) { "文本最多为 300 个 UTF-8 字节" }
        write { writeByte(TYPE_INJECT_TEXT); writeInt(bytes.size); write(bytes) }
    }

    fun injectTouch(action: Int, pointerId: Long, x: Int, y: Int, screenWidth: Int, screenHeight: Int,
                    pressure: Float = 1f, actionButton: Int = 0, buttons: Int = 0) {
        require(action in 0..3 && screenWidth in 1..0xffff && screenHeight in 1..0xffff)
        require(x in 0 until screenWidth && y in 0 until screenHeight && pressure.isFinite())
        val force = if (action == 1 || action == 3) 0 else encodeUnsignedFixedPoint16(pressure)
        write {
            writeByte(TYPE_INJECT_TOUCH_EVENT); writeByte(action); writeLong(pointerId)
            writeInt(x); writeInt(y); writeShort(screenWidth); writeShort(screenHeight)
            writeShort(force); writeInt(actionButton); writeInt(buttons)
        }
    }

    fun pressBack(action: Int) {
        require(action in 0..1)
        write { writeByte(TYPE_BACK_OR_SCREEN_ON); writeByte(action) }
    }

    fun setDisplayPower(on: Boolean) = write { writeByte(TYPE_SET_DISPLAY_POWER); writeBoolean(on) }

    @Synchronized
    private fun write(build: DataOutputStream.() -> Unit) {
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).build()
        // One ADB WRTE per message avoids an acknowledgement round trip for every field.
        output.write(bytes.toByteArray())
        output.flush()
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
        private const val MAX_TEXT_BYTES = 300
    }
}
