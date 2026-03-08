import 'dart:async';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

class NetworkService {
  static final NetworkInfo _info = NetworkInfo();
  static const MethodChannel _channel = MethodChannel('network_stats');

  // ================= PERMISSION =================
  static Future<void> requestPermission() async {
    if (!await Permission.location.isGranted) {
      await Permission.location.request();
    }
  }

  // ================= WIFI STATUS =================
  static Future<bool> isWifiConnected() async {
    final result = await Connectivity().checkConnectivity();
    return result == ConnectivityResult.wifi;
  }

  // ================= SIGNAL =================
  static Future<double> getSignalPower() async {
    final rssi = await WiFiForIoTPlugin.getCurrentSignalStrength();
    return rssi?.toDouble() ?? -100;
  }

  // ================= FREQUENCY =================
  static Future<int?> getFrequency() async {
    try {
      return await WiFiForIoTPlugin.getFrequency();
    } catch (_) {
      return null;
    }
  }

  static bool is5GHz(int? frequency) {
    if (frequency == null) return false;
    return frequency >= 4900 && frequency <= 5900;
  }

  static String getFrequencyBand(int? frequency) {
    if (frequency == null) return "Unknown";
    if (frequency >= 4900 && frequency <= 5900) return "5 GHz";
    if (frequency >= 2400 && frequency <= 2500) return "2.4 GHz";
    return "Unknown";
  }

  // ================= NOISE & INTERFERENCE =================
  static double getNoiseFloor({required bool is5GHz}) {
    return is5GHz ? -95 : -92;
  }

  static double getInterference({required bool is5GHz}) {
    return is5GHz ? -90 : -85;
  }

  // ================= WIFI INFO =================
  static Future<String> getSSID() async {
    await requestPermission();
    final ssid = await _info.getWifiName();
    return ssid ?? "Unknown";
  }

  static Future<String> getBSSID() async {
    await requestPermission();
    final bssid = await _info.getWifiBSSID();
    return bssid ?? "Unknown";
  }

  static Future<String> getIPAddress() async {
    await requestPermission();
    final ip = await _info.getWifiIP();
    return ip ?? "0.0.0.0";
  }

  // ================= TOTAL BYTES =================
  static Future<int> getTotalBytes() async {
    try {
      final bytes = await _channel.invokeMethod<int>('getTotalBytes');
      return bytes ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

// ====================== THROUGHPUT ======================
class ThroughputCalculator {
  int? _prevBytes;
  DateTime? _prevTime;

  Future<double> getThroughput() async {
    int totalBytes = await NetworkService.getTotalBytes();
    DateTime now = DateTime.now();

    if (_prevBytes == null) {
      _prevBytes = totalBytes;
      _prevTime = now;
      return 0;
    }

    int deltaBytes = totalBytes - _prevBytes!;
    double deltaTime = now.difference(_prevTime!).inSeconds.toDouble();
    if (deltaTime <= 0) deltaTime = 1;

    double throughputKbps = (deltaBytes * 8 / 1000) / deltaTime;

    _prevBytes = totalBytes;
    _prevTime = now;

    return throughputKbps;
  }
}

