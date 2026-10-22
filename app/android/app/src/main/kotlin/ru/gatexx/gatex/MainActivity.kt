package ru.gatexx.gatex

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import gatexcore.Gatexcore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private companion object {
        const val REQUEST_VPN = 7001
    }

    private var pendingPrepare: MethodChannel.Result? = null
    private var appChannel: MethodChannel? = null
    private var initialLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        initialLink = gatexLink(intent)

        MethodChannel(messenger, "gatex/core").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepare(result)
                "start" -> {
                    GatexVpnService.configFile(this).writeText(call.argument<String>("config")!!)
                    val start = Intent(this, GatexVpnService::class.java)
                        .setAction(GatexVpnService.ACTION_START)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(start)
                    } else {
                        startService(start)
                    }
                    result.success(null)
                }
                "stop" -> {
                    startService(
                        Intent(this, GatexVpnService::class.java)
                            .setAction(GatexVpnService.ACTION_STOP),
                    )
                    result.success(null)
                }
                "delay" -> {
                    val config = call.argument<String>("config")!!
                    val url = call.argument<String>("url")!!
                    val timeout = call.argument<Int>("timeout") ?: 5000
                    thread {
                        val answer: Map<String, Any?> = try {
                            mapOf("ms" to Gatexcore.measureDelay(config, url, timeout.toLong()).toInt())
                        } catch (e: Exception) {
                            mapOf("ms" to -1, "error" to (e.message ?: e.toString()))
                        }
                        runOnUiThread { result.success(answer) }
                    }
                }
                "version" -> result.success(Gatexcore.version())
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "gatex/core/status").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    GatexVpnService.listener = { sink.success(it) }
                    sink.success(GatexVpnService.current())
                }

                override fun onCancel(arguments: Any?) {
                    GatexVpnService.listener = null
                }
            },
        )

        appChannel = MethodChannel(messenger, "gatex/app").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialLink" -> {
                        result.success(initialLink)
                        initialLink = null
                    }
                    "deviceModel" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}")
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun prepare(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            // Only for the "Подключено" notification; the VPN works without it.
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
        }
        val consent = VpnService.prepare(this)
        if (consent == null) {
            result.success(true)
        } else {
            pendingPrepare = result
            @Suppress("DEPRECATION")
            startActivityForResult(consent, REQUEST_VPN)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_VPN) {
            pendingPrepare?.success(resultCode == RESULT_OK)
            pendingPrepare = null
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        gatexLink(intent)?.let { appChannel?.invokeMethod("link", it) }
    }

    private fun gatexLink(intent: Intent?): String? =
        intent?.dataString?.takeIf { it.startsWith("gatex:") }
}
