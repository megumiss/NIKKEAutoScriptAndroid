package com.megumiss.nkas

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Base64
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import android.os.Handler
import android.os.Looper
import android.util.Log

class TermuxBridge(private val context: Context) {
    companion object {
        private const val TAG = "NkasTermuxBridge"
        private const val TERMUX_PACKAGE = "com.termux"
        const val RUN_COMMAND_PERMISSION = "com.termux.permission.RUN_COMMAND"
        private const val RUN_COMMAND = "com.termux.RUN_COMMAND"
        private const val EXTRA_PATH = "com.termux.RUN_COMMAND_PATH"
        private const val EXTRA_ARGUMENTS = "com.termux.RUN_COMMAND_ARGUMENTS"
        private const val EXTRA_BACKGROUND = "com.termux.RUN_COMMAND_BACKGROUND"
        private const val EXTRA_PENDING_INTENT = "com.termux.RUN_COMMAND_PENDING_INTENT"
        private const val TOKEN = "nkas_result_token"
        private const val COMMAND_TIMEOUT_MS = 12_000L
        private val callbacks = ConcurrentHashMap<String, (CommandResult) -> Unit>()
        private val timeoutHandler = Handler(Looper.getMainLooper())

        internal fun deliver(intent: Intent) {
            val token = intent.getStringExtra(TOKEN) ?: return
            val callback = callbacks.remove(token) ?: return
            val bundle = intent.getBundleExtra("result")
            val stdout = bundle?.getString("stdout") ?: intent.getStringExtra("stdout") ?: ""
            val stderr = bundle?.getString("stderr") ?: intent.getStringExtra("stderr") ?: ""
            val code = bundle?.getInt("exitCode", -1) ?: intent.getIntExtra("exitCode", -1)
            val error = bundle?.getString("errmsg") ?: ""
            Log.i(TAG, "result token=$token exitCode=$code stdout=${stdout.take(200)} stderr=${stderr.take(200)} errmsg=${error.take(200)}")
            callback(CommandResult(stdout, if (error.isBlank()) stderr else "$stderr\n$error", code))
        }
    }

    fun isInstalled(): Boolean = try {
        context.packageManager.getApplicationInfo(TERMUX_PACKAGE, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    @Throws(IOException::class)
    fun startBootstrap(onResult: (CommandResult) -> Unit = {}) {
        // Android assets retain the checkout's line endings. Normalize scripts before handing
        // them to Termux, otherwise CRLF files fail in bash with syntax errors.
        val script = readAssetScript("bootstrap.sh")
        val service = readAssetScript("nkas-service.sh")
        val settings = "NKAS_APT_SOURCE=${SettingsStore.aptSource(context)}\n" +
            "NKAS_DOCKER_IMAGE=${SettingsStore.dockerImage(context)}\n" +
            "NKAS_REPOSITORY=${SettingsStore.repository(context)}\n" +
            "NKAS_SERIAL=${SettingsStore.serial(context)}\n" +
            "NKAS_WEBUI_URL=${SettingsStore.webUiUrl(context)}\n" +
            "NKAS_WEBUI_HOST=${SettingsStore.webUiHost(context)}\n" +
            "NKAS_WEBUI_PORT=${SettingsStore.webUiPort(context)}\n"
        val encoded = Base64.encodeToString(script, Base64.NO_WRAP)
        val encodedService = Base64.encodeToString(service, Base64.NO_WRAP)
        val encodedSettings = Base64.encodeToString(settings.toByteArray(), Base64.NO_WRAP)
        val command = "mkdir -p \$HOME/.nkas; echo $encodedSettings | base64 -d > \$HOME/.nkas/settings.env; echo $encodedService | base64 -d > \$HOME/.nkas/nkas-service.sh; chmod 700 \$HOME/.nkas/nkas-service.sh; echo $encoded | base64 -d > \$HOME/.nkas/bootstrap.sh; chmod 700 \$HOME/.nkas/bootstrap.sh; \$HOME/.nkas/bootstrap.sh"
        runCommand(command, onResult)
    }

    private fun readAssetScript(name: String): ByteArray = context.assets.open(name).use {
        it.readBytes().toString(Charsets.UTF_8)
            .replace("\r\n", "\n")
            .replace('\r', '\n')
            .toByteArray(Charsets.UTF_8)
    }

    fun readBootstrapLog(onResult: (CommandResult) -> Unit) {
        runCommand("printf '%s\\n' '---STATE---'; cat \$HOME/.nkas/state 2>/dev/null || true; printf '%s\\n' '---LOG---'; tail -n 80 \$HOME/.nkas/bootstrap.log 2>/dev/null || true; printf '%s\\n' '---SERVICE---'; tail -n 40 \$HOME/.nkas/nkas-service.log 2>/dev/null || true", onResult)
    }

    fun checkArtifacts(onResult: (CommandResult) -> Unit) {
        val expectedImage = SettingsStore.dockerImage(context).replace("'", "")
        val serviceUrl = SettingsStore.webUiApiUrl(context, "/api/system/status")
        val script = """
            termux_home="${'$'}{HOME:-/data/data/com.termux/files/home}"
            termux_prefix="${'$'}{PREFIX:-/data/data/com.termux/files/usr}"
            if [ -f "${'$'}termux_home/.nkas/settings.env" ]; then . "${'$'}termux_home/.nkas/settings.env"; fi
            configured_serial="${'$'}{NKAS_SERIAL:-}"
            if [ -z "${'$'}configured_serial" ]; then configured_serial="${'$'}(sed -n -E 's/^[[:space:]]*"Serial"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "${'$'}termux_home/NIKKEAutoScript/config/nkas.json" 2>/dev/null | head -n1)"; fi
            detected_serial=""
            if [ "${'$'}configured_serial" = auto ]; then configured_serial=""; fi
            if [ -n "${'$'}configured_serial" ] && ! adb -s "${'$'}configured_serial" get-state 2>/dev/null | grep -qx device; then configured_serial=""; fi
            if [ -z "${'$'}configured_serial" ]; then
                detected_serial="${'$'}(adb devices 2>/dev/null | awk 'NR > 1 && ${'$'}2 == "device" { print ${'$'}1; exit }')"
                configured_serial="${'$'}detected_serial"
            fi
            if [ -n "${'$'}detected_serial" ] && [ -f "${'$'}termux_home/NIKKEAutoScript/config/nkas.json" ]; then
                sed -i -E "s/(\"Serial\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"${'$'}detected_serial\"/" "${'$'}termux_home/NIKKEAutoScript/config/nkas.json"
            fi
            printf 'adb_serial=%s\n' "${'$'}configured_serial"
            printf 'adb_device='
            if [ -n "${'$'}configured_serial" ] && adb -s "${'$'}configured_serial" get-state 2>/dev/null | grep -qx device; then printf 'yes'; else printf 'no'; fi
            printf '\n'
            termux_properties="${'$'}termux_home/.termux/termux.properties"
            [ -f "${'$'}termux_properties" ] || termux_properties="${'$'}termux_prefix/../home/.termux/termux.properties"
            [ -f "${'$'}termux_properties" ] || termux_properties="${'$'}termux_prefix/etc/termux.properties"
            setting_value="${'$'}(sed -n -E 's/^[[:space:]]*allow-external-apps[[:space:]]*=[[:space:]]*(true|false).*/\1/p' "${'$'}termux_properties" 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]')"
            printf 'termux_setting=%s\n' "${'$'}([ "${'$'}setting_value" = true ] && printf yes || printf no)"
            printf 'tools=%s\n' "${'$'}([ "${'$'}(command -v git)" ] && [ "${'$'}(command -v proot-distro)" ] && [ "${'$'}(command -v curl)" ] && [ "${'$'}(command -v adb)" ] && printf yes || printf no)"
            printf 'source=%s\n' "${'$'}([ -d "${'$'}termux_home/NIKKEAutoScript/.git" ] && git -C "${'$'}termux_home/NIKKEAutoScript" rev-parse --is-inside-work-tree >/dev/null 2>&1 && printf yes || printf no)"
            printf 'config=%s\n' "${'$'}([ -f "${'$'}termux_home/NIKKEAutoScript/config/nkas.json" ] && printf yes || printf no)"
            printf 'container=%s\n' "${'$'}([ -d "${'$'}termux_prefix/var/lib/proot-distro/containers/nkas/rootfs" ] && [ -x "${'$'}termux_prefix/var/lib/proot-distro/containers/nkas/rootfs/usr/local/bin/python" ] && [ "${'$'}(sed -n 's/^NKAS_DOCKER_IMAGE=//p' "${'$'}termux_home/.nkas/settings.env" 2>/dev/null)" = '$expectedImage' ] && printf yes || printf no)"
            printf 'service=%s\n' "${'$'}(curl -fsS --max-time 3 "${'$'}{NKAS_WEBUI_URL:-$serviceUrl}/api/system/status" >/dev/null 2>&1 && printf yes || printf no)"
        """.trimIndent()
        val encoded = Base64.encodeToString(script.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val command = "printf '%s' '$encoded' | base64 -d | bash"
        runCommand(command, onResult)
    }

    private fun runCommand(
        command: String,
        onResult: (CommandResult) -> Unit,
    ) {
        val token = UUID.randomUUID().toString()
        Log.i(TAG, "send token=$token command=${command.take(240)}")
        callbacks[token] = onResult
        timeoutHandler.postDelayed({
            val callback = callbacks.remove(token) ?: return@postDelayed
            Log.w(TAG, "timeout token=$token")
            callback(CommandResult("", "Termux 外部命令等待超时，请确认 Termux 已完全重启且 allow-external-apps=true。", -2))
        }, COMMAND_TIMEOUT_MS)
        val callbackIntent = Intent(context, TermuxResultReceiver::class.java).putExtra(TOKEN, token)
        val pendingIntent = PendingIntent.getBroadcast(context, token.hashCode(), callbackIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_MUTABLE)
        val intent = Intent(RUN_COMMAND).apply {
            setClassName(TERMUX_PACKAGE, "com.termux.app.RunCommandService")
            putExtra(EXTRA_PATH, "/data/data/com.termux/files/usr/bin/bash")
            putExtra(EXTRA_ARGUMENTS, arrayOf("-lc", command))
            putExtra(EXTRA_BACKGROUND, true)
            putExtra(EXTRA_PENDING_INTENT, pendingIntent)
            putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", "NKAS Mobile")
            addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
        }
        try {
            // RunCommandService is a short-lived command service; foreground startup can
            // prevent Termux from returning the command result on some Android builds.
            context.startService(intent)
            Log.i(TAG, "started token=$token")
        } catch (error: Exception) {
            callbacks.remove(token)
            Log.e(TAG, "start failed token=$token", error)
            onResult(CommandResult("", error.message ?: "无法启动 Termux 命令", -1))
        }
    }

    data class CommandResult(val stdout: String, val stderr: String, val exitCode: Int)
}
