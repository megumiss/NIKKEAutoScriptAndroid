package com.megumiss.nkas.mobile.platform.scrcpy

import java.util.Locale

data class ScrcpyServerOptions(
    val video: Boolean = true,
    val audio: Boolean = false,
    val control: Boolean = true,
    val maxSize: Int = 0,
    val videoBitRate: Int = 0,
) {
    init {
        require(maxSize >= 0) { "maxSize must be non-negative" }
        require(videoBitRate >= 0) { "videoBitRate must be non-negative" }
        require(video || audio || control) { "At least one scrcpy channel must be enabled" }
    }
}

internal object ScrcpyServerCommand {
    const val DEFAULT_VERSION = "4.1"
    const val DEFAULT_REMOTE_PATH = "/data/local/tmp/scrcpy-server.jar"

    fun build(
        remotePath: String,
        version: String,
        scid: Int,
        options: ScrcpyServerOptions,
    ): String {
        require(remotePath.startsWith("/")) { "remotePath must be absolute" }
        require(version.matches(Regex("[0-9]+\\.[0-9]+"))) { "Invalid scrcpy version" }
        require(scid in 0..0x7fffffff) { "scid must fit in a signed 31-bit integer" }
        return buildList {
            add("CLASSPATH=$remotePath")
            add("app_process")
            add("/")
            add("com.genymobile.scrcpy.Server")
            add(version)
            add("scid=${scid.toString(16).lowercase(Locale.ROOT)}")
            add("tunnel_forward=true")
            if (!options.video) add("video=false")
            if (!options.audio) add("audio=false")
            if (!options.control) add("control=false")
            if (options.maxSize > 0) add("max_size=${options.maxSize}")
            if (options.videoBitRate > 0) add("video_bit_rate=${options.videoBitRate}")
        }.joinToString(" ")
    }

    fun socketName(scid: Int): String = "scrcpy_%08x".format(Locale.ROOT, scid)
}
