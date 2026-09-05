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
        val command = """
            if [ -f "${'$'}HOME/.nkas/settings.env" ]; then . "${'$'}HOME/.nkas/settings.env"; fi
            configured_serial="${'$'}(sed -n -E 's/^[[:space:]]*"Serial"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "${'$'}HOME/NIKKEAutoScript/config/nkas.json" 2>/dev/null | head -n1)"
            detected_serial=""
            if [ -n "${'$'}{NKAS_SERIAL:-}" ]; then
                configured_serial="${'$'}NKAS_SERIAL"
            else
                if [ -n "${'$'}configured_serial" ] && [ "${'$'}configured_serial" != "auto" ]; then
                    if ! adb -s "${'$'}configured_serial" get-state 2>/dev/null | grep -qx device; then configured_serial=""; fi
                else
                    configured_serial=""
                fi
                local_ip="${'$'}(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1)"
                [ -z "${'$'}local_ip" ] && local_ip="${'$'}(ip -4 addr show scope global 2>/dev/null | sed -n 's/.* inet \([0-9.]*\)\/.*/\1/p' | head -n1)"
                if [ -z "${'$'}configured_serial" ]; then
                    detected_serial="${'$'}(adb devices 2>/dev/null | awk 'NR > 1 && ${'$'}2 == "device" { print ${'$'}1; exit }')"
                    configured_serial="${'$'}detected_serial"
                fi
                if [ -z "${'$'}configured_serial" ] && [ -n "${'$'}local_ip" ]; then
                    for candidate in ${'$'}(adb mdns services 2>/dev/null | awk -v ip="${'$'}local_ip" '(${'$'}2 == "_adb-tls-connect._tcp" && index(${'$'}3, ip ":") == 1) { print ${'$'}3 } (${'$'}3 == "_adb-tls-connect._tcp" && index(${'$'}4, ip ":") == 1) { print ${'$'}4 }'); do
                        adb connect "${'$'}candidate" >/dev/null 2>&1 || true
                        if adb -s "${'$'}candidate" get-state 2>/dev/null | grep -qx device; then
                            configured_serial="${'$'}candidate"
                            detected_serial="${'$'}candidate"
                            break
                        fi
                    done
                fi
            fi
            if [ -n "${'$'}detected_serial" ] && [ -f "${'$'}HOME/NIKKEAutoScript/config/nkas.json" ]; then
                sed -i -E "s/(\"Serial\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"${'$'}detected_serial\"/" "${'$'}HOME/NIKKEAutoScript/config/nkas.json"
            fi
            printf 'adb_serial=%s\n' "${'$'}configured_serial"
            printf 'adb_device='
            if [ -n "${'$'}configured_serial" ] && adb -s "${'$'}configured_serial" get-state 2>/dev/null | grep -qx device; then printf 'yes'
            elif adb devices 2>/dev/null | awk 'NR > 1 && ${'$'}2 == "device" { found=1 } END { exit(found ? 0 : 1) }'; then printf 'yes'
            else printf 'no'; fi
            printf '\n'
            printf 'termux_setting='
            termux_home="${'$'}{HOME:-/data/data/com.termux/files/home}"
            termux_prefix="${'$'}{PREFIX:-/data/data/com.termux/files/usr}"
            termux_properties="${'$'}termux_home/.termux/termux.properties"
            [ -f "${'$'}termux_properties" ] || termux_properties="${'$'}termux_prefix/../home/.termux/termux.properties"
            [ -f "${'$'}termux_properties" ] || termux_properties="${'$'}termux_prefix/etc/termux.properties"
            setting_value="${'$'}(cat "${'$'}termux_properties" 2>/dev/null | tr -d '[:space:]\r' | tr '[:upper:]' '[:lower:]')"
            printf 'termux_home=%s\n' "${'$'}termux_home"
            printf 'termux_prefix=%s\n' "${'$'}termux_prefix"
            printf 'termux_properties_path=%s\n' "${'$'}termux_properties"
            printf 'termux_setting_value=%s\n' "${'$'}setting_value"
            if [ "${'$'}setting_value" = "allow-external-apps=true" ]; then printf 'yes'; else printf 'no'; fi
            printf '\n'
            printf 'tools='
            if command -v git >/dev/null 2>&1 && command -v proot-distro >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v adb >/dev/null 2>&1; then printf 'yes'; else printf 'no'; fi
            printf '\n'
            printf 'source='
            if [ -d "${'$'}HOME/NIKKEAutoScript/.git" ] && git -C "${'$'}HOME/NIKKEAutoScript" rev-parse --is-inside-work-tree >/dev/null 2>&1; then printf 'yes'; else printf 'no'; fi
            printf '\n'
            printf 'config='
            if [ -f "${'$'}HOME/NIKKEAutoScript/config/nkas.json" ]; then printf 'yes'; else printf 'no'; fi
            printf '\n'
            printf 'container='
            if [ -d "${'$'}PREFIX/var/lib/proot-distro/containers/nkas/rootfs" ] && [ -x "${'$'}PREFIX/var/lib/proot-distro/containers/nkas/rootfs/usr/local/bin/python" ] && [ "${'$'}(sed -n 's/^NKAS_DOCKER_IMAGE=//p' "${'$'}HOME/.nkas/settings.env" 2>/dev/null)" = '$expectedImage' ]; then printf 'yes'; else printf 'no'; fi
            printf '\n'
            printf 'service='
            if curl -fsS --max-time 3 "${'$'}{NKAS_WEBUI_URL:-$serviceUrl}/api/system/status" >/dev/null 2>&1; then printf 'yes'; else printf 'no'; fi
            printf '\n'
        """.trimIndent().lineSequence().joinToString(";")
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
            context.startForegroundService(intent)
            Log.i(TAG, "started token=$token")
        } catch (error: Exception) {
            callbacks.remove(token)
            Log.e(TAG, "start failed token=$token", error)
            onResult(CommandResult("", error.message ?: "无法启动 Termux 命令", -1))
        }
    }

    data class CommandResult(val stdout: String, val stderr: String, val exitCode: Int)
}
