import 'dart:async';
import '../models/data_qos.dart';
import '../database/db_helper.dart';

// ════════════════════════════════════════════════════════════════════
// MonitoringController — HANYA untuk main isolate (UI state)
//
// FIX: Controller ini tidak lagi menjalankan poll atau timer sendiri.
// Semua pengukuran dilakukan oleh QosTaskHandler di foreground service.
// Controller ini hanya menyimpan data terakhir yang diterima dari
// sendDataToMain, dan menyediakan getter untuk UI.
// ════════════════════════════════════════════════════════════════════

class MonitoringController {
  static final MonitoringController _instance = MonitoringController._internal();
  factory MonitoringController() => _instance;
  MonitoringController._internal();

  // Data terakhir dari foreground service
  DataQoS? _latestFromService;
  double? lastPrediction;
  Map<String, dynamic>? lastEvaluation;

  String _cachedSSID = 'Unknown';
  String _cachedIP   = '0.0.0.0';
  String _cachedBand = 'Unknown';

  int _mlBufferLength    = 0;
  int _exportBufferLength = 0;

  // ── Getters ───────────────────────────────────────────────────
  DataQoS? get latest          => _latestFromService;
  String   get cachedSSID      => _cachedSSID;
  String   get cachedIP        => _cachedIP;
  String   get cachedBand      => _cachedBand;
  int      get mlBufferLength  => _mlBufferLength;
  int      get exportBufferLength => _exportBufferLength;

  // ── History untuk chart (dari DB langsung) ────────────────────
  final List<DataQoS> history = [];

  // ── Update dari data yang diterima foreground service ─────────
  // Panggil ini dari onReceiveTaskData di widget/page utama
  void updateFromServiceData(Map<String, dynamic> data) {
    final hasData = data['hasData'] as bool? ?? false;

    if (hasData) {
      final ts = data['timestamp'] as String?;
      _latestFromService = DataQoS(
        timestamp:  ts != null && ts.isNotEmpty
                      ? DateTime.parse(ts)
                      : DateTime.now(),
        throughput: (data['throughput'] as num?)?.toDouble() ?? 0.0,
        delay:      (data['delay'] as num?)?.toDouble() ?? 0.0,
        jitter:     (data['jitter'] as num?)?.toDouble() ?? 0.0,
        sinr:       (data['sinr'] as num?)?.toDouble() ?? 0.0,
      );

      if (history.length >= 150) history.removeAt(0);
      history.add(_latestFromService!);
    }

    _cachedSSID          = data['ssid'] as String? ?? 'Unknown';
    _cachedIP            = data['ip']   as String? ?? '0.0.0.0';
    _cachedBand          = data['band'] as String? ?? 'Unknown';
    _mlBufferLength      = data['mlLen'] as int? ?? 0;
    _exportBufferLength  = data['exportLen'] as int? ?? 0;
    lastPrediction       = (data['prediction'] as num?)?.toDouble();
    lastEvaluation       = data['evaluation'] as Map<String, dynamic>?;
  }

  // ── Load history dari DB untuk chart ─────────────────────────
  Future<void> loadHistoryFromDB({int days = 1}) async {
    try {
      final rows = await DBHelper.getHistory(days: days);
      history.clear();
      history.addAll(rows);
      print('[Controller] loadHistoryFromDB: ${history.length} baris');
    } catch (e) {
      print('[Controller] loadHistoryFromDB error: $e');
    }
  }

  void clearHistory() {
    history.clear();
    _latestFromService = null;
    lastPrediction     = null;
    lastEvaluation     = null;
  }
}