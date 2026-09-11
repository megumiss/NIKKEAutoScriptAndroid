package com.megumiss.nkas.mobile.preview.platform

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors

class TermuxInstaller(private val activity: Activity) {
    private val executor = Executors.newSingleThreadExecutor()

    fun download(
        onProgress: (Int) -> Unit,
        onComplete: (String) -> Unit,
        onError: (String) -> Unit,
    ) {
        executor.execute {
            try {
                val asset = findAsset()
                val target = File(activity.cacheDir, "termux-latest.apk")
                downloadFile(asset.second, target, onProgress)
                activity.runOnUiThread {
                    launchInstaller(target)
                    onComplete(asset.first)
                }
            } catch (error: Exception) {
                activity.runOnUiThread { onError(error.message ?: "Termux 下载失败") }
            }
        }
    }

    fun close() {
        executor.shutdownNow()
    }

    private fun findAsset(): Pair<String, String> {
        val abi = Build.SUPPORTED_ABIS.firstOrNull()?.lowercase(Locale.ROOT)
            ?: throw IllegalStateException("无法识别设备架构")
        val tokens = when {
            abi.contains("arm64") || abi.contains("aarch64") -> listOf("arm64-v8a", "aarch64")
            abi.contains("armeabi") || abi == "arm" -> listOf("armeabi-v7a", "arm")
            abi.contains("x86_64") || abi.contains("amd64") -> listOf("x86_64", "amd64")
            abi.contains("x86") -> listOf("x86")
            else -> throw IllegalStateException("Termux 不支持当前设备架构：$abi")
        }
        val connection = (URL(RELEASE_API).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 20_000
            requestMethod = "GET"
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "NKAS-Mobile")
        }
        try {
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("GitHub API 返回 HTTP ${connection.responseCode}")
            }
            val release = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val assets = release.optJSONArray("assets")
                ?: throw IllegalStateException("最新 Release 没有可用资产")
            var fallback: Pair<String, String>? = null
            for (index in 0 until assets.length()) {
                val asset = assets.optJSONObject(index) ?: continue
                val name = asset.optString("name")
                val lower = name.lowercase(Locale.ROOT)
                val url = asset.optString("browser_download_url")
                if (!lower.startsWith("termux-app") || !lower.endsWith(".apk") || url.isBlank()) continue
                if (tokens.any(lower::contains)) return name to url
                if (!lower.contains("source") && !lower.contains("debug")) fallback = name to url
            }
            return fallback ?: throw IllegalStateException("没有匹配 $abi 的 Termux APK")
        } finally {
            connection.disconnect()
        }
    }

    private fun downloadFile(url: String, target: File, onProgress: (Int) -> Unit) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            requestMethod = "GET"
            setRequestProperty("User-Agent", "NKAS-Mobile")
        }
        try {
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("Termux 下载返回 HTTP ${connection.responseCode}")
            }
            val total = connection.contentLengthLong
            var received = 0L
            var last = -1
            target.outputStream().use { output ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(32 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        received += count
                        if (total > 0) {
                            val progress = ((received * 100) / total).toInt()
                            if (progress != last) {
                                last = progress
                                activity.runOnUiThread { onProgress(progress) }
                            }
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun launchInstaller(apk: File) {
        val uri: Uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            apk,
        )
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }

    companion object {
        private const val RELEASE_API = "https://api.github.com/repos/termux/termux-app/releases/latest"
    }
}
