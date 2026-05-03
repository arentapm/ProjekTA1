package com.example.flutter_application_1

import android.net.TrafficStats
import android.util.Log

object NativeTrafficStats {
    
    fun getRxBytes(): Long {
        val rx = TrafficStats.getTotalRxBytes()
        return if (rx < 0 || rx == TrafficStats.UNSUPPORTED.toLong()) -1L else rx
    }
}