package com.megumiss.nkas.mobile.platform.scrcpy

import java.util.Locale

data class ScrcpyServerOptions(
    val video: Boolean = true,
    val audio: Boolean = false,
    val control: Boolean = true,
    val maxSize: Int = 0,
    val videoBitRate: Int = 0,
    val videoCodec: String = "h264",
    val newDisplay: Boolean = false,
) {
    init {
        require(maxSize >= 0) { "maxSize must be non-negative" }
        require(videoBitRate >= 0) { "videoBitRate must be non-negative" }
        require(!audio && (video || control)) { "Enable video or control; audio is unsupported" }
        require(videoCodec in setOf("h264", "h265")) { "Unsupported video codec" }
        require(!newDisplay || video) { "Virtual display requires video" }
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
        require(remotePath.matches(Regex("/[A-Za-z0-9_./-]+"))) { "remotePath must be a shell-safe absolute path" }
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
            add("clipboard_autosync=false")
            if (!options.video) add("video=false")
            if (!options.audio) add("audio=false")
            if (!options.control) add("control=false")
            if (options.maxSize > 0) add("max_size=${options.maxSize}")
            if (options.videoBitRate > 0) add("video_bit_rate=${options.videoBitRate}")
            if (options.videoCodec != "h264") add("video_codec=${options.videoCodec}")
            if (options.newDisplay) {
                add("new_display=1080x1920/320")
                add("vd_destroy_content=false")
            }
        }.joinToString(" ")
    }

    fun socketName(scid: Int): String = "scrcpy_%08x".format(Locale.ROOT, scid)
}
