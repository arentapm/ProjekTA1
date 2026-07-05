import 'dart:async';

import '../database/db_helper.dart';
import '../services/ml_service.dart';

class ForecastController {

  // singleton
  static final ForecastController _instance =
      ForecastController._internal();

  factory ForecastController() => _instance;

  ForecastController._internal();

  List<Map<String, dynamic>> latestForecast = [];
  bool    isForecasting = false;
  double? jobProgress;
  String  modelName = 'MSSA-LSTM';

  // =========================================================
  // RUN HISTORICAL FORECAST (tetap, dipakai /predict)
  // =========================================================
  Future<bool> runForecast({
    int historyDays    = 7,
    int horizonMinutes = 60,
  }) async {
    if (isForecasting) return false;
    isForecasting = true;

    try {
      final history = await DBHelper.getHistory(days: historyDays);

      if (history.length < 110) {
        print('[Forecast] data tidak cukup');
        return false;
      }

      final inputData = history.map((qos) => [
        qos.throughput.toDouble(),
        qos.delay.toDouble(),
        qos.jitter.toDouble(),
        qos.sinr.toDouble(),
      ]).toList();

      final result = await MLService.runForecast(inputData: inputData);

      if (result == null) {
        print('[Forecast] backend gagal');
        return false;
      }

      latestForecast = List<Map<String, dynamic>>.from(result['result']);
      modelName      = result['model'] ?? 'MSSA-LSTM';

      for (final item in latestForecast) {
        final int    index = item['forecast_index'] ?? 0;
        final double qos   = (item['predicted_qos'] as num).toDouble();

        await DBHelper.insertForecast(
          forecastTime:    DateTime.now().add(Duration(minutes: (index + 1) * horizonMinutes)),
          predictedQos:    qos,
          horizonMinutes:  horizonMinutes,
          intervalMinutes: horizonMinutes,
          modelName:       modelName,
        );
      }

      print('[Forecast] sukses ${latestForecast.length} titik');
      return true;

    } catch (e) {
      print('[Forecast] ERROR: $e');
      return false;
    } finally {
      isForecasting = false;
    }
  }

  // =========================================================
  // RUN FUTURE FORECAST — ASYNC JOB + POLLING
  //
  // FIX: `intervalMinutes` sekarang diteruskan ke
  // MLService.startForecastFutureJob(), sehingga backend hanya
  // menjalankan step yang relevan dengan mode yang dipilih user:
  //   - 5  menit -> 300 step   (cepat, cocok didemokan)
  //   - 30 menit -> 4 titik x 30 menit = total 2 jam
  //
  // Return:
  //   {
  //     'status'         : 'success',
  //     'predictions'    : List<double>,   // 1 nilai (5m) atau 4 nilai (30m)
  //     'predictionsDetail': List<double>, // 300 titik grafik (hanya interval 5m)
  //     'detailLabels'   : List<String>,   // ['t+1s'..'t+300s'] (hanya interval 5m)
  //     'forecastTimes'  : List<DateTime>,
  //     'intervalMinutes': int,
  //   }
  //   {'status': 'waiting', 'message': '...'}  → data belum cukup
  //   {'status': 'loading', 'message': '...'}  → model masih loading
  //   {'status': 'error',   'message': '...'}  → forecast gagal
  //   null                                      → gagal total (network dsb)
  // =========================================================
  Future<Map<String, dynamic>?> runFutureForecast({
    int intervalMinutes = 30,
    void Function(double progress)? onProgress,
    Duration pollInterval   = const Duration(seconds: 5),
    int maxPollFailures     = 6,
  }) async {
    if (isForecasting) return null;
    isForecasting = true;
    jobProgress   = 0;

    try {
      // Ambil 110 baris terakhir langsung dari SQL
      final last110 = await DBHelper.getQoSHistoryRecent(limit: 110);

      if (last110.length < 110) {
        return {
          'status' : 'waiting',
          'message': 'Data belum cukup: ${last110.length}/110',
        };
      }

      final inputData = last110.map((row) => [
        (row['throughput'] as num).toDouble(),
        (row['delay']      as num).toDouble(),
        (row['jitter']     as num).toDouble(),
        (row['sinr']       as num).toDouble(),
      ]).toList();

      // =====================================================
      // STEP 1 — START JOB
      // FIX: kirim intervalMinutes supaya backend hanya
      // menjalankan step yang dibutuhkan mode ini.
      // =====================================================
      final startResult = await MLService.startForecastFutureJob(
        inputData: inputData,
        intervalMinutes: intervalMinutes,
      );

      if (startResult == null) return null;

      if (startResult['status'] == 'waiting' ||
          startResult['status'] == 'loading') {
        return startResult;
      }

      if (startResult['status'] != 'queued' || startResult['job_id'] == null) {
        return {'status': 'error', 'message': 'Gagal memulai forecast job'};
      }

      final jobId = startResult['job_id'] as String;
      print('[Forecast] Job dimulai: $jobId (interval: $intervalMinutes menit)');

      // =====================================================
      // STEP 2 — POLLING
      // =====================================================
      Map<String, dynamic>? finalResult;
      int consecutiveFailures = 0;

      while (true) {
        await Future.delayed(pollInterval);

        final poll = await MLService.pollForecastFutureJob(jobId: jobId);

        if (poll == null) {
          consecutiveFailures++;
          print('[Forecast] Polling gagal ($consecutiveFailures/$maxPollFailures)');
          if (consecutiveFailures >= maxPollFailures) {
            return {
              'status' : 'error',
              'message': 'Koneksi ke server terputus saat menunggu hasil forecast',
            };
          }
          continue;
        }

        consecutiveFailures = 0;
        final status = poll['status'] as String?;

        if (status == 'queued' || status == 'processing') {
          final progress = (poll['progress'] as num?)?.toDouble() ?? 0;
          jobProgress = progress;
          onProgress?.call(progress);
          continue;
        }

        if (status == 'error') {
          return {
            'status' : 'error',
            'message': poll['message'] as String? ?? 'Forecast gagal diproses',
          };
        }

        if (status == 'success') {
          jobProgress = 100;
          onProgress?.call(100);
          finalResult = poll;
          break;
        }

        return {
          'status' : 'error',
          'message': 'Status job tidak dikenal: $status',
        };
      }

      // =====================================================
      // STEP 3 — PROSES HASIL SUKSES
      //
      // interval 5  -> pakai predictions_5m_detail (300 titik)
      // interval 30 -> pakai predictions_30m (4 titik: t+30m..t+120m)
      // =====================================================
      List<double> predictions       = [];
      List<double> predictionsDetail = [];
      List<String> detailLabels      = [];

      if (intervalMinutes == 5) {
        // 300 titik t+1s..t+300s untuk grafik
        final rawDetail = finalResult!['predictions_5m_detail'] as List<dynamic>;
        predictionsDetail = rawDetail
            .map((e) => (e['qos_index'] as num).toDouble())
            .toList();
        detailLabels = rawDetail
            .map((e) => e['label'] as String)
            .toList();
        // Nilai final = titik terakhir (t+300 = t+5m) — untuk kartu hero & DB
        predictions = [predictionsDetail.last];
      } else {
        // 4 titik t+30m..t+120m (total cakupan 2 jam)
        final raw = finalResult!['predictions_30m'] as List<dynamic>;
        predictions = raw
            .map((e) => (e['qos_index'] as num).toDouble())
            .toList();
      }

      await DBHelper.clearOldForecast();

      final now = DateTime.now();

      // forecastTimes: 5m → 1 titik (t+5m), 30m → 4 titik (t+30m..t+120m)
      final List<DateTime> forecastTimes = intervalMinutes == 5
          ? [now.add(const Duration(minutes: 5))]
          : List.generate(
              predictions.length,
              (i) => now.add(Duration(minutes: (i + 1) * intervalMinutes)),
            );

      // Simpan ke DB
      for (int i = 0; i < predictions.length; i++) {
        await DBHelper.insertForecast(
          forecastTime:    forecastTimes[i],
          predictedQos:    predictions[i],
          horizonMinutes:  (i + 1) * intervalMinutes,
          intervalMinutes: intervalMinutes,
          modelName:       'MSSA-LSTM',
        );
      }

      return {
        ...finalResult!,
        'predictions'      : predictions,        // 1 nilai (5m) atau 4 nilai (30m)
        'predictionsDetail': predictionsDetail,  // 300 titik (hanya 5m, else kosong)
        'detailLabels'     : detailLabels,       // ['t+1s'..'t+300s'] (hanya 5m)
        'forecastTimes'    : forecastTimes,
        'intervalMinutes'  : intervalMinutes,
      };

    } catch (e) {
      print('[Forecast] ERROR: $e');
      return {'status': 'error', 'message': 'Error: $e'};
    } finally {
      isForecasting = false;
      jobProgress   = null;
    }
  }

  // =========================================================
  // CLEAR
  // =========================================================
  void clearForecast() {
    latestForecast.clear();
  }
}