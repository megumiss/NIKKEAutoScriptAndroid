package com.megumiss.nkas.mobile.platform

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

/**
 * 移植 Shizuku AdbPairingService 的交互模式：mDNS 发现本机配对端口 → 通知栏输入配对码。
 * 与 Shizuku 的差别：配对动作委托给 Termux 的 adb pair，不在进程内实现 SPAKE2。
 */
class AdbPairingService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var mdns: AdbMdns? = null
    private var pendingCode: String? = null
    private var paired = false

    private val discoveryTimeout = Runnable {
        notifyResult(false, "等待配对服务超时。请确认无线调试中的“使用配对码配对”弹窗处于打开状态。")
        stopSelf()
    }

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "ADB 配对", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                setShowBadge(false)
            }
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                pendingCode = intent.getStringExtra(EXTRA_CODE)?.takeIf { it.isNotBlank() }
                startForegroundSafe(searchingNotification())
                startDiscovery()
            }
            ACTION_REPLY -> {
                val code = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(KEY_PAIRING_CODE)?.toString().orEmpty()
                val port = intent.getIntExtra(EXTRA_PORT, -1)
                if (port > 0 && code.isNotBlank()) pair(port, code)
            }
            ACTION_STOP -> stopSelf()
        }
        return START_REDELIVER_INTENT
    }

    private fun startDiscovery() {
        if (mdns != null) return
        handler.postDelayed(discoveryTimeout, 60_000)
        mdns = AdbMdns(this, AdbMdns.TLS_PAIRING) { port ->
            handler.post {
                if (port <= 0 || paired) return@post
                handler.removeCallbacks(discoveryTimeout)
                val code = pendingCode
                if (code != null) pair(port, code) else notifyInput(port)
            }
        }.apply { start() }
    }

    private fun pair(port: Int, code: String) {
        notifyProgress("正在配对 127.0.0.1:$port ……")
        TermuxBridge(this).pairDevice("127.0.0.1:$port", code, SettingsStore.serial(this)) { result ->
            paired = true
            LogStore.log("pair", "配对结果 exitCode=${result.exitCode}")
            val output = (result.stdout + if (result.stderr.isNotBlank()) "\n${result.stderr}" else "").trim()
            if (result.exitCode == 0) {
                notifyResult(true, "配对成功，设备已连接。")
            } else {
                notifyResult(false, "配对失败：${output.takeLast(300).ifBlank { "返回码 ${result.exitCode}" }}")
            }
            stopSelf()
        }
    }

    private fun startForegroundSafe(notification: Notification) {
        try {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MANIFEST)
        } catch (error: Throwable) {
            Log.e(TAG, "startForeground failed", error)
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification)
        }
    }

    private fun notify(id: Int, notification: Notification) {
        getSystemService(NotificationManager::class.java).notify(id, notification)
    }

    private fun searchingNotification(): Notification {
        val stop = PendingIntent.getService(
            this, 2, Intent(this, AdbPairingService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("正在搜索配对服务……")
            .setContentText("请在无线调试页面打开“使用配对码配对”")
            .addAction(Notification.Action.Builder(null, "取消", stop).build())
            .build()
    }

    private fun notifyInput(port: Int) {
        val remoteInput = RemoteInput.Builder(KEY_PAIRING_CODE).setLabel("配对码").build()
        val reply = PendingIntent.getService(
            this, 1,
            Intent(this, AdbPairingService::class.java).setAction(ACTION_REPLY).putExtra(EXTRA_PORT, port),
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val action = Notification.Action.Builder(null, "输入配对码", reply).addRemoteInput(remoteInput).build()
        notify(NOTIFICATION_ID, Notification.Builder(this, CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("已发现配对服务")
            .setContentText("在无线调试的配对弹窗中查看配对码")
            .addAction(action)
            .build())
    }

    private fun notifyProgress(text: String) {
        notify(NOTIFICATION_ID, Notification.Builder(this, CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(text)
            .build())
    }

    private fun notifyResult(success: Boolean, text: String) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        notify(NOTIFICATION_ID, Notification.Builder(this, CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(if (success) "ADB 配对成功" else "ADB 配对失败")
            .setContentText(text)
            .setAutoCancel(true)
            .build())
    }

    override fun onDestroy() {
        mdns?.stop()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "NkasAdbPairing"
        private const val CHANNEL = "adb_pairing"
        private const val NOTIFICATION_ID = 42
        private const val KEY_PAIRING_CODE = "pairing_code"
        private const val EXTRA_PORT = "pair_port"
        private const val EXTRA_CODE = "pair_code"
        private const val ACTION_START = "start"
        private const val ACTION_REPLY = "reply"
        private const val ACTION_STOP = "stop"

        fun startIntent(context: Context, code: String?): Intent =
            Intent(context, AdbPairingService::class.java).setAction(ACTION_START).putExtra(EXTRA_CODE, code)
    }
}
