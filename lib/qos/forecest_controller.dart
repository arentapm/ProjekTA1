import '../database/db_helper.dart';
import '../services/ml_service.dart';

class ForecastController {

  // singleton
  static final ForecastController _instance =
      ForecastController._internal();

  factory ForecastController() => _instance;

  ForecastController._internal();

  // hasil forecast terakhir
  List<Map<String, dynamic>> latestForecast = [];

  bool isForecasting = false;

  String modelName = 'MSSA-LSTM';

  // =========================================================
  // RUN HISTORICAL FORECAST
  // =========================================================
  Future<bool> runForecast({
    int historyDays = 7,
    int horizonMinutes = 60,
  }) async {

    if (isForecasting) return false;

    isForecasting = true;

    try {

      // =====================================================
      // LOAD HISTORICAL DATA
      // =====================================================
      final history = await DBHelper.getHistory(
        days: historyDays,
      );

      if (history.length < 110) {

        print('[Forecast] data tidak cukup');

        return false;
      }

      // =====================================================
      // FORMAT PAYLOAD
      // =====================================================
      final inputData = history.map((qos) {

        return [

          qos.throughput.toDouble(),

          qos.delay.toDouble(),

          qos.jitter.toDouble(),

          qos.sinr.toDouble(),

        ];

      }).toList();

      // =====================================================
      // CALL BACKEND
      // =====================================================
      final result =
      await MLService.runForecast(

      inputData: inputData,
    );

      if (result == null) {

        print('[Forecast] backend gagal');

        return false;
      }

      // =====================================================
      // SAVE RESULT
      // =====================================================
      latestForecast =
          List<Map<String, dynamic>>.from(
              result['result']
          );

      modelName =
          result['model']
          ?? 'MSSA-LSTM';

      // =====================================================
      // SAVE TO SQLITE
      // =====================================================
      for (final item in latestForecast) {

        final int index =
            item['forecast_index'] ?? 0;

        final double qos =
            (item['predicted_qos'] as num)
                .toDouble();

        await DBHelper.insertForecast(

          // generate waktu sendiri
          forecastTime: DateTime.now().add(
            Duration(minutes: index),
          ),

          predictedQos: qos,

          horizonMinutes: horizonMinutes,

          modelName: modelName,
        );
      }

      print(
        '[Forecast] sukses '
        '${latestForecast.length} titik'
      );

      return true;

    } catch (e) {

      print('[Forecast] ERROR: $e');

      return false;

    } finally {

      isForecasting = false;
    }
  }

  // TAMBAH method baru di ForecastController

Future<Map<String, dynamic>?> runFutureForecast() async {

  if (isForecasting) return null;
  isForecasting = true;

  try {
    // Ambil SEMUA data dari SQLite, tidak dibatasi hari
    final history = await DBHelper.getQoSHistoryAsc(); // ambil semua

    if (history.length < 111) {
      print('[Forecast] data belum cukup: ${history.length}/111');
      return {'status': 'waiting', 'message': 'Data belum cukup: ${history.length}/111'};
    }

    // Format input
    final inputData = history.map((row) => [
      (row['throughput'] as num).toDouble(),
      (row['delay']      as num).toDouble(),
      (row['jitter']     as num).toDouble(),
      (row['sinr']       as num).toDouble(),
    ]).toList();

    // Panggil endpoint baru
    final result = await MLService.runForecastFuture(inputData: inputData);

    if (result == null || result['status'] != 'success') return result;

    final predictions = result['predictions'] as List<double>;

    // =====================================================
    // SIMPAN KE SQLITE
    // Setiap titik = interval 30 menit
    // =====================================================
    await DBHelper.clearOldForecast(); // bersihkan forecast lama

    final now = DateTime.now();
    for (int i = 0; i < predictions.length; i++) {
      await DBHelper.insertForecast(
        forecastTime   : now.add(Duration(minutes: (i + 1) * 30)),
        predictedQos   : predictions[i],
        horizonMinutes : (i + 1) * 30,
        modelName      : 'MSSA-LSTM',
      );
    }

    print('[Forecast] Tersimpan ${predictions.length} titik prediksi');
    return result;

  } catch (e) {
    print('[Forecast] ERROR: $e');
    return null;
  } finally {
    isForecasting = false;
  }
}
  
  // =========================================================
  // LOAD FORECAST FROM DB
  // =========================================================
  Future<void> loadForecastHistory() async {

    latestForecast =
        await DBHelper.getForecastHistory();

    print(
      '[Forecast] loaded '
      '${latestForecast.length} forecast'
    );
  }

  // =========================================================
  // CLEAR
  // =========================================================
  void clearForecast() {

    latestForecast.clear();
  }
}