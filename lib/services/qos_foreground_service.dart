import 'dart:async';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/network_service.dart';
import '../models/data_qos.dart';
import '../database/db_helper.dart';

// ════════════════════════════════════════════════════════════════════
// QosTaskHandler — berjalan di isolate TERPISAH dari main isolate
//
// FIX UTAMA:
// 1. MonitoringController DIHAPUS dari sini — singleton tidak shared
//    antar isolate, menyebabkan history selalu kosong
// 2. Seluruh logika poll, buffer, DB insert dipindah ke sini langsung
// 3. Guard duplicate timestamp pada file rx_bytes.txt
// 4. SINR cache dengan TTL 30 detik
// ════════════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(QosTaskHandler());
}

class QosTaskHandler extends TaskHandler {

  // ── State throughput ─────────────────────────────────────────
  int _lastRxBytes = 0;
  int _lastRxTimestamp = 0;
  int _lastProcessedTs = 0;     // ✅ FIX: guard duplicate timestamp file
  double _lastThroughput = 0.0;
  bool _hasThroughput = false;
  String? _rxFilePath;

  // ── State QoS terbaru ─────────────────────────────────────────
  DataQoS? _latestQoS;
  int _mlBufferCount = 0;
  int _exportBufferCount = 0;
  double? _lastPrediction;

  // ── Cache info WiFi ───────────────────────────────────────────
  String _cachedSSID = 'Unknown';
  String _cachedIP   = '0.0.0.0';
  String _cachedBand = 'Unknown';

  // ── Busy guard poll ───────────────────────────────────────────
  bool _isPollBusy = false;

  // ═══════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('[TaskHandler] START');
    await NetworkService.requestPermission();
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // ✅ FIX: Semua logika ada di sini, tidak bergantung pada singleton
    // Baca throughput dari file Kotlin
    await _readThroughputFromFile();

    // Jalankan poll QoS (sama seperti _runPoll di MonitoringController)
    await _runPoll();

    // Kirim data ke main isolate via sendDataToMain
    _sendToMain();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('[TaskHandler] STOP');
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'stop') FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') FlutterForegroundTask.stopService();
  }

  // ═══════════════════════════════════════════════════════════════
  // BACA THROUGHPUT DARI FILE
  // ═══════════════════════════════════════════════════════════════

  Future<void> _readThroughputFromFile() async {
    try {
      _rxFilePath ??= '/data/user/0/com.example.flutter_application_1/files/rx_bytes.txt';

      final file = File(_rxFilePath!);
      if (!await file.exists()) {
        print('[TaskHandler] file rx belum ada');
        return;
      }

      final content = await file.readAsString();
      final parts = content.trim().split(',');
      if (parts.length < 2) return;

      final rx = int.tryParse(parts[0]) ?? -1;
      final ts = int.tryParse(parts[1]) ?? -1;

      if (rx < 0 || ts <= 0) return;

      // ✅ FIX BUG 1: Skip jika file belum diupdate (timestamp sama)
      // Ini root cause throughput frozen
      if (ts == _lastProcessedTs) {
        print('[TaskHandler] file belum diupdate (ts=$ts sama), skip throughput');
        return;
      }
      _lastProcessedTs = ts;

      _updateThroughput(rx, ts);

    } catch (e) {
      print('[TaskHandler] file read error: $e');
    }
  }

  void _updateThroughput(int rxBytes, int timestampMs) {
    if (rxBytes <= 0) return;

    if (_lastRxBytes > 0 && _lastRxTimestamp > 0) {
      final deltaBytes = rxBytes - _lastRxBytes;
      final deltaSec   = (timestampMs - _lastRxTimestamp) / 1000.0;

      if (deltaSec > 0 && deltaBytes >= 0 && deltaBytes < 100000000) {
        final newThroughput = (deltaBytes * 8) / (deltaSec * 1000000.0);
        // EMA smoothing
        _lastThroughput = (_lastThroughput * 0.7) + (newThroughput * 0.3);
        _hasThroughput  = true;

        print('[TaskHandler] throughput=${_lastThroughput.toStringAsFixed(2)} Mbps '
              '(delta=${deltaBytes}B in ${deltaSec.toStringAsFixed(2)}s)');
      } else {
        print('[TaskHandler] delta tidak valid: bytes=$deltaBytes sec=$deltaSec');
      }
    } else {
      print('[TaskHandler] init throughput sample pertama RX=$rxBytes');
    }

    _lastRxBytes     = rxBytes;
    _lastRxTimestamp = timestampMs;
  }

  // ═══════════════════════════════════════════════════════════════
  // POLL QoS
  // ═══════════════════════════════════════════════════════════════

  Future<void> _runPoll() async {
    if (_isPollBusy) return;
    _isPollBusy = true;

    try {
      final connected = await NetworkService.isWifiConnected();
      if (!connected) {
        print('[TaskHandler] WiFi tidak terhubung, skip poll');
        return;
      }

      // Jalankan probe dan snapshot paralel
      final results = await Future.wait([
        NetworkService.probeDelayJitter(),
        NetworkService.getWifiSnapshot(),
      ]);

      final probe    = results[0] as ProbeResult;
      final snapshot = results[1] as WiFiSnapshot;

      // Cache info WiFi untuk dikirim ke UI
      _cachedSSID = snapshot.ssid;
      _cachedIP   = snapshot.ip;
      _cachedBand = snapshot.band;

      // Throughput: pakai nilai terakhir, fallback 0 jika belum siap
      final throughputValue = _hasThroughput ? _lastThroughput : 0.0;

      final qos = DataQoS(
        timestamp:  DateTime.now(),   // ✅ Selalu fresh timestamp
        throughput: throughputValue,
        delay:      probe.delayMs,
        jitter:     probe.jitterMs,
        sinr:       snapshot.sinrDb,
      );

      if (!_isValidQoS(qos)) {
        print('[TaskHandler] data invalid, skip insert');
        return;
      }

      // Insert ke DB — timestamp dari DataQoS, bukan override
      final idQos = await DBHelper.insertQoS(qos.toMap());
      _latestQoS = qos.copyWith(idQos: idQos);

      _exportBufferCount++;
      print('[TaskHandler] poll OK id_qos=$idQos '
            'T=${throughputValue.toStringAsFixed(2)} '
            'D=${probe.delayMs.toStringAsFixed(1)} '
            'J=${probe.jitterMs.toStringAsFixed(1)} '
            'SINR=${snapshot.sinrDb.toStringAsFixed(1)}');

    } catch (e) {
      print('[TaskHandler] poll ERROR: $e');
    } finally {
      _isPollBusy = false;
    }
  }

  bool _isValidQoS(DataQoS q) {
    return q.throughput.isFinite &&
        q.delay.isFinite &&
        q.jitter.isFinite &&
        q.sinr.isFinite;
  }

  // ═══════════════════════════════════════════════════════════════
  // KIRIM DATA KE MAIN ISOLATE
  // ═══════════════════════════════════════════════════════════════

  void _sendToMain() {
    final latest = _latestQoS;

    FlutterForegroundTask.sendDataToMain({
      'hasData':    latest != null,
      'throughput': latest?.throughput ?? 0.0,
      'delay':      latest?.delay ?? 0.0,
      'jitter':     latest?.jitter ?? 0.0,
      'sinr':       latest?.sinr ?? 0.0,
      'timestamp':  latest?.timestamp.toIso8601String() ?? '',
      'mlLen':      _mlBufferCount,
      'exportLen':  _exportBufferCount,
      'prediction': _lastPrediction,
      'ssid':       _cachedSSID,
      'ip':         _cachedIP,
      'band':       _cachedBand,
    });

    // Update notifikasi foreground
    if (latest != null) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'QoS Monitoring Aktif',
        notificationText:
            'T:${latest.throughput.toStringAsFixed(1)} Mbps '
            '| D:${latest.delay.toStringAsFixed(0)} ms',
      );
    }
  }
}