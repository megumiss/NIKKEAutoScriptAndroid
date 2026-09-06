package com.megumiss.nkas

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** 应用侧事件日志：初始化、配对、状态检查等关键事件落盘，供日志页回看。 */
object LogStore {
    private const val MAX_BYTES = 256 * 1024
    private const val KEEP_BYTES = 128 * 1024
    private var file: File? = null
    private val time = SimpleDateFormat("MM-dd HH:mm:ss", Locale.US)

    fun init(context: Context) {
        file = File(context.filesDir, "nkas-app.log")
    }

    @Synchronized
    fun log(tag: String, message: String) {
        val target = file ?: return
        runCatching {
            if (target.length() > MAX_BYTES) {
                val bytes = target.readBytes()
                target.writeBytes(bytes.copyOfRange(bytes.size - KEEP_BYTES, bytes.size))
            }
            target.appendText("${time.format(Date())} [$tag] $message\n")
        }
    }

    fun text(): String = runCatching {
        file?.takeIf { it.exists() }?.readText()?.takeLast(KEEP_BYTES).orEmpty()
    }.getOrDefault("")
}
