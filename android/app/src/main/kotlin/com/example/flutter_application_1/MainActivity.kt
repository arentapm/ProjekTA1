package com.example.flutter_application_1

import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ✅ FIX: Plugin hanya didaftarkan SEKALI di sini
        // Hapus registrasi di provideFlutterEngine — itu menyebabkan channel conflict
        flutterEngine.plugins.add(TrafficStatsPlugin())
        Log.d("MainActivity", "TrafficStatsPlugin added OK")

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.app/wifi"
        ).setMethodCallHandler { _, result -> result.notImplemented() }
    }

    // ✅ FIX: Hapus override provideFlutterEngine sepenuhnya
    // Method ini menyebabkan plugin terdaftar dua kali → conflict channel
}