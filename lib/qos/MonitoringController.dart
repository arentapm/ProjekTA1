import 'dart:async';
import '../models/data_qos.dart';
import '../services/network_service.dart';
import '../services/delay_service.dart';
import 'qos_calculator.dart';
import '../database/db_helper.dart';
import '../services/qos_predictor.dart';

class MonitoringController {

  // ================= TIMER =================
  Timer? _timer;               // untuk collect data tiap detik
  Timer? _predictionTimer;     // untuk prediksi tiap 30 menit

  bool monitoringStatus = false;
  bool wifiStatus = false;

  bool _predicting = false;    // lock biar gak double request

  final ThroughputCalculator _throughputCalculator = ThroughputCalculator();

  double _lastDelay = 0;

  static const int windowSize = 110;

  // ================= WIFI CHECK =================
  Future<void> checkWifiConnection() async {
    wifiStatus = await NetworkService.isWifiConnected();
  }

  // ================= START MONITORING =================
  Future<void> startMonitoring(
    void Function(DataQoS qos) onData,
    void Function(Map<String, double> prediction) onPrediction, // 🔥 FIX: multi-output
  ) async {

    await checkWifiConnection();

    if (!wifiStatus) return;

    monitoringStatus = true;

    // ================= 1. COLLECT DATA PER DETIK =================
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {

      if (!monitoringStatus) return;

      try {

        // ambil data QoS real-time
        final qos = await collectQoSData();

        // simpan ke database
        await saveQoSData(qos);

        // kirim ke UI (realtime monitoring)
        onData(qos);

      } catch (e) {
        print("Monitoring Error: $e");
      }

    });

    // ================= 2. PREDIKSI TIAP 30 MENIT =================
    _predictionTimer = Timer.periodic(const Duration(minutes: 30), (_) async {

      await runPrediction(onPrediction);

    });

  }

  // ================= STOP MONITORING =================
  void stopMonitoring() {
    monitoringStatus = false;
    _timer?.cancel();
    _predictionTimer?.cancel();
  }

  // ================= PREDICTION FUNCTION =================
  Future<void> runPrediction(
    void Function(Map<String, double>) onPrediction
  ) async {

    // 🔒 cegah request ganda
    if (_predicting) return;

    final history = await DBHelper.getLastNQoS(windowSize);

    // 🔥 pastikan data cukup untuk LSTM
    if (history.length < windowSize) {
      print("⚠️ Data belum cukup untuk prediksi");
      return;
    }

    _predicting = true;

    try {

      // ================= PREPARE SEQUENCE =================
      final sequence = history.map((e) {

        return [

          // 🔥 HARUS SAMA DENGAN TRAINING
          e.throughput,
          e.delay,
          e.jitter,
          e.sinr

        ];

      }).toList();

      // ================= CALL BACKEND =================
      final prediction = await MLService.predict(
        sequence: sequence,
      );

      print("📊 HASIL PREDIKSI: $prediction");

      // ================= SEND KE UI =================
      if (prediction != null) {
        onPrediction(prediction);
      }

    } catch (e) {

      print("Prediction Error: $e");

    }

    _predicting = false;
  }

  // ================= COLLECT DATA =================
  Future<DataQoS> collectQoSData() async {

    final now = DateTime.now();

    // ================= THROUGHPUT =================
    final double throughput = await _throughputCalculator.getThroughput();

    // ================= DELAY =================
    double delay = await DelayService.measureDelay();

    // 🔥 VALIDASI DELAY BIAR TIDAK ERROR
    if (delay.isNaN || delay <= 0) {
      delay = 1;
    }

    // ================= JITTER =================
    double jitter = 0;

    if (_lastDelay != 0) {

      // 🔥 FIX: pakai delta langsung (bukan akumulasi)
      jitter = QoSCalculator.calculateJitter(_lastDelay, delay);

    }

    _lastDelay = delay;

    // ================= SIGNAL =================
    final signalPower = await NetworkService.getSignalPower();
    final freq = await NetworkService.getFrequency();
    final is5GHz = NetworkService.is5GHz(freq);

    final sinr = QoSCalculator.calculateSINR(
      signalPowerDbm: signalPower,
      interferenceDbm: NetworkService.getInterference(is5GHz: is5GHz),
      noiseDbm: NetworkService.getNoiseFloor(is5GHz: is5GHz),
    );

    return DataQoS(
      timestamp: now,
      throughput: throughput,
      delay: delay,
      jitter: jitter,
      sinr: sinr,
    );
  }

  // ================= SAVE DATABASE =================
  Future<void> saveQoSData(DataQoS qos) async {

    await DBHelper.insertQoS({

      // 🔥 gunakan ISO format biar urutan waktu valid
      "timestamp": qos.timestamp.toIso8601String(),

      "throughput": qos.throughput,
      "delay": qos.delay,
      "jitter": qos.jitter,
      "sinr": qos.sinr,
    });

  }

}