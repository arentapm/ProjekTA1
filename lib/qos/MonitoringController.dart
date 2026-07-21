import '../models/data_qos.dart';
import '../database/db_helper.dart';
import '../services/ml_service.dart';

class MonitoringController {

  // =========================================================
  // SINGLETON
  // =========================================================

  static final MonitoringController _instance =
      MonitoringController._internal();

  factory MonitoringController() => _instance;

  MonitoringController._internal();

  // =========================================================
  // REALTIME DATA
  // =========================================================

  DataQoS? _latestFromService;

  String _cachedSSID = 'Unknown';
  String _cachedIP   = '0.0.0.0';
  String _cachedBand = 'Unknown';

  int _exportBufferLength = 0;

  // =========================================================
  // FORECAST RESULT
  // =========================================================

  List<double> forecastResult = [];

  String lastModelName = 'MSSA-LSTM';

  DateTime? lastForecastTime;

  // =========================================================
  // HISTORY
  // =========================================================

  final List<DataQoS> history = [];

  // =========================================================
  // GETTERS
  // =========================================================

  DataQoS? get latest => _latestFromService;

  String get cachedSSID => _cachedSSID;

  String get cachedIP => _cachedIP;

  String get cachedBand => _cachedBand;

  int get exportBufferLength => _exportBufferLength;

// =========================================================
  // SKOR PER PARAMETER (1-4) 
  // Python (score_throughput / score_delay / score_jitter / score_sinr)
  // =========================================================

  int _scoreThroughput(double x) {
    if (x >= 75) return 4;
    if (x >= 50) return 3;
    if (x >= 25) return 2;
    return 1;
  }

  int _scoreDelay(double x) {
    if (x < 150) return 4;
    if (x < 300) return 3;
    if (x < 450) return 2;
    return 1;
  }

  int _scoreJitter(double x) {
    if (x == 0) return 4;
    if (x < 75) return 3;
    if (x <= 125) return 2;
    return 1;
  }

  int _scoreSinr(double x) {
    if (x > 20) return 4;
    if (x >= 15) return 3;
    if (x >= 0) return 2;
    return 1;
  }

  // =========================================================
  // QOS INDEX CALCULATION

  //   1. Setiap parameter mentah -> skor kategorikal 1-4
  //   2. Rata-rata skor (avg)
  //   3. avg -> persentase QoS via mapping piecewise 25-100
  //
  // =========================================================

  double calculateQoSIndex(DataQoS d) {
    final scores = [
      _scoreThroughput(d.throughput),
      _scoreDelay(d.delay),
      _scoreJitter(d.jitter),
      _scoreSinr(d.sinr),
    ];

    final avg =
        scores.reduce((a, b) => a + b) / scores.length;

    double qos;
    if (avg >= 3.8) {
      qos = 95 + ((avg - 3.8) / (4.0 - 3.8)) * 5;
    } else if (avg >= 3.0) {
      qos = 75 + ((avg - 3.0) / (3.79 - 3.0)) * (94.75 - 75);
    } else if (avg >= 2.0) {
      qos = 50 + ((avg - 2.0) / (2.99 - 2.0)) * (74.75 - 50);
    } else {
      qos = 25 + ((avg - 1.0) / (1.99 - 1.0)) * (49.75 - 25);
    }

    return qos.clamp(25, 100);
  }

  // =========================================================
  // REALTIME QOS INDEX
  // =========================================================

  double? get latestQoSIndex {

    if (_latestFromService == null) {
      return null;
    }

    return calculateQoSIndex(
      _latestFromService!,
    );
  }

  // =========================================================
  // UPDATE FROM FOREGROUND SERVICE
  // =========================================================

  void updateFromServiceData(
    Map<String, dynamic> data,
  ) {

    final hasData =
        data['hasData'] as bool? ?? false;

    if (hasData) {

      final ts =
          data['timestamp'] as String?;

      _latestFromService = DataQoS(

        timestamp:
            ts != null && ts.isNotEmpty
                ? DateTime.parse(ts)
                : DateTime.now(),

        throughput:
            (data['throughput'] as num?)
                    ?.toDouble() ??
                0.0,

        delay:
            (data['delay'] as num?)
                    ?.toDouble() ??
                0.0,

        jitter:
            (data['jitter'] as num?)
                    ?.toDouble() ??
                0.0,

        sinr:
            (data['sinr'] as num?)
                    ?.toDouble() ??
                0.0,
      );

      // =====================================================
      // LIMIT MEMORY
      // =====================================================

      if (history.length >= 300) {
        history.removeAt(0);
      }

      history.add(
        _latestFromService!,
      );
    }

    // =======================================================
    // CACHE WIFI INFO
    // =======================================================

    _cachedSSID =
        data['ssid'] as String? ??
            'Unknown';

    _cachedIP =
        data['ip'] as String? ??
            '0.0.0.0';

    _cachedBand =
        data['band'] as String? ??
            'Unknown';

    _exportBufferLength =
        data['exportLen'] as int? ?? 0;
  }

  // =========================================================
  // LOAD SQLITE HISTORY
  // =========================================================

  Future<void> loadHistoryFromDB({
    int days = 7,
  }) async {

    try {

      final rows =
          await DBHelper.getHistory(
        days: days,
      );

      history
        ..clear()
        ..addAll(rows);

      print(
        '[Controller] '
        'History loaded: ${history.length}',
      );

    } catch (e) {

      print(
        '[Controller] '
        'loadHistoryFromDB ERROR: $e',
      );
    }
  }

  // =========================================================
  // RUN FORECAST
  // =========================================================

  Future<bool> runForecast({
    int days = 7,
  }) async {

    print('RUN FORECAST DIPANGGIL');
    try {

      print(
        '[Forecast] Loading data...',
      );

      // =====================================================
      // LOAD SQLITE
      // =====================================================

      final rows =
          await DBHelper.getHistory(
        days: days,
      );

      print(
        '[Forecast] DB Rows=${rows.length}',
      );

      // =====================================================
      // VALIDATION
      // =====================================================

      if (rows.length < 110) {

        print(
          '[Forecast] Need minimum 110 rows',
        );

        return false;
      }

      // =====================================================
      // PAYLOAD
      // =====================================================
      final inputData = rows.map((r) {

        return [

          r.throughput.toDouble(),

          r.delay.toDouble(),

          r.jitter.toDouble(),

          r.sinr.toDouble(),

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

        print(
          '[Forecast] Backend NULL',
        );

        return false;
      }

      // =====================================================
      // RESULT
      // =====================================================

      forecastResult =
          List<double>.from(
        result['result'] ?? [],
      );

      lastModelName =
          result['model'] ??
              'MSSA-LSTM';

      lastForecastTime =
          DateTime.now();

      print(
        '[Forecast] SUCCESS '
        '${forecastResult.length} points',
      );

      return true;

    } catch (e) {

      print(
        '[Forecast] ERROR: $e',
      );

      return false;
    }
  }

  // =========================================================
  // CLEAR FORECAST
  // =========================================================

  void clearForecast() {

    forecastResult.clear();

    lastForecastTime = null;
  }

  // =========================================================
  // CLEAR ALL
  // =========================================================

  void clearAll() {

    history.clear();

    forecastResult.clear();

    _latestFromService = null;

    lastForecastTime = null;
  }
}