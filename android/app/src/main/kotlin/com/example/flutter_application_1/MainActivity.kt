package com.example.flutter_application_1

import android.net.TrafficStats
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "network_stats"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->

                if (call.method == "getTotalBytes") {

                    val rx = TrafficStats.getTotalRxBytes()
                    val tx = TrafficStats.getTotalTxBytes()

                    if (rx == TrafficStats.UNSUPPORTED.toLong() ||
                        tx == TrafficStats.UNSUPPORTED.toLong()) {
                        result.success(0)
                    } else {
                        result.success(rx + tx)
                    }

                } else {
                    result.notImplemented()
                }
            }
    }
}
