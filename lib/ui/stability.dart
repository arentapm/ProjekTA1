import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math' as math;

import '../models/data_qos.dart';
import '../qos/MonitoringController.dart';
import '../database/db_helper.dart';
import '../qos/forecest_controller.dart';


// =========================================================
// COLORS – Light Modern Theme
// =========================================================
const _bgDark        = Color(0xFFF8FAFC);
const _bgCard        = Color(0xFFFFFFFF);
const _bgCardAlt     = Color(0xFFF1F5F9);
const _accent        = Color(0xFF0066FF);
const _accentGlow    = Color(0x1A0066FF);
const _colorGreen    = Color(0xFF00C853);
const _colorGreenBg  = Color(0x1A00C853);
const _colorAmber    = Color(0xFFFFB300);
const _colorAmberBg  = Color(0x1AFFB300);
const _colorRed      = Color(0xFFFF3D00);
const _colorRedBg    = Color(0x1AFF3D00);
const _textPrimary   = Color(0xFF1E2937);
const _textSecondary = Color(0xFF64748B);
const _divider       = Color(0xFFE2E8F0);

// =========================================================
// STATUS MODEL
// =========================================================
enum QoSStatus { excellent, good, fair, poor, unknown }

QoSStatus _statusFromValue(double? v) {
  if (v == null) return QoSStatus.unknown;
  if (v >= 80)   return QoSStatus.excellent;
  if (v >= 60)   return QoSStatus.good;
  if (v >= 40)   return QoSStatus.fair;
  return QoSStatus.poor;
}

// =========================================================
// INTERVAL FORECAST MODEL
// =========================================================
class _IntervalForecast {
  final String    label;
  final double    value;
  final QoSStatus status;
  final String    timeLabel;
  final DateTime  time;

  const _IntervalForecast({
    required this.label,
    required this.timeLabel,
    required this.time,
    required this.value,
    required this.status,
  });

  /// true kalau waktu interval ini sudah terlewat
  bool get isExpired => DateTime.now().isAfter(time);
}

// =========================================================
// CHART PAINTER
// =========================================================
class _ForecastChartPainter extends CustomPainter {
  final List<double> actualValues;
  final List<double> predictedValues;
  final int          splitIndex;
  final List<String> timeLabels;

  _ForecastChartPainter({
    required this.actualValues,
    required this.predictedValues,
    required this.splitIndex,
    required this.timeLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final allValues = [...actualValues, ...predictedValues];
    if (allValues.isEmpty) return;

    final minVal = (allValues.reduce(math.min) - 8).clamp(0.0, 90.0);
    final maxVal = (allValues.reduce(math.max) + 8).clamp(10.0, 103.0);
    final range  = (maxVal - minVal).clamp(10.0, 100.0);
    final total  = actualValues.length + predictedValues.length;
    final stepX  = size.width / math.max(1, total - 1);
    final chartH = size.height - 28.0;

    double toY(double v) =>
        chartH - ((v - minVal) / range) * chartH * 0.88 - chartH * 0.06;
    double toX(int i) => i * stepX;

    // Zone bands
    final bands = [
      [80.0, 100.0, const Color(0x0F1D9E75)],
      [60.0,  80.0, const Color(0x0C378ADD)],
      [40.0,  60.0, const Color(0x0CBA7517)],
      [ 0.0,  40.0, const Color(0x0FE24B4A)],
    ];
    for (final b in bands) {
      canvas.drawRect(
        Rect.fromLTRB(0, toY(b[1] as double), size.width, toY(b[0] as double)),
        Paint()..color = b[2] as Color,
      );
    }

    // Grid
    final gridPaint = Paint()..color = const Color(0x12000000)..strokeWidth = 0.5;
    for (final v in [25.0, 50.0, 75.0, 100.0]) {
      final y = toY(v);
      if (y >= 0 && y <= chartH) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    // Actual area
    if (actualValues.length > 1) {
      final path = Path()..moveTo(toX(0), chartH);
      for (int i = 0; i < actualValues.length; i++) {
        i == 0
            ? path.lineTo(toX(i), toY(actualValues[i]))
            : path.cubicTo(
                toX(i - 1) + stepX * 0.5, toY(actualValues[i - 1]),
                toX(i) - stepX * 0.5,     toY(actualValues[i]),
                toX(i),                    toY(actualValues[i]),
              );
      }
      path.lineTo(toX(actualValues.length - 1), chartH);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: [
              const Color(0xFF1D9E75).withOpacity(0.22),
              const Color(0xFF1D9E75).withOpacity(0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, chartH)),
      );
    }

    // Actual line
    if (actualValues.length > 1) {
      final path = Path()..moveTo(toX(0), toY(actualValues[0]));
      for (int i = 1; i < actualValues.length; i++) {
        path.cubicTo(
          toX(i - 1) + stepX * 0.5, toY(actualValues[i - 1]),
          toX(i) - stepX * 0.5,     toY(actualValues[i]),
          toX(i),                    toY(actualValues[i]),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color       = const Color(0xFF1D9E75)
          ..strokeWidth = 2.5
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round,
      );
    }

    // Split line
    final splitX    = toX(actualValues.length - 1);
    final dashPaint = Paint()..color = const Color(0x55000000)..strokeWidth = 1.0;
    double dy = 0;
    while (dy < chartH) {
      canvas.drawLine(
        Offset(splitX, dy),
        Offset(splitX, math.min(dy + 5, chartH)),
        dashPaint,
      );
      dy += 9;
    }
    final nowPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = const TextSpan(
        text: 'sekarang',
        style: TextStyle(fontSize: 9, color: Color(0x88000000), fontWeight: FontWeight.w500),
      )
      ..layout();
    nowPainter.paint(canvas, Offset(splitX + 4, 4));

    // Prediction area
    if (predictedValues.length > 1) {
      final offset = actualValues.length - 1;
      final path   = Path()..moveTo(toX(offset), chartH);
      path.lineTo(toX(offset), toY(actualValues.last));
      for (int i = 0; i < predictedValues.length; i++) {
        final xi = offset + i + 1;
        path.cubicTo(
          toX(xi - 1) + stepX * 0.5, toY(i == 0 ? actualValues.last : predictedValues[i - 1]),
          toX(xi) - stepX * 0.5,     toY(predictedValues[i]),
          toX(xi),                    toY(predictedValues[i]),
        );
      }
      path.lineTo(toX(offset + predictedValues.length), chartH);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: [
              const Color(0xFF7F77DD).withOpacity(0.20),
              const Color(0xFF7F77DD).withOpacity(0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, chartH)),
      );
    }

    // Prediction dashed line
    if (predictedValues.length > 1) {
      final offset     = actualValues.length - 1;
      final smoothPath = Path()..moveTo(toX(offset), toY(actualValues.last));
      for (int i = 0; i < predictedValues.length; i++) {
        final xi = offset + i + 1;
        smoothPath.cubicTo(
          toX(xi - 1) + stepX * 0.5, toY(i == 0 ? actualValues.last : predictedValues[i - 1]),
          toX(xi) - stepX * 0.5,     toY(predictedValues[i]),
          toX(xi),                    toY(predictedValues[i]),
        );
      }
      final metrics       = smoothPath.computeMetrics();
      const dashLen       = 8.0;
      const gapLen        = 5.0;
      final dashPaintPred = Paint()
        ..color       = const Color(0xFF7F77DD)
        ..strokeWidth = 2.5
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round;
      for (final metric in metrics) {
        double dist   = 0;
        bool   drawing = true;
        while (dist < metric.length) {
          final end = math.min(dist + (drawing ? dashLen : gapLen), metric.length);
          if (drawing) canvas.drawPath(metric.extractPath(dist, end), dashPaintPred);
          dist    = end;
          drawing = !drawing;
        }
      }
      canvas.drawCircle(
        Offset(toX(offset), toY(actualValues.last)),
        4.5,
        Paint()..color = const Color(0xFF7F77DD),
      );
      final endX = toX(offset + predictedValues.length);
      final endY = toY(predictedValues.last);
      canvas.drawCircle(Offset(endX, endY), 8,
          Paint()..color = const Color(0xFF7F77DD).withOpacity(0.18));
      canvas.drawCircle(Offset(endX, endY), 4.5,
          Paint()..color = const Color(0xFF7F77DD));
    }

    // Time labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < timeLabels.length && i < total; i++) {
      tp.text = TextSpan(
        text: timeLabels[i],
        style: const TextStyle(
          color:      Color(0xFF64748B),
          fontSize:   9.5,
          fontWeight: FontWeight.w500,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(toX(i) - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(_ForecastChartPainter old) =>
      !listEquals(old.actualValues, actualValues) ||
      !listEquals(old.predictedValues, predictedValues) ||
      old.splitIndex != splitIndex;
}

// =========================================================
// PAGE
// =========================================================
class StabilityPage extends StatefulWidget {
  final DataQoS       qos;
  final List<DataQoS> qosHistory;

  final double?                    savedPrediction;
  final List<double>               savedSeries;
  final List<Map<String, dynamic>> savedIntervals;
  final List<String>               savedTimeLabels;
  final String?                    savedModelName;
  final DateTime?                  savedForecastTime;
  final String?                    savedError;
  final DateTime? savedNextForecastAt;

  final void Function({
    required double?                    prediction,
    required List<double>               series,
    required List<Map<String, dynamic>> intervals,
    required List<String>               timeLabels,
    required String?                    modelName,
    required DateTime?                  forecastTime,
    required DateTime? nextForecastAt,
    required String?                    error,
  }) onForecastResult;

  const StabilityPage({
    super.key,
    required this.qos,
    required this.qosHistory,
    required this.onForecastResult,
    this.savedNextForecastAt,
    this.savedPrediction,
    this.savedSeries      = const [],
    this.savedIntervals   = const [],
    this.savedTimeLabels  = const [],
    this.savedModelName,
    this.savedForecastTime,
    this.savedError,
  });

  @override
  State<StabilityPage> createState() => _StabilityPageState();
}

class _StabilityPageState extends State<StabilityPage>
    with SingleTickerProviderStateMixin {
  final MonitoringController _ctrl = MonitoringController();

  double?      _prediction;
  List<double> _predictionSeries = [];
  bool         _isForecasting    = false;
  String?      _errorMessage;
  String?      _lastModelName;
  DateTime?    _lastForecastTime;
  int          _rowCount         = 0;

  List<_IntervalForecast> _intervalForecasts = [];
  List<String>            _timeLabels        = [];

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── AUTO-REFRESH ──────────────────────────────────────
  // Timer utama: cek setiap 60 detik apakah sudah waktunya
  // menjalankan forecast baru.
  Timer? _autoRefreshTimer;

  // Timer countdown: rebuild setiap detik agar sisa waktu
  // di UI selalu akurat.
  Timer? _countdownTimer;

  // Waktu forecast berikutnya dijadwalkan
  DateTime? _nextForecastAt;

  // =========================================================
  // INIT
  // =========================================================
  @override
  void initState() {
    super.initState();
    _checkRowCount();

    _prediction       = widget.savedPrediction;
    _lastModelName    = widget.savedModelName;
    _lastForecastTime = widget.savedForecastTime;
    _errorMessage     = widget.savedError;
    _predictionSeries = List<double>.from(widget.savedSeries);
    _timeLabels       = List<String>.from(widget.savedTimeLabels);
    _intervalForecasts = widget.savedIntervals
        .map((m) => _IntervalForecast(
              label:     m['label']     as String,
              timeLabel: m['timeLabel'] as String,
              time:      m['time']      as DateTime,
              value:     m['value']     as double,
              status:    m['status']    as QoSStatus,
            ))
        .toList();

    if (widget.savedNextForecastAt != null) {
      _nextForecastAt = widget.savedNextForecastAt;
    }else {
      _scheduleNextForecast();
    }

    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Mulai timer cek otomatis setiap 60 detik.
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkAndAutoRefresh(),
    );

    // Timer countdown setiap detik untuk rebuild UI sisa waktu.
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {}); // rebuild sisa waktu
      },
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _autoRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // =========================================================
  // PENJADWALAN AUTO-REFRESH
  // =========================================================

  /// Menghitung kapan forecast berikutnya harus dijalankan.
  /// Aturan: 30 menit setelah _lastForecastTime.
  /// Kalau belum ada forecast sama sekali, jadwalkan sekarang.
  void _scheduleNextForecast() {
    if (_lastForecastTime == null) {
      // Belum pernah forecast — jalankan segera setelah widget siap.
      _nextForecastAt = DateTime.now();
    } else {
      _nextForecastAt = _lastForecastTime!.add(const Duration(minutes: 30));
    }
  }

  /// Dipanggil oleh _autoRefreshTimer setiap menit.
  /// Kalau waktu sekarang sudah melewati _nextForecastAt, jalankan forecast.
  Future<void> _checkAndAutoRefresh() async {
    if (_nextForecastAt == null) return;
    if (_isForecasting)          return;

    final now = DateTime.now();
    if (now.isAfter(_nextForecastAt!) || now.isAtSameMomentAs(_nextForecastAt!)) {
      await _runForecast(isAuto: true);
    }
  }

  /// Hitung sisa detik sampai forecast berikutnya.
  /// Dipakai di UI countdown.
  Duration get _timeUntilNextForecast {
    if (_nextForecastAt == null) return Duration.zero;
    final diff = _nextForecastAt!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  // =========================================================
  // HELPERS
  // =========================================================
  List<DataQoS> _sampleEvery30Min(List<DataQoS> history) {
    if (history.isEmpty) return [];
    final result = <DataQoS>[];
    DateTime? last;
    for (final d in history) {
      final t = d.timestamp ?? DateTime.now();
      if (last == null || t.difference(last).inMinutes >= 30) {
        result.add(d);
        last = t;
      }
    }
    return result;
  }

  Future<void> _checkRowCount() async {
    final rows = await DBHelper.getHistory(days: 30);
    if (!mounted) return;
    setState(() => _rowCount = rows.length);
  }

  double _getQoSIndex(DataQoS d) => _ctrl.calculateQoSIndex(d);

  String _categoryLabel(double? v) {
    if (v == null) return 'N/A';
    if (v >= 80)   return 'SANGAT BAIK';
    if (v >= 60)   return 'BAIK';
    if (v >= 40)   return 'SEDANG';
    return 'BURUK';
  }

  Color _statusColor(QoSStatus s) {
    switch (s) {
      case QoSStatus.excellent: return _colorGreen;
      case QoSStatus.good:      return _accent;
      case QoSStatus.fair:      return _colorAmber;
      case QoSStatus.poor:      return _colorRed;
      case QoSStatus.unknown:   return _textSecondary;
    }
  }

  Color _statusBg(QoSStatus s) {
    switch (s) {
      case QoSStatus.excellent: return _colorGreenBg;
      case QoSStatus.good:      return _accentGlow;
      case QoSStatus.fair:      return _colorAmberBg;
      case QoSStatus.poor:      return _colorRedBg;
      case QoSStatus.unknown:   return _bgCardAlt;
    }
  }

  IconData _statusIcon(QoSStatus s) {
    switch (s) {
      case QoSStatus.excellent: return Icons.signal_cellular_alt_rounded;
      case QoSStatus.good:      return Icons.signal_cellular_alt_2_bar_rounded;
      case QoSStatus.fair:      return Icons.signal_cellular_alt_1_bar_rounded;
      case QoSStatus.poor:      return Icons.signal_cellular_0_bar_rounded;
      case QoSStatus.unknown:   return Icons.signal_cellular_null_rounded;
    }
  }

  String _trendLabel(List<double> series) {
    if (series.length < 3) return '—';
    final last3 = series.sublist(series.length - 3);
    final delta = last3.last - last3.first;
    if (delta > 3)  return '▲ Meningkat';
    if (delta < -3) return '▼ Menurun';
    return '● Stabil';
  }

  Color _trendColor(List<double> series) {
    if (series.length < 3) return _textSecondary;
    final delta = series.last - series[series.length - 3];
    if (delta > 3)  return _colorGreen;
    if (delta < -3) return _colorRed;
    return _colorAmber;
  }

  List<_IntervalForecast> _buildIntervals(
    List<double> series,
    DateTime startTime,
  ) {
    if (series.isEmpty) return [];
    final intervals = <_IntervalForecast>[];
    DateTime current = startTime;
    for (int i = 0; i < series.length; i++) {
      final timeLabel =
          '${current.hour.toString().padLeft(2, '0')}:'
          '${current.minute.toString().padLeft(2, '0')}';
      intervals.add(_IntervalForecast(
        label:     '+${(i + 1) * 30} mnt',
        timeLabel: timeLabel,
        value:     series[i],
        status:    _statusFromValue(series[i]),
        time:      current,
      ));
      current = current.add(const Duration(minutes: 30));
    }
    return intervals;
  }

  List<String> _buildTimeLabels(
    List<DataQoS> history,
    List<double>  predSeries,
    DateTime      forecastStart,
  ) {
    final labels = <String>[];
    for (final q in history) {
      final t = q.timestamp ?? DateTime.now();
      labels.add(
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}',
      );
    }
    DateTime current = forecastStart;
    for (int i = 0; i < predSeries.length; i++) {
      labels.add(
        '${current.hour.toString().padLeft(2, '0')}:'
        '${current.minute.toString().padLeft(2, '0')}',
      );
      current = current.add(const Duration(minutes: 30));
    }
    return labels;
  }

  // =========================================================
  // FORECAST
  // =========================================================
  Future<void> _runForecast({bool isAuto = false}) async {
    if (_isForecasting) return;

    setState(() {
      _isForecasting = true;
      _errorMessage  = null;
    });

    try {
      final ctrl   = ForecastController();
      final result = await ctrl.runFutureForecast();

      if (result == null) {
        setState(() => _errorMessage = 'Backend tidak merespons');
        return;
      }

      if (result['status'] == 'waiting') {
        setState(() => _errorMessage = result['message']);
        return;
      }

      final predictions   = result['predictions'] as List<double>;
      final forecastStart = DateTime.now().add(const Duration(minutes: 30));
      final histSlice     = _sampleEvery30Min(widget.qosHistory);
      final newIntervals  = _buildIntervals(predictions, forecastStart);
      final newLabels     = _buildTimeLabels(histSlice, predictions, forecastStart);
      final newPrediction = predictions.isNotEmpty ? predictions.last : null;

      await DBHelper.getForecastHistory();

      setState(() {
        _prediction        = newPrediction;
        _predictionSeries  = predictions;
        _intervalForecasts = newIntervals;
        _timeLabels        = newLabels;
        _lastModelName     = 'MSSA-LSTM';
        _lastForecastTime  = DateTime.now();

        // Jadwalkan forecast berikutnya 30 menit dari sekarang
        _nextForecastAt = DateTime.now().add(const Duration(minutes: 30));
      });

      widget.onForecastResult(
        prediction:   newPrediction,
        series:       predictions,
        intervals:    newIntervals.map((f) => <String, dynamic>{
          'label':     f.label,
          'timeLabel': f.timeLabel,
          'time':      f.time,
          'value':     f.value,
          'status':    f.status,
        }).toList(),
        timeLabels:   newLabels,
        modelName:    'MSSA-LSTM',
        forecastTime: forecastStart,
        nextForecastAt: _nextForecastAt,
        error:        null,
      );

    } catch (e) {
      final msg = 'Error: $e';
      setState(() => _errorMessage = msg);
      widget.onForecastResult(
        prediction:   null,
        series:       [],
        intervals:    [],
        timeLabels:   [],
        modelName:    null,
        forecastTime: null,
        nextForecastAt: _nextForecastAt,
        error:        msg,
      );
    } finally {
      if (mounted) setState(() => _isForecasting = false);
    }
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    final status    = _statusFromValue(_prediction);
    final statusClr = _statusColor(status);
    final histSlice = _sampleEvery30Min(widget.qosHistory);
    final actualSeries = histSlice.map(_getQoSIndex).toList();

    return Scaffold(
      backgroundColor: _bgDark,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _DatasetStatusBar(
                  rowCount:      _rowCount,
                  isForecasting: _isForecasting,
                ),
                const SizedBox(height: 14),

                // ── AUTO-REFRESH INDICATOR ──────────────────
                _AutoRefreshBar(
                  isForecasting:       _isForecasting,
                  timeUntilNext:       _timeUntilNextForecast,
                  lastForecastTime:    _lastForecastTime,
                  onManualRefresh:     () => _runForecast(isAuto: false),
                ),
                const SizedBox(height: 10),

                // ── TOMBOL MANUAL (tetap ada) ────────────────
                _RunForecastButton(
                  isForecasting: _isForecasting,
                  onTap:         () => _runForecast(isAuto: false),
                ),

                if (_errorMessage != null)
                  _ErrorBanner(message: _errorMessage!),
                const SizedBox(height: 16),

                if (_prediction != null)
                  _StatusHeroCard(
                    prediction:    _prediction!,
                    status:        status,
                    statusColor:   statusClr,
                    categoryLabel: _categoryLabel(_prediction),
                    modelName:     _lastModelName,
                    forecastTime:  _lastForecastTime,
                    trendLabel:    _trendLabel(actualSeries),
                    trendColor:    _trendColor(actualSeries),
                    statusIcon:    _statusIcon(status),
                  )
                else
                  _PlaceholderHeroCard(),

                const SizedBox(height: 20),
                const _SectionLabel(label: 'PREDIKSI PER INTERVAL'),
                const SizedBox(height: 10),
                _IntervalForecastRow(
                  intervals:   _intervalForecasts,
                  statusColor: _statusColor,
                  statusBg:    _statusBg,
                  statusIcon:  _statusIcon,
                ),

                const SizedBox(height: 24),
                const _SectionLabel(label: 'GRAFIK FORECAST'),
                const SizedBox(height: 10),
                _ForecastChartCard(
                  actualSeries:     actualSeries,
                  predictionSeries: _predictionSeries,
                  timeLabels:       _timeLabels,
                  prediction:       _prediction,
                ),

                const SizedBox(height: 20),
                const _SectionLabel(label: 'STABILITAS JARINGAN'),
                const SizedBox(height: 10),
                _StabilityGaugeCard(
                  actualSeries: actualSeries,
                  prediction:   _prediction,
                  statusColor:  _statusColor,
                ),

                const SizedBox(height: 20),
                const _SectionLabel(label: 'LEVEL PERINGATAN'),
                const SizedBox(height: 10),
                _AlertLevelCard(prediction: _prediction, status: status),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// AUTO-REFRESH BAR  (komponen baru)
// Menampilkan:
//   - "Auto-refresh aktif" + countdown sisa waktu
//   - Tombol refresh manual (ikon)
//   - Badge "Sedang memproses..." saat isForecasting
// =========================================================
class _AutoRefreshBar extends StatelessWidget {
  final bool         isForecasting;
  final Duration     timeUntilNext;
  final DateTime?    lastForecastTime;
  final VoidCallback onManualRefresh;

  const _AutoRefreshBar({
    required this.isForecasting,
    required this.timeUntilNext,
    required this.lastForecastTime,
    required this.onManualRefresh,
  });

  String _formatCountdown(Duration d) {
    if (d == Duration.zero) return 'segera…';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatLastTime(DateTime? t) {
    if (t == null) return 'belum pernah';
    return '${t.hour.toString().padLeft(2, '0')}:'
           '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        _bgCard,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Row(
        children: [
          // Ikon status
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isForecasting
                ? const SizedBox(
                    key:    ValueKey('loading'),
                    width:  16,
                    height: 16,
                    child:  CircularProgressIndicator(
                      strokeWidth: 2,
                      color:       _accent,
                    ),
                  )
                : const Icon(
                    key:   ValueKey('clock'),
                    Icons.autorenew_rounded,
                    size:  16,
                    color: _colorGreen,
                  ),
          ),
          const SizedBox(width: 10),

          // Teks countdown / status
          Expanded(
            child: isForecasting
                ? const Text(
                    'Memperbarui forecast…',
                    style: TextStyle(
                      fontSize:   12,
                      fontWeight: FontWeight.w600,
                      color:      _accent,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Forecast berikutnya: ',
                            style: TextStyle(fontSize: 11, color: _textSecondary),
                          ),
                          Text(
                            _formatCountdown(timeUntilNext),
                            style: const TextStyle(
                              fontSize:   12,
                              fontWeight: FontWeight.w700,
                              color:      _accent,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Terakhir diperbarui: ${_formatLastTime(lastForecastTime)}',
                        style: const TextStyle(fontSize: 10, color: _textSecondary),
                      ),
                    ],
                  ),
          ),

          // Tombol refresh manual
          GestureDetector(
            onTap: isForecasting ? null : onManualRefresh,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color:        isForecasting ? _bgCardAlt : _accentGlow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.refresh_rounded,
                size:  16,
                color: isForecasting ? _textSecondary : _accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// SECTION LABEL
// =========================================================
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width:  3,
          height: 14,
          decoration: BoxDecoration(
            color:        _accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize:      11,
            fontWeight:    FontWeight.w700,
            color:         _textSecondary,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// =========================================================
// DATASET STATUS BAR
// =========================================================
class _DatasetStatusBar extends StatelessWidget {
  final int  rowCount;
  final bool isForecasting;
  const _DatasetStatusBar({
    required this.rowCount,
    required this.isForecasting,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (rowCount / 110).clamp(0.0, 1.0);
    final isReady  = rowCount >= 110;
    final barColor = isReady ? _colorGreen : _colorAmber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        _bgCard,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isReady ? '✓  Dataset siap diproses' : '⚠  Mengumpulkan data…',
                style: TextStyle(
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                  color:      barColor,
                ),
              ),
              Text(
                '$rowCount / 110',
                style: const TextStyle(
                  fontSize:   12,
                  color:      _textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           progress,
              minHeight:       5,
              backgroundColor: _bgCardAlt,
              valueColor:      AlwaysStoppedAnimation(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// RUN FORECAST BUTTON
// =========================================================
class _RunForecastButton extends StatelessWidget {
  final bool         isForecasting;
  final VoidCallback onTap;
  const _RunForecastButton({
    required this.isForecasting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isForecasting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: isForecasting
                ? [_bgCardAlt, _bgCardAlt]
                : [const Color(0xFF005FAB), const Color(0xFF0099DD)],
          ),
          boxShadow: isForecasting
              ? []
              : [
                  BoxShadow(
                    color:        _accent.withOpacity(0.3),
                    blurRadius:   20,
                    spreadRadius: -4,
                    offset:       const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isForecasting)
              const SizedBox(
                width:  18,
                height: 18,
                child:  CircularProgressIndicator(
                  strokeWidth: 2,
                  color:       _textSecondary,
                ),
              )
            else
              const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              isForecasting ? 'MEMPROSES FORECAST…' : 'JALANKAN FORECAST',
              style: TextStyle(
                fontSize:      13,
                fontWeight:    FontWeight.w800,
                letterSpacing: 1.5,
                color: isForecasting ? _textSecondary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
// ERROR BANNER
// =========================================================
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        _colorRedBg,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _colorRed.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _colorRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: _colorRed),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// PLACEHOLDER HERO
// =========================================================
class _PlaceholderHeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color:        _bgCard,
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        children: [
          Icon(Icons.radar_rounded, size: 56, color: _textSecondary.withOpacity(0.3)),
          const SizedBox(height: 12),
          const Text(
            'Belum ada prediksi',
            style: TextStyle(
              fontSize:   16,
              fontWeight: FontWeight.w600,
              color:      _textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tekan tombol di atas atau tunggu auto-refresh',
            style: TextStyle(fontSize: 12, color: _textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// =========================================================
// STATUS HERO CARD
// =========================================================
class _StatusHeroCard extends StatelessWidget {
  final double    prediction;
  final QoSStatus status;
  final Color     statusColor;
  final String    categoryLabel;
  final String?   modelName;
  final DateTime? forecastTime;
  final String    trendLabel;
  final Color     trendColor;
  final IconData  statusIcon;

  const _StatusHeroCard({
    required this.prediction,
    required this.status,
    required this.statusColor,
    required this.categoryLabel,
    required this.modelName,
    required this.forecastTime,
    required this.trendLabel,
    required this.trendColor,
    required this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
          colors: [_bgCard, statusColor.withOpacity(0.08)],
        ),
        border: Border.all(color: statusColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color:        statusColor.withOpacity(0.15),
            blurRadius:   24,
            spreadRadius: -6,
            offset:       const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INDEKS QoS',
                        style: TextStyle(
                          fontSize:      10,
                          fontWeight:    FontWeight.w700,
                          letterSpacing: 2,
                          color:         _textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            prediction.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize:   56,
                              fontWeight: FontWeight.w900,
                              color:      statusColor,
                              height:     0.9,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, left: 4),
                            child: Text(
                              '/ 100',
                              style: TextStyle(
                                fontSize:   16,
                                color:      _textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:        statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          categoryLabel,
                          style: TextStyle(
                            fontSize:      11,
                            fontWeight:    FontWeight.w700,
                            letterSpacing: 1,
                            color:         statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:  statusColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 30),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      trendLabel,
                      style: TextStyle(
                        fontSize:   12,
                        fontWeight: FontWeight.w700,
                        color:      trendColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Divider(color: _divider, height: 1),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                _MetaChip(
                  icon:  Icons.access_time_rounded,
                  label: forecastTime != null
                      ? '${forecastTime!.hour.toString().padLeft(2, '0')}:'
                        '${forecastTime!.minute.toString().padLeft(2, '0')}'
                      : '--:--',
                  hint: 'Waktu forecast',
                ),
                const SizedBox(width: 12),
                _MetaChip(
                  icon:  Icons.memory_rounded,
                  label: modelName ?? 'MSSA-LSTM',
                  hint:  'Model',
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:        _colorGreenBg,
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(color: _colorGreen.withOpacity(0.3)),
                  ),
                  child: const Text(
                    '30 mnt horizon',
                    style: TextStyle(
                      fontSize:   10,
                      fontWeight: FontWeight.w700,
                      color:      _colorGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   hint;
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _textSecondary),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize:   11,
            color:      _textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// =========================================================
// INTERVAL FORECAST ROW  (diperbarui: expired state)
// =========================================================
class _IntervalForecastRow extends StatelessWidget {
  final List<_IntervalForecast>       intervals;
  final Color Function(QoSStatus)     statusColor;
  final Color Function(QoSStatus)     statusBg;
  final IconData Function(QoSStatus)  statusIcon;

  const _IntervalForecastRow({
    required this.intervals,
    required this.statusColor,
    required this.statusBg,
    required this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (intervals.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color:        _bgCard,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: _divider),
        ),
        child: const Center(
          child: Text(
            'Jalankan forecast untuk melihat prediksi per interval',
            style:     TextStyle(fontSize: 12, color: _textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: intervals.map((f) {
          final expired = f.isExpired;
          // Kalau expired: tampilkan abu-abu + badge "Lewat"
          final clr = expired ? _textSecondary : statusColor(f.status);
          final bg  = expired ? _bgCardAlt     : statusBg(f.status);
          final icn = expired
              ? Icons.history_rounded
              : statusIcon(f.status);

          return Container(
            width:   80,
            margin:  const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color:        _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: expired
                    ? _divider
                    : clr.withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(icn, size: 20, color: clr),
                const SizedBox(height: 6),
                Text(
                  f.value.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize:             20,
                    fontWeight:           FontWeight.w800,
                    color:                clr,
                    decoration:           expired
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor:      _textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                // Badge "Lewat" jika expired
                if (expired)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color:        _bgCardAlt,
                      borderRadius: BorderRadius.circular(4),
                      border:       Border.all(color: _divider),
                    ),
                    child: const Text(
                      'Lewat',
                      style: TextStyle(
                        fontSize:   8,
                        color:      _textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Text(
                    f.timeLabel,
                    style: const TextStyle(
                      fontSize:   10,
                      color:      _textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  f.label,
                  style: const TextStyle(
                    fontSize:   10,
                    color:      _textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =========================================================
// FORECAST CHART CARD
// =========================================================
class _ForecastChartCard extends StatelessWidget {
  final List<double> actualSeries;
  final List<double> predictionSeries;
  final List<String> timeLabels;
  final double?      prediction;

  const _ForecastChartCard({
    required this.actualSeries,
    required this.predictionSeries,
    required this.timeLabels,
    required this.prediction,
  });

  @override
  Widget build(BuildContext context) {
    final totalPoints = actualSeries.length + predictionSeries.length;
    final chartWidth  = math.max(
      MediaQuery.of(context).size.width - 80.0,
      totalPoints * 48.0,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color:        _bgCard,
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: ['100', '75', '50', '25', '0'].map((v) => SizedBox(
                    height: 44,
                    child: Text(
                      v,
                      style: const TextStyle(
                          fontSize: 9, color: _textSecondary),
                    ),
                  )).toList(),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width:  chartWidth,
                      height: 220,
                      child: CustomPaint(
                        painter: _ForecastChartPainter(
                          actualValues:    actualSeries,
                          predictedValues: predictionSeries,
                          splitIndex:      actualSeries.length,
                          timeLabels:      timeLabels,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Divider(color: _divider, height: 1),
          const SizedBox(height: 10),

          Row(
            children: [
              _LegendDot(color: const Color(0xFF1D9E75), label: 'Aktual'),
              const SizedBox(width: 16),
              _LegendDash(color: const Color(0xFF7F77DD), label: 'Forecast'),
              const Spacer(),
              const Icon(Icons.swipe_rounded, size: 13, color: _textSecondary),
              const SizedBox(width: 4),
              const Text(
                'geser grafik',
                style: TextStyle(fontSize: 10, color: _textSecondary),
              ),
            ],
          ),

          if (prediction != null) ...[
            const SizedBox(height: 6),
            Text(
              'Target: ${prediction!.toStringAsFixed(1)}',
              style: const TextStyle(
                fontSize:   11,
                color:      _colorGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width:  12,
          height: 3,
          decoration: BoxDecoration(
            color:        color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, color: _textSecondary)),
      ],
    );
  }
}

class _LegendDash extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDash({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Row(
          children: List.generate(
            3,
            (i) => Container(
              width:  4,
              height: 3,
              margin: const EdgeInsets.only(right: 2),
              color:  color,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, color: _textSecondary)),
      ],
    );
  }
}

// =========================================================
// STABILITY GAUGE CARD
// =========================================================
class _StabilityGaugeCard extends StatefulWidget {
  final List<double>              actualSeries;
  final double?                   prediction;
  final Color Function(QoSStatus) statusColor;

  const _StabilityGaugeCard({
    required this.actualSeries,
    required this.prediction,
    required this.statusColor,
  });

  @override
  State<_StabilityGaugeCard> createState() => _StabilityGaugeCardState();
}

class _StabilityGaugeCardState extends State<_StabilityGaugeCard> {
  double? _avgMAE;
  int     _evalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadMAE();
  }

  Future<void> _loadMAE() async {
    final mae   = await DBHelper.getAverageMAE();
    final evals = await DBHelper.getEvaluatedForecasts(limit: 1000);
    if (!mounted) return;
    setState(() {
      _avgMAE    = mae;
      _evalCount = evals.length;
    });
  }

  String _accuracyLabel(double mae) {
    if (mae < 5)  return 'SANGAT AKURAT';
    if (mae < 10) return 'AKURAT';
    if (mae < 20) return 'CUKUP AKURAT';
    return 'PERLU PERBAIKAN';
  }

  Color _accuracyColor(double mae) {
    if (mae < 5)  return _colorGreen;
    if (mae < 10) return _accent;
    if (mae < 20) return _colorAmber;
    return _colorRed;
  }

  @override
  Widget build(BuildContext context) {
    final avgCurrent = widget.actualSeries.isEmpty
        ? 0.0
        : widget.actualSeries.reduce((a, b) => a + b) /
          widget.actualSeries.length;
    final delta =
        widget.prediction != null ? widget.prediction! - avgCurrent : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        _bgCard,
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatRow(
            label: 'Rata-rata Aktual',
            value: avgCurrent.toStringAsFixed(1),
            color: _accent,
          ),
          const SizedBox(height: 10),
          _StatRow(
            label: 'Prediksi +30 mnt',
            value: widget.prediction != null
                ? widget.prediction!.toStringAsFixed(1)
                : '—',
            color: _colorGreen,
          ),
          const SizedBox(height: 10),
          _StatRow(
            label: 'Perubahan',
            value: delta != null
                ? '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)}'
                : '—',
            color: delta == null
                ? _textSecondary
                : delta >= 0 ? _colorGreen : _colorRed,
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child:   Divider(color: _divider, height: 1),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AKURASI MODEL',
                style: TextStyle(
                  fontSize:      10,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: 1.5,
                  color:         _textSecondary,
                ),
              ),
              Text(
                '$_evalCount evaluasi',
                style: const TextStyle(
                  fontSize: 10,
                  color:    _textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_avgMAE == null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        _bgCardAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_empty_rounded,
                      size: 16, color: _textSecondary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Menunggu forecast_time tiba untuk evaluasi pertama',
                      style: TextStyle(fontSize: 11, color: _textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _StatRow(
              label: 'MAE rata-rata',
              value: _avgMAE!.toStringAsFixed(2),
              color: _accuracyColor(_avgMAE!),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:        _accuracyColor(_avgMAE!).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _accuracyColor(_avgMAE!).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _avgMAE! < 10
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    size:  16,
                    color: _accuracyColor(_avgMAE!),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _accuracyLabel(_avgMAE!),
                          style: TextStyle(
                            fontSize:      11,
                            fontWeight:    FontWeight.w800,
                            letterSpacing: 1,
                            color:         _accuracyColor(_avgMAE!),
                          ),
                        ),
                        Text(
                          'Selisih rata-rata prediksi vs aktual: '
                          '${_avgMAE!.toStringAsFixed(2)} poin',
                          style: TextStyle(
                            fontSize: 10,
                            color:    _accuracyColor(_avgMAE!).withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          GestureDetector(
            onTap: _loadMAE,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.refresh_rounded, size: 12, color: _textSecondary),
                SizedBox(width: 4),
                Text(
                  'Refresh evaluasi',
                  style: TextStyle(fontSize: 10, color: _textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: _textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontSize:   13,
            fontWeight: FontWeight.w700,
            color:      color,
          ),
        ),
      ],
    );
  }
}

// =========================================================
// ALERT LEVEL CARD
// =========================================================
class _AlertLevelCard extends StatelessWidget {
  final double?   prediction;
  final QoSStatus status;
  const _AlertLevelCard({
    required this.prediction,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final levels = [
      _AlertLevel(
        label:  'KRITIS',
        range:  '0–39',
        color:  _colorRed,
        bg:     _colorRedBg,
        icon:   Icons.warning_amber_rounded,
        active: status == QoSStatus.poor,
        desc:   'Layanan terganggu parah',
      ),
      _AlertLevel(
        label:  'WASPADA',
        range:  '40–59',
        color:  _colorAmber,
        bg:     _colorAmberBg,
        icon:   Icons.info_outline_rounded,
        active: status == QoSStatus.fair,
        desc:   'Kualitas di bawah standar',
      ),
      _AlertLevel(
        label:  'NORMAL',
        range:  '60–79',
        color:  _accent,
        bg:     _accentGlow,
        icon:   Icons.check_circle_outline_rounded,
        active: status == QoSStatus.good,
        desc:   'Layanan beroperasi normal',
      ),
      _AlertLevel(
        label:  'PRIMA',
        range:  '80–100',
        color:  _colorGreen,
        bg:     _colorGreenBg,
        icon:   Icons.verified_rounded,
        active: status == QoSStatus.excellent,
        desc:   'Kualitas optimal',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        _bgCard,
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        children: levels.map((lvl) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:        lvl.active ? lvl.bg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: lvl.active ? lvl.color.withOpacity(0.5) : _divider,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  lvl.icon,
                  size:  18,
                  color: lvl.active ? lvl.color : _textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lvl.label,
                        style: TextStyle(
                          fontSize:      11,
                          fontWeight:    FontWeight.w800,
                          letterSpacing: 1,
                          color:         lvl.active
                              ? lvl.color
                              : _textSecondary,
                        ),
                      ),
                      Text(
                        lvl.desc,
                        style: TextStyle(
                          fontSize: 10,
                          color:    lvl.active
                              ? lvl.color.withOpacity(0.7)
                              : _textSecondary.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  lvl.range,
                  style: TextStyle(
                    fontSize:   11,
                    fontWeight: FontWeight.w700,
                    color:      lvl.active ? lvl.color : _textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
                if (lvl.active) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:        lvl.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'AKTIF',
                      style: TextStyle(
                        fontSize:      8,
                        fontWeight:    FontWeight.w800,
                        letterSpacing: 1,
                        color:         lvl.color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        )).toList(),
      ),
    );
  }
}

class _AlertLevel {
  final String   label;
  final String   range;
  final Color    color;
  final Color    bg;
  final IconData icon;
  final bool     active;
  final String   desc;

  const _AlertLevel({
    required this.label,
    required this.range,
    required this.color,
    required this.bg,
    required this.icon,
    required this.active,
    required this.desc,
  });
}