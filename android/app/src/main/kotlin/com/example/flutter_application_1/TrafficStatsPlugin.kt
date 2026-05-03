package com.example.flutter_application_1

import android.net.TrafficStats
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

class TrafficStatsPlugin : FlutterPlugin, MethodCallHandler {

    private var channel: MethodChannel? = null
    private var cacheDir: String? = null

    companion object {
        private val handler = Handler(Looper.getMainLooper())
        private var polling = false
        private var rxFilePath: String? = null

        fun startPolling(filePath: String) {
            rxFilePath = filePath
            if (polling) {
                Log.d("TrafficStats", "Polling sudah berjalan, skip")
                return
            }
            polling = true
            schedulePoll()
            Log.d("TrafficStats", "Polling started, file=$filePath")
        }

        fun stopPolling() {
            polling = false
            Log.d("TrafficStats", "Polling stopped")
        }

        private fun schedulePoll() {
            handler.postDelayed({
                if (!polling) return@postDelayed

                val rx = TrafficStats.getTotalRxBytes()
                val ts = System.currentTimeMillis()

                if (rx >= 0 && rx != TrafficStats.UNSUPPORTED.toLong()) {
                    try {
                        File(rxFilePath!!).writeText("$rx,$ts")
                    } catch (e: Exception) {
                        Log.e("TrafficStats", "Write error: $e")
                    }
                } else {
                    Log.w("TrafficStats", "TrafficStats tidak valid: rx=$rx")
                }

                schedulePoll()
            }, 500)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("TrafficStats", "onAttachedToEngine OK")
        cacheDir = binding.applicationContext.filesDir.absolutePath
        channel = MethodChannel(binding.binaryMessenger, "com.example.app/traffic_stats")
        channel!!.setMethodCallHandler(this)

        val filePath = "$cacheDir/rx_bytes.txt"
        startPolling(filePath)
        Log.d("TrafficStats", "RX file path: $filePath")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        stopPolling()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getFilePath" -> result.success("$cacheDir/rx_bytes.txt")
            "getRxBytes" -> {
                val rx = TrafficStats.getTotalRxBytes()
                if (rx < 0 || rx == TrafficStats.UNSUPPORTED.toLong()) {
                    result.error("UNSUPPORTED", "TrafficStats tidak tersedia", null)
                } else {
                    result.success(rx)
                }
            }
            "getTxBytes" -> {
                val tx = TrafficStats.getTotalTxBytes()
                if (tx < 0 || tx == TrafficStats.UNSUPPORTED.toLong()) {
                    result.error("UNSUPPORTED", "TrafficStats tidak tersedia", null)
                } else {
                    result.success(tx)
                }
            }
            else -> result.notImplemented()
        }
    }
}