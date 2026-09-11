package com.megumiss.nkas.mobile.preview.platform

import android.content.Context
import android.net.Uri

data class SourceChoice(val label: String, val value: String)

object SettingsStore {
    const val PREFS_NAME = "nkas_settings"
    const val DEFAULT_APT_SOURCE = "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
    const val DEFAULT_DOCKER_IMAGE = "docker.1ms.run/megumiss/nkas:latest"
    const val DEFAULT_REPOSITORY = "https://git.megumiss.top/megumiss/NIKKEAutoScript"
    const val DEFAULT_WEBUI_URL = "http://127.0.0.1:12271"
    const val DEFAULT_WEBUI_PORT = 12271

    val aptSources = listOf(
        SourceChoice("清华 Termux 源（国内）", DEFAULT_APT_SOURCE),
        SourceChoice("中科大 Termux 源（国内）", "https://mirrors.ustc.edu.cn/termux/apt/termux-main"),
        SourceChoice("官方 Termux 源", "https://packages.termux.dev/apt/termux-main")
    )

    val repositorySources = listOf(
        SourceChoice("项目镜像（国内）", DEFAULT_REPOSITORY),
        SourceChoice("GitHub 官方仓库", "https://github.com/megumiss/NIKKEAutoScript")
    )

    fun aptSource(context: Context): String = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString("apt_source", DEFAULT_APT_SOURCE) ?: DEFAULT_APT_SOURCE

    fun dockerImage(context: Context): String = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString("docker_image", DEFAULT_DOCKER_IMAGE) ?: DEFAULT_DOCKER_IMAGE

    fun repository(context: Context): String = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString("repository", DEFAULT_REPOSITORY) ?: DEFAULT_REPOSITORY

    fun webUiUrl(context: Context): String {
        val saved = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString("webui_url", DEFAULT_WEBUI_URL)
        return normalizeWebUiUrl(saved.orEmpty()) ?: DEFAULT_WEBUI_URL
    }

    fun webUiHost(context: Context): String = Uri.parse(webUiUrl(context)).host ?: "127.0.0.1"

    fun webUiPort(context: Context): Int = Uri.parse(webUiUrl(context)).port
        .takeIf { it in 1..65535 } ?: DEFAULT_WEBUI_PORT

    fun webUiApiUrl(context: Context, path: String): String =
        "${webUiUrl(context).trimEnd('/')}/${path.trimStart('/')}"

    fun serial(context: Context): String = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString("serial", "")?.trim().orEmpty()

    fun setSerial(context: Context, value: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString("serial", value.trim())
            .apply()
    }

    fun normalizeWebUiUrl(raw: String): String? {
        val candidate = raw.trim().trimEnd('/')
        if (candidate.isBlank() || candidate.length > 200 || candidate.any { it == '\n' || it == '\r' }) return null
        val uri = runCatching { Uri.parse(candidate) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        val host = uri.host ?: return null
        if (scheme !in setOf("http", "https") || host.isBlank() || uri.userInfo != null || uri.query != null || uri.fragment != null) return null
        if (uri.path != null && uri.path != "") return null
        if (!host.matches(Regex("[A-Za-z0-9._:-]+"))) return null
        val port = uri.port
        if (port != -1 && port !in 1..65535) return null
        val formattedHost = if (host.contains(':')) "[$host]" else host
        return "$scheme://$formattedHost:${if (port == -1) DEFAULT_WEBUI_PORT else port}"
    }

}
