package ru.gatexx.gatex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import gatexcore.Gatexcore
import java.io.File
import java.util.concurrent.Executors

/**
 * Owns the TUN and runs Xray from the gatexcore library in this process.
 * Xray's own sockets stay outside the tunnel because the app excludes
 * itself with addDisallowedApplication.
 */
class GatexVpnService : VpnService() {
    companion object {
        const val ACTION_START = "ru.gatexx.gatex.START"
        const val ACTION_STOP = "ru.gatexx.gatex.STOP"
        private const val CHANNEL = "vpn"
        private const val NOTIFICATION_ID = 1
        const val MTU = 1500

        @Volatile private var state = "disconnected"
        @Volatile private var error: String? = null
        private val main = Handler(Looper.getMainLooper())

        /** Set by MainActivity while Flutter listens for status. */
        @Volatile var listener: ((Map<String, Any?>) -> Unit)? = null

        fun current(): Map<String, Any?> = mapOf("state" to state, "error" to error)

        fun configFile(service: android.content.Context) = File(service.filesDir, "config.json")

        private fun emit(newState: String, newError: String? = null) {
            state = newState
            error = newError
            val snapshot = current()
            main.post { listener?.invoke(snapshot) }
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private var tun: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopTunnel()
            else -> startTunnel()
        }
        return START_NOT_STICKY
    }

    private fun startTunnel() {
        showNotification()
        emit("connecting")
        worker.execute {
            try {
                if (Gatexcore.isRunning()) Gatexcore.stop()
                tun?.close()
                val builder = Builder()
                    .setSession("GateX")
                    .setMtu(MTU)
                    .addAddress("172.19.0.1", 30)
                    .addRoute("0.0.0.0", 0)
                    .addDnsServer("1.1.1.1")
                    .addDnsServer("8.8.8.8")
                    .addDisallowedApplication(packageName)
                try {
                    builder.addAddress("fdfe:dcba:9876::1", 126).addRoute("::", 0)
                } catch (_: Exception) {
                    // No IPv6 on this device; IPv4 is enough to connect.
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
                val fd = builder.establish()
                    ?: throw IllegalStateException("Нет разрешения на VPN")
                tun = fd
                Gatexcore.setAssetDir(filesDir.path)
                Gatexcore.start(configFile(this).readText(), fd.fd.toLong())
                emit("connected")
            } catch (e: Exception) {
                cleanup()
                emit("disconnected", e.message ?: e.toString())
                main.post { finish() }
            }
        }
    }

    private fun stopTunnel() {
        emit("disconnecting")
        worker.execute {
            cleanup()
            emit("disconnected")
            main.post { finish() }
        }
    }

    private fun cleanup() {
        try {
            Gatexcore.stop()
        } catch (_: Exception) {
        }
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
    }

    private fun finish() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() {
        // Another VPN took over or the user turned us off in settings.
        stopTunnel()
    }

    override fun onDestroy() {
        if (tun != null) {
            cleanup()
            emit("disconnected")
        }
        worker.shutdown()
        super.onDestroy()
    }

    private fun showNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "VPN", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), flags,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, GatexVpnService::class.java).setAction(ACTION_STOP), flags,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_gatex)
            .setContentTitle("GateX VPN")
            .setContentText("Подключено")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Отключить", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
