import 'dart:async';
import '../models/data_qos.dart';
import '../services/network_service.dart';
import '../services/delay_service.dart';
import 'qos_calculator.dart';
import '../database/db_helper.dart';

class MonitoringController {

  Timer? _timer;

  bool monitoringStatus = false;
  bool wifiStatus = false;

  int _lastBytes = 0;
  double _lastDelay = 0;
  double _totalJitter = 0;
  int _jitterSamples = 0;

  // ================= WIFI =================
  Future<void> checkWifiConnection() async {
    wifiStatus = await NetworkService.isWifiConnected();
  }

  // ================= START MONITORING =================
  Future<void> startMonitoring(void Function(DataQoS) onData) async {
    await checkWifiConnection();
    if (!wifiStatus) return;

    monitoringStatus = true;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {

      if (!monitoringStatus) return;

      final qos = await collectQoSData();

      await saveQoSData(qos);

      onData(qos);

    });
  }

  // ================= STOP MONITORING =================
  void stopMonitoring() {
    monitoringStatus = false;
    _timer?.cancel();
  }

  // ================= COLLECT DATA =================
  Future<DataQoS> collectQoSData() async {

    final now = DateTime.now();

    // ================= NETWORK COUNTER =================
    final currentBytes = await NetworkService.getTotalBytes();

    // ================= FIRST SAMPLE =================
    if (_lastBytes == 0) {

      _lastBytes = currentBytes;

      final delay = await DelayService.measureDelay();
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
        throughput: 0,
        delay: delay,
        jitter: 0,
        sinr: sinr,
      );
    }

    // ================= THROUGHPUT =================
    final bytesDelta = (currentBytes - _lastBytes).clamp(0, 1 << 62);
    _lastBytes = currentBytes;

    final double throughput =
        QoSCalculator.calculateThroughput(bytesDelta, 1);

    // ================= DELAY =================
    final delay = await DelayService.measureDelay();

    // ================= JITTER =================
    double jitterAvg = 0;

    if (_lastDelay != 0) {

      final delta = (delay - _lastDelay).abs();

      _totalJitter += delta;

      _jitterSamples++;

      jitterAvg = _totalJitter / _jitterSamples;
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
      jitter: jitterAvg,
      sinr: sinr,
    );
  }

  // ================= SAVE DATABASE =================
  Future<void> saveQoSData(DataQoS qos) async {

    await DBHelper.insertQoS({

      "timestamp": qos.timestamp.toIso8601String(),
      "throughput": qos.throughput,
      "delay": qos.delay,
      "jitter": qos.jitter,
      "sinr": qos.sinr,

    });

  }
}