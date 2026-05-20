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
  // QOS INDEX CALCULATION
  // =========================================================
  //
  // WAJIB sama dengan formula training backend
  //
  // =========================================================

  double calculateQoSIndex(DataQoS d) {

    // Throughput normalization
    final tNorm =
        (d.throughput / 20000)
            .clamp(0.0, 1.0);

    // Delay normalization
    final dNorm =
        1 -
        (d.delay / 600)
            .clamp(0.0, 1.0);

    // Jitter normalization
    final jNorm =
        1 -
        (d.jitter / 300)
            .clamp(0.0, 1.0);

    // SINR normalization
    final sNorm =
        (d.sinr / 40)
            .clamp(0.0, 1.0);

    final qos = (

      tNorm * 0.35 +

      dNorm * 0.30 +

      jNorm * 0.20 +

      sNorm * 0.15

    ) * 100;

    return qos.clamp(0, 100);
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