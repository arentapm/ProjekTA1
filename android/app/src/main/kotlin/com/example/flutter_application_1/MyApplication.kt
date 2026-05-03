package com.example.flutter_application_1

import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import android.net.TrafficStats
import android.util.Log

class MyApplication : FlutterApplication() {

    override fun onCreate() {
        super.onCreate()
        Log.d("MyApplication", "App started")
    }
}