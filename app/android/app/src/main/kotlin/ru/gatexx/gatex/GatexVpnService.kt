package ru.gatexx.gatex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
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
        const val EXTRA_APPS_MODE = "apps_mode"
        const val EXTRA_APPS = "apps"
        private const val CHANNEL = "vpn"
        private const val TAG = "GatexVpnService"
        private const val NOTIFICATION_ID = 1
        const val MTU = 1500

        @Volatile private var state = "disconnected"
        @Volatile private var error: String? = null
        @Volatile private var reconnecting = false
        private val main = Handler(Looper.getMainLooper())

        /** Set by MainActivity while Flutter listens for status. */
        @Volatile var listener: ((Map<String, Any?>) -> Unit)? = null

        fun current(): Map<String, Any?> = mapOf("state" to state, "error" to error, "reconnecting" to reconnecting)

        fun configFile(service: android.content.Context) = File(service.filesDir, "config.json")

        private fun emit(newState: String, newError: String? = null, newReconnecting: Boolean = false) {
            state = newState
            error = newError
            reconnecting = newReconnecting
            val snapshot = current()
            main.post { listener?.invoke(snapshot) }
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var tun: ParcelFileDescriptor? = null

    // Per-app VPN from the start intent: all | only | except, and package names.
    @Volatile private var appsMode = "all"
    @Volatile private var apps: List<String> = emptyList()

    // Set by stopTunnel, cleared by startTunnel; a queued core restart then does nothing.
    @Volatile private var stopping = false

    // Bumped on every start and stop; a restart scheduled earlier is dropped.
    @Volatile private var session = 0

    // Network change: keep the TUN, restart only the core (API 24+).
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var lastNetwork: Network? = null
    @Volatile private var firstNetwork = true
    @Volatile private var scheduledSession = 0
    private val restartCore = Runnable { restartCoreOnWorker(scheduledSession) }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopTunnel()
            else -> {
                appsMode = intent?.getStringExtra(EXTRA_APPS_MODE) ?: "all"
                apps = intent?.getStringArrayExtra(EXTRA_APPS)?.toList() ?: emptyList()
                startTunnel()
            }
        }
        return START_NOT_STICKY
    }

    private fun startTunnel() {
        stopping = false
        session++
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
                applyApps(builder)
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
                main.post { watchNetwork() }
            } catch (e: Exception) {
                cleanup()
                emit("disconnected", e.message ?: e.toString())
                main.post { finish() }
            }
        }
    }

    /**
     * Android forbids mixing allowed and disallowed apps on one Builder.
     * only: just the chosen apps are tunnelled (GateX is not among them,
     * so Xray's sockets stay outside). all / except: GateX is excluded,
     * and in except so are the chosen apps. Unknown packages are skipped.
     */
    private fun applyApps(builder: Builder) {
        if (appsMode == "only") {
            var added = 0
            for (name in apps) {
                if (name == packageName) continue
                try {
                    builder.addAllowedApplication(name)
                    added++
                } catch (_: PackageManager.NameNotFoundException) {
                }
            }
            // An empty allow list would tunnel every app; fail instead.
            if (added == 0) throw IllegalStateException("Не выбрано ни одного приложения")
            return
        }
        builder.addDisallowedApplication(packageName)
        if (appsMode == "except") {
            for (name in apps) {
                if (name == packageName) continue
                try {
                    builder.addDisallowedApplication(name)
                } catch (_: PackageManager.NameNotFoundException) {
                }
            }
        }
    }

    private fun stopTunnel() {
        stopping = true
        session++
        main.removeCallbacks(restartCore)
        emit("disconnecting")
        worker.execute {
            cleanup()
            emit("disconnected")
            main.post { finish() }
        }
    }

    private fun watchNetwork() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        if (netCallback != null || tun == null) return
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        firstNetwork = true
        lastNetwork = null
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (firstNetwork) {
                    // The first call is the network we are on now.
                    firstNetwork = false
                    lastNetwork = network
                    setUnderlyingNetworks(arrayOf(network))
                    return
                }
                if (network == lastNetwork) return
                lastNetwork = network
                setUnderlyingNetworks(arrayOf(network))
                main.removeCallbacks(restartCore)
                scheduledSession = session
                main.postDelayed(restartCore, 2000)
            }

            override fun onLost(network: Network) {
                // The next onAvailable is a network change even if it is the same one.
                if (network == lastNetwork) lastNetwork = null
            }
        }
        try {
            cm.registerDefaultNetworkCallback(callback)
            netCallback = callback
        } catch (e: Exception) {
            // Without the callback the tunnel works, it just will not follow network changes.
            Log.w(TAG, "registerDefaultNetworkCallback failed", e)
        }
    }

    private fun unwatchNetwork() {
        main.removeCallbacks(restartCore)
        val callback = netCallback ?: return
        netCallback = null
        try {
            getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
        }
    }

    private fun restartCoreOnWorker(scheduledIn: Int) {
        if (stopping || scheduledIn != session) return
        worker.execute {
            if (stopping || scheduledIn != session) return@execute
            val fd = tun ?: return@execute
            try {
                emit("connecting", newReconnecting = true)
                Gatexcore.stop()
                Gatexcore.start(configFile(this).readText(), fd.fd.toLong())
                emit("connected")
            } catch (e: Exception) {
                cleanup()
                emit("disconnected", e.message ?: e.toString())
                main.post { finish() }
            }
        }
    }

    private fun cleanup() {
        main.post { unwatchNetwork() }
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
