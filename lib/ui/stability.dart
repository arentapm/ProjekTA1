import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math' as math;

import '../models/data_qos.dart';
import '../qos/MonitoringController.dart';
import '../database/db_helper.dart';
import '../qos/forecest_controller.dart';

// =========================================================
// COLORS
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

  bool get isExpired => DateTime.now().isAfter(time);
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
  final DateTime?                  savedNextForecastAt;

  final void Function({
    required double?                    prediction,
    required List<double>               series,
    required List<Map<String, dynamic>> intervals,
    required List<String>               timeLabels,
    required String?                    modelName,
    required DateTime?                  forecastTime,
    required DateTime?                  nextForecastAt,
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

  double?                 _prediction;
  List<double>            _predictionSeries       = [];
  List<double>            _predictionSeriesDetail = []; // 300 titik untuk grafik 5m
  List<String>            _detailLabels           = []; // ['t+1s'..'t+300s']
  bool                    _isForecasting          = false;
  double?                 _forecastProgress;
  String?                 _errorMessage;
  String?                 _lastModelName;
  DateTime?               _lastForecastTime;
  int                     _rowCount               = 0;
  int                     _activeIntervalMin      = 30;

  List<_IntervalForecast> _intervalForecasts = [];
  List<String>            _timeLabels        = [];

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  Timer?    _autoRefreshTimer;
  Timer?    _rowCountTimer;
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

    // FIX: _predictionSeriesDetail & _detailLabels tidak disimpan di saved state,
    // jadi inisialisasi ke kosong saja — akan terisi saat forecast dijalankan.
    _predictionSeriesDetail = [];
    _detailLabels           = [];

    _nextForecastAt = widget.savedNextForecastAt;

    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkAndAutoRefresh(),
    );

    if (widget.savedPrediction == null) {
      _rowCountTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkRowCount(),
      );
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _autoRefreshTimer?.cancel();
    _rowCountTimer?.cancel();
    super.dispose();
  }

  // =========================================================
  // AUTO-REFRESH
  // =========================================================
  Future<void> _checkAndAutoRefresh() async {
    if (_nextForecastAt == null || _isForecasting) return;
    final now = DateTime.now();
    if (now.isAfter(_nextForecastAt!) || now.isAtSameMomentAs(_nextForecastAt!)) {
      await _runForecast(isAuto: true, intervalMinutes: _activeIntervalMin);
    }
  }

  // =========================================================
  // HELPERS
  // =========================================================
  Future<void> _checkRowCount() async {
    final rows = await DBHelper.getHistory(days: 30);
    if (!mounted) return;
    setState(() => _rowCount = rows.length);
  }

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
    final delta = series.last - series[series.length - 3];
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

  _IntervalForecast? get _nextActiveInterval {
    for (final f in _intervalForecasts) {
      if (!f.isExpired) return f;
    }
    return null;
  }

  List<_IntervalForecast> _buildIntervals(
    List<double>   series,
    List<DateTime> times,
    int            intervalMinutes,
  ) {
    return List.generate(series.length, (i) {
      final t = times[i];
      return _IntervalForecast(
        label:     '+${(i + 1) * intervalMinutes} mnt',
        timeLabel: '${t.hour.toString().padLeft(2, '0')}:'
                   '${t.minute.toString().padLeft(2, '0')}',
        time:      t,
        value:     series[i],
        status:    _statusFromValue(series[i]),
      );
    });
  }

  List<String> _buildTimeLabels(List<DateTime> forecastTimes) {
    return forecastTimes.map((t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}'
    ).toList();
  }

  // =========================================================
  // FORECAST
  // =========================================================
  Future<void> _runForecast({
    bool isAuto          = false,
    int  intervalMinutes = 30,
  }) async {
    if (_isForecasting) return;

    if (!isAuto && _rowCountTimer == null) {
      _rowCountTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkRowCount(),
      );
    }

    setState(() {
      _isForecasting     = true;
      _errorMessage      = null;
      _forecastProgress  = 0;
      _activeIntervalMin = intervalMinutes;
    });

    try {
      final ctrl   = ForecastController();
      final result = await ctrl.runFutureForecast(
        intervalMinutes: intervalMinutes,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _forecastProgress = p);
        },
      );

      if (result == null) {
        setState(() => _errorMessage = 'Backend tidak merespons');
        return;
      }

      final status = result['status'] as String?;

      if (status == 'waiting' || status == 'loading' || status == 'error') {
        setState(() => _errorMessage = result['message'] as String?);
        return;
      }

      final predictions       = result['predictions']       as List<double>;
      final predictionsDetail = result['predictionsDetail'] as List<double>? ?? [];
      final detailLabels      = result['detailLabels']      as List<String>? ?? [];
      final forecastTimes     = result['forecastTimes']     as List<DateTime>;
      final forecastStart     = forecastTimes.isNotEmpty
          ? forecastTimes.first
          : DateTime.now().add(Duration(minutes: intervalMinutes));

      final newLabels    = _buildTimeLabels(forecastTimes);
      final newIntervals = _buildIntervals(predictions, forecastTimes, intervalMinutes);

      _rowCountTimer?.cancel();
      _rowCountTimer = null;

      setState(() {
        _prediction             = predictions.isNotEmpty ? predictions.first : null;
        _predictionSeries       = predictions;
        _predictionSeriesDetail = predictionsDetail; // FIX: simpan ke state
        _detailLabels           = detailLabels;      // FIX: simpan ke state
        _intervalForecasts      = newIntervals;
        _timeLabels             = newLabels;
        _lastModelName          = 'MSSA-LSTM';
        _lastForecastTime       = DateTime.now();
        _nextForecastAt         = DateTime.now().add(Duration(minutes: intervalMinutes));
      });

      widget.onForecastResult(
        prediction:     _prediction,
        series:         predictions,
        intervals:      newIntervals.map((f) => <String, dynamic>{
          'label':     f.label,
          'timeLabel': f.timeLabel,
          'time':      f.time,
          'value':     f.value,
          'status':    f.status,
        }).toList(),
        timeLabels:     newLabels,
        modelName:      'MSSA-LSTM',
        forecastTime:   forecastStart,
        nextForecastAt: _nextForecastAt,
        error:          null,
      );

    } catch (e) {
      final msg = 'Error: $e';
      setState(() => _errorMessage = msg);
      widget.onForecastResult(
        prediction:     null,
        series:         [],
        intervals:      [],
        timeLabels:     [],
        modelName:      null,
        forecastTime:   null,
        nextForecastAt: _nextForecastAt,
        error:          msg,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isForecasting    = false;
          _forecastProgress = null;
        });
      }
    }
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    final active = _nextActiveInterval;

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

                _RunForecastButton(
                  isForecasting: _isForecasting,
                  onTap: (interval) => _runForecast(
                    isAuto:          false,
                    intervalMinutes: interval,
                  ),
                ),

                if (_isForecasting)
                  _ForecastProgressBar(
                    progress:        _forecastProgress,
                    intervalMinutes: _activeIntervalMin, // FIX: pass interval
                  ),

                if (_errorMessage != null)
                  _ErrorBanner(message: _errorMessage!),
                const SizedBox(height: 16),

                if (active != null)
                  _StatusHeroCard(
                    prediction:      active.value,
                    status:          active.status,
                    statusColor:     _statusColor(active.status),
                    categoryLabel:   _categoryLabel(active.value),
                    modelName:       _lastModelName,
                    forecastTime:    active.time,
                    trendLabel:      _trendLabel(_predictionSeries),
                    trendColor:      _trendColor(_predictionSeries),
                    statusIcon:      _statusIcon(active.status),
                    intervalMinutes: _activeIntervalMin,
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
                const _SectionLabel(label: 'GRAFIK PREDIKSI'),
                const SizedBox(height: 10),
                _ForecastChartCard(
                  predictionSeries:       _predictionSeries,
                  predictionSeriesDetail: _predictionSeriesDetail, // FIX
                  detailLabels:           _detailLabels,           // FIX
                  timeLabels:             _timeLabels,
                  intervalMinutes:        _activeIntervalMin,
                ), // FIX: koma ada

                const SizedBox(height: 20),
                const _SectionLabel(label: 'STABILITAS JARINGAN'),
                const SizedBox(height: 10),
                _StabilityGaugeCard(
                  prediction:       active?.value ?? _prediction,
                  predictionLabel:  active?.label,
                  predictionSeries: _predictionSeries,
                ),

                const SizedBox(height: 20),
                const _SectionLabel(label: 'LEVEL PERINGATAN'),
                const SizedBox(height: 10),
                _AlertLevelCard(
                  prediction: active?.value,
                  status:     active?.status ?? QoSStatus.unknown,
                ),

              ]),
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
          width: 3, height: 14,
          decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: _textSecondary, letterSpacing: 2,
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
  const _DatasetStatusBar({required this.rowCount, required this.isForecasting});

  @override
  Widget build(BuildContext context) {
    final progress = (rowCount / 110).clamp(0.0, 1.0);
    final isReady  = rowCount >= 110;
    final barColor = isReady ? _colorGreen : _colorAmber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isReady ? '✓  Dataset siap diproses' : '⚠  Mengumpulkan data…',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: barColor),
              ),
              Text(
                '$rowCount / 110',
                style: const TextStyle(fontSize: 12, color: _textSecondary, fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress, minHeight: 5,
              backgroundColor: _bgCardAlt,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// FORECAST PROGRESS BAR
// FIX: tambah parameter intervalMinutes untuk teks dinamis
// =========================================================
class _ForecastProgressBar extends StatelessWidget {
  final double? progress;
  final int     intervalMinutes;
  const _ForecastProgressBar({
    required this.progress,
    required this.intervalMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final pct  = (progress ?? 0).clamp(0.0, 100.0);
    final text = intervalMinutes == 5
        ? 'Memproses prediksi 5 menit ke depan…'
        : 'Memproses prediksi 2 jam ke depan…';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accent),
                ),
              ),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 12, color: _accent, fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 6,
              backgroundColor: _bgCardAlt,
              valueColor: const AlwaysStoppedAnimation(_accent),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Proses berjalan di server, kamu boleh tetap di halaman ini',
            style: TextStyle(fontSize: 10, color: _textSecondary),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// RUN FORECAST BUTTON
// FIX: label & sublabel bottom sheet diperbarui
// =========================================================
class _RunForecastButton extends StatelessWidget {
  final bool isForecasting;
  final void Function(int intervalMinutes) onTap;

  const _RunForecastButton({
    required this.isForecasting,
    required this.onTap,
  });

  void _showIntervalPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih interval prediksi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pilih horizon waktu prediksi QoS jaringan',
                style: TextStyle(fontSize: 12, color: _textSecondary),
              ),
              const SizedBox(height: 16),
              _IntervalOption(
                label:    '5 menit ke depan',
                sublabel: '1 prediksi · grafik pola 300 detik',
                icon:     Icons.access_time_filled_rounded,
                color:    _accent,
                onTap: () { Navigator.pop(context); onTap(5); },
              ),
              const SizedBox(height: 10),
              _IntervalOption(
                label:    'Setiap 30 menit (2 jam)',
                sublabel: '4 titik · gambaran umum',
                icon:     Icons.av_timer_rounded,
                color:    _colorGreen,
                onTap: () { Navigator.pop(context); onTap(30); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isForecasting ? null : () => _showIntervalPicker(context),
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
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isForecasting)
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _textSecondary),
              )
            else
              const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              isForecasting ? 'MEMPROSES PREDIKSI…' : 'JALANKAN PREDIKSI',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5,
                color: isForecasting ? _textSecondary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervalOption extends StatelessWidget {
  final String     label;
  final String     sublabel;
  final IconData   icon;
  final Color      color;
  final VoidCallback onTap;

  const _IntervalOption({
    required this.label, required this.sublabel,
    required this.icon,  required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _textPrimary,
                  )),
                  Text(sublabel, style: const TextStyle(fontSize: 11, color: _textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 20),
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
        color: _colorRedBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _colorRed.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _colorRed, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12, color: _colorRed))),
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
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: [
          Icon(Icons.radar_rounded, size: 56, color: _textSecondary.withOpacity(0.3)),
          const SizedBox(height: 12),
          const Text(
            'Belum ada prediksi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textSecondary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tekan tombol di atas untuk memilih interval dan menjalankan prediksi',
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
  final int       intervalMinutes;

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
    required this.intervalMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [_bgCard, statusColor.withOpacity(0.08)],
        ),
        border: Border.all(color: statusColor.withOpacity(0.3)),
        boxShadow: [BoxShadow(
          color: statusColor.withOpacity(0.15),
          blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 8),
        )],
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
                      const Text(
                        'INDEKS QoS',
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          letterSpacing: 2, color: _textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            prediction.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 56, fontWeight: FontWeight.w900,
                              color: statusColor, height: 0.9,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, left: 4),
                            child: Text(
                              '/ 100',
                              style: TextStyle(
                                fontSize: 16, color: _textSecondary, fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          categoryLabel,
                          style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            letterSpacing: 1, color: statusColor,
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
                        color: statusColor.withOpacity(0.12), shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 30),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      trendLabel,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: trendColor),
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
                ),
                const SizedBox(width: 12),
                _MetaChip(icon: Icons.memory_rounded, label: modelName ?? 'MSSA-LSTM'),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _colorGreenBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _colorGreen.withOpacity(0.3)),
                  ),
                  child: Text(
                    intervalMinutes == 5 ? 't+5 menit' : '$intervalMinutes mnt interval',
                    style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: _colorGreen,
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
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _textSecondary),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(
          fontSize: 11, color: _textPrimary, fontWeight: FontWeight.w600,
        )),
      ],
    );
  }
}

// =========================================================
// INTERVAL FORECAST ROW
// =========================================================
class _IntervalForecastRow extends StatelessWidget {
  final List<_IntervalForecast>      intervals;
  final Color Function(QoSStatus)    statusColor;
  final Color Function(QoSStatus)    statusBg;
  final IconData Function(QoSStatus) statusIcon;

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
          color: _bgCard, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _divider),
        ),
        child: const Center(
          child: Text(
            'Jalankan forecast untuk melihat prediksi per interval',
            style: TextStyle(fontSize: 12, color: _textSecondary),
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
          final clr = expired ? _textSecondary : statusColor(f.status);
          final icn = expired ? Icons.history_rounded : statusIcon(f.status);

          return Container(
            width: 80,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: expired ? _divider : clr.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Icon(icn, size: 20, color: clr),
                const SizedBox(height: 6),
                Text(
                  f.value.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: clr,
                    decoration: expired ? TextDecoration.lineThrough : TextDecoration.none,
                    decorationColor: _textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                if (expired)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _bgCardAlt,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _divider),
                    ),
                    child: const Text(
                      'Lewat',
                      style: TextStyle(fontSize: 8, color: _textSecondary, fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  Text(f.timeLabel, style: const TextStyle(
                    fontSize: 10, color: _textSecondary, fontWeight: FontWeight.w600,
                  )),
                const SizedBox(height: 2),
                Text(f.label, style: const TextStyle(
                  fontSize: 10, color: _textSecondary, fontWeight: FontWeight.w600,
                ), textAlign: TextAlign.center),
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
// FIX: pakai displaySeries/displayLabels sesuai interval,
//      bukan selalu predictionSeries/timeLabels
// =========================================================
class _ForecastChartCard extends StatelessWidget {
  final List<double> predictionSeries;
  final List<double> predictionSeriesDetail;
  final List<String> detailLabels;
  final List<String> timeLabels;
  final int          intervalMinutes;

  const _ForecastChartCard({
    required this.predictionSeries,
    required this.predictionSeriesDetail,
    required this.detailLabels,
    required this.timeLabels,
    required this.intervalMinutes,
  });

  @override
  Widget build(BuildContext context) {
    // Pilih data sesuai interval
    final displaySeries = intervalMinutes == 5 ? predictionSeriesDetail : predictionSeries;
    final displayLabels = intervalMinutes == 5 ? detailLabels : timeLabels;

    if (displaySeries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _bgCard, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _divider),
        ),
        child: const Center(
          child: Text('Belum ada data prediksi',
              style: TextStyle(fontSize: 12, color: _textSecondary)),
        ),
      );
    }

    final chipLabel = intervalMinutes == 5
        ? '5 menit ke depan · pola per detik (300 titik)'
        : 'Interval 30 menit · 2 jam ke depan (24 titik)';

    final chartWidth = math.max(
      MediaQuery.of(context).size.width - 80.0,
      displaySeries.length * (intervalMinutes == 5 ? 8.0 : 32.0),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: _bgCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _accentGlow, borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              chipLabel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _accent),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 220,
                  child: Stack(
                    children: [
                      for (final entry in const [
                        [100.0, 12.0],
                        [ 75.0, 54.0],
                        [ 50.0, 96.0],
                        [ 25.0, 138.0],
                        [  0.0, 175.0],
                      ])
                        Positioned(
                          top: entry[1],
                          child: Text(
                            entry[0].toInt().toString(),
                            style: const TextStyle(fontSize: 9, color: _textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: chartWidth, height: 220,
                      child: CustomPaint(
                        painter: _ForecastOnlyPainter(
                          values:     displaySeries, // FIX: pakai displaySeries
                          timeLabels: displayLabels, // FIX: pakai displayLabels
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
              _LegendDash(color: const Color(0xFF7F77DD), label: 'Prediksi QoS'),
              const Spacer(),
              const Icon(Icons.swipe_rounded, size: 13, color: _textSecondary),
              const SizedBox(width: 4),
              const Text('geser grafik', style: TextStyle(fontSize: 10, color: _textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// =========================================================
// FORECAST ONLY PAINTER
// =========================================================
class _ForecastOnlyPainter extends CustomPainter {
  final List<double> values;
  final List<String> timeLabels;

  const _ForecastOnlyPainter({required this.values, required this.timeLabels});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const minVal = 0.0;
    const maxVal = 100.0;
    const range  = maxVal - minVal;

    final stepX  = size.width / math.max(1, values.length - 1);
    final chartH = size.height - 28.0;

    double toY(double v) =>
        chartH - ((v - minVal) / range) * chartH * 0.88 - chartH * 0.06;
    double toX(int i) => i * stepX;

    // Zone bands
    for (final b in [
      [80.0, 100.0, const Color(0x0F1D9E75)],
      [60.0,  80.0, const Color(0x0C378ADD)],
      [40.0,  60.0, const Color(0x0CBA7517)],
      [ 0.0,  40.0, const Color(0x0FE24B4A)],
    ]) {
      canvas.drawRect(
        Rect.fromLTRB(0, toY(b[1] as double), size.width, toY(b[0] as double)),
        Paint()..color = b[2] as Color,
      );
    }

    // Grid
    for (final v in [25.0, 50.0, 75.0, 100.0]) {
      final y = toY(v);
      if (y >= 0 && y <= chartH) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y),
            Paint()..color = const Color(0x12000000)..strokeWidth = 0.5);
      }
    }

    if (values.length < 2) return;

    // Area
    final areaPath = Path()..moveTo(toX(0), chartH)..lineTo(toX(0), toY(values[0]));
    for (int i = 1; i < values.length; i++) {
      areaPath.cubicTo(
        toX(i-1)+stepX*0.5, toY(values[i-1]),
        toX(i)-stepX*0.5,   toY(values[i]),
        toX(i),              toY(values[i]),
      );
    }
    areaPath.lineTo(toX(values.length-1), chartH);
    areaPath.close();
    canvas.drawPath(areaPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF7F77DD).withOpacity(0.22),
          const Color(0xFF7F77DD).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, chartH)),
    );

    // Garis dashed
    final linePath = Path()..moveTo(toX(0), toY(values[0]));
    for (int i = 1; i < values.length; i++) {
      linePath.cubicTo(
        toX(i-1)+stepX*0.5, toY(values[i-1]),
        toX(i)-stepX*0.5,   toY(values[i]),
        toX(i),              toY(values[i]),
      );
    }
    final dashPaint = Paint()
      ..color = const Color(0xFF7F77DD)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final metric in linePath.computeMetrics()) {
      double dist = 0; bool drawing = true;
      while (dist < metric.length) {
        final end = math.min(dist + (drawing ? 8.0 : 5.0), metric.length);
        if (drawing) canvas.drawPath(metric.extractPath(dist, end), dashPaint);
        dist = end; drawing = !drawing;
      }
    }

    // Titik awal & akhir
    canvas.drawCircle(Offset(toX(0), toY(values.first)), 4.5,
        Paint()..color = const Color(0xFF7F77DD));
    final ex = toX(values.length-1), ey = toY(values.last);
    canvas.drawCircle(Offset(ex, ey), 8,
        Paint()..color = const Color(0xFF7F77DD).withOpacity(0.18));
    canvas.drawCircle(Offset(ex, ey), 4.5,
        Paint()..color = const Color(0xFF7F77DD));

    // Label X — max 12 label agar tidak rapat
    final tp   = TextPainter(textDirection: TextDirection.ltr);
    final step = math.max(1, (values.length / 12).ceil());
    for (int i = 0; i < values.length; i++) {
      if (i % step != 0 && i != values.length - 1) continue;
      if (i >= timeLabels.length) break;
      tp.text = TextSpan(
        text: timeLabels[i],
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontWeight: FontWeight.w500),
      );
      tp.layout();
      tp.paint(canvas, Offset(toX(i) - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(_ForecastOnlyPainter old) => !listEquals(old.values, values);
}

// =========================================================
// LEGEND
// =========================================================
class _LegendDash extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDash({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Row(children: List.generate(3, (i) => Container(
          width: 4, height: 3, margin: const EdgeInsets.only(right: 2), color: color,
        ))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: _textSecondary)),
      ],
    );
  }
}

// =========================================================
// STABILITY GAUGE CARD
// =========================================================
class _StabilityGaugeCard extends StatefulWidget {
  final double?        prediction;
  final String?        predictionLabel;
  final List<double>   predictionSeries;

  const _StabilityGaugeCard({
    required this.prediction,
    required this.predictionSeries,
    this.predictionLabel,
  });

  @override
  State<_StabilityGaugeCard> createState() => _StabilityGaugeCardState();
}

class _StabilityGaugeCardState extends State<_StabilityGaugeCard> {
  Map<String, dynamic>? _batchEval;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadEvaluation();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) { if (mounted) _loadEvaluation(); },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadEvaluation() async {
    final eval = await DBHelper.getLatestBatchEvaluation();
    if (!mounted) return;
    setState(() => _batchEval = eval);
  }

  Duration? _timeUntilFirstHorizon() {
    final ft = _batchEval?['forecastTime'] as String?;
    if (ft == null) return null;
    final diff = DateTime.parse(ft).difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return 'sebentar lagi';
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}d';
  }

  @override
  Widget build(BuildContext context) {
    final avgPred = widget.predictionSeries.isEmpty
        ? 0.0
        : widget.predictionSeries.reduce((a, b) => a + b) /
          widget.predictionSeries.length;

    final delta = widget.prediction != null
        ? widget.prediction! - avgPred
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatRow(
            label: 'Rata-rata prediksi',
            value: avgPred.toStringAsFixed(1),
            color: _accent,
          ),
          const SizedBox(height: 10),
          _StatRow(
            label: 'Prediksi ${widget.predictionLabel ?? "berikutnya"}',
            value: widget.prediction?.toStringAsFixed(1) ?? '—',
            color: _colorGreen,
          ),
          const SizedBox(height: 10),
          _StatRow(
            label: 'Selisih dari rata-rata',
            value: delta != null
                ? '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)}'
                : '—',
            color: delta == null
                ? _textSecondary
                : delta >= 0 ? _colorGreen : _colorRed,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: _divider, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'EVALUASI MODEL',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 1.5, color: _textSecondary,
                ),
              ),
              if (_batchEval != null && _batchEval!['status'] != 'pending')
                Text(
                  '${_batchEval!['evaluatedPoints']}/${_batchEval!['totalPoints']} titik',
                  style: const TextStyle(fontSize: 10, color: _textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _buildAccuracySection(),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _loadEvaluation,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.refresh_rounded, size: 12, color: _textSecondary),
                SizedBox(width: 4),
                Text('Refresh evaluasi', style: TextStyle(fontSize: 10, color: _textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccuracySection() {
    if (_batchEval == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _bgCardAlt, borderRadius: BorderRadius.circular(10)),
        child: const Row(
          children: [
            Icon(Icons.hourglass_empty_rounded, size: 16, color: _textSecondary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Jalankan forecast untuk mulai evaluasi',
                style: TextStyle(fontSize: 11, color: _textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    if (_batchEval!['status'] == 'pending') {
      final remaining = _timeUntilFirstHorizon();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _accentGlow, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _accent.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 16, color: _accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MENUNGGU DATA AKTUAL',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800,
                      letterSpacing: 1, color: _accent,
                    ),
                  ),
                  Text(
                    remaining != null
                        ? 'Evaluasi tersedia dalam ${_formatDuration(remaining)}'
                        : 'Menunggu titik forecast pertama tiba',
                    style: const TextStyle(fontSize: 10, color: _accent),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final avgMae    = (_batchEval!['avgMae'] as num).toDouble();
    final isPartial = _batchEval!['status'] == 'partial';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatRow(
          label: isPartial ? 'MAE rata-rata (sebagian)' : 'MAE rata-rata',
          value: avgMae.toStringAsFixed(2),
          color: _textPrimary,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _bgCardAlt, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: _textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isPartial
                      ? 'Selisih sementara prediksi vs aktual: ${avgMae.toStringAsFixed(2)} poin '
                        '(${_batchEval!['evaluatedPoints']}/${_batchEval!['totalPoints']} titik tereval)'
                      : 'Selisih rata-rata prediksi vs aktual: ${avgMae.toStringAsFixed(2)} poin',
                  style: const TextStyle(fontSize: 11, color: _textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _StatRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: _textSecondary)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
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
  const _AlertLevelCard({required this.prediction, required this.status});

  @override
  Widget build(BuildContext context) {
    final levels = [
      _AlertLevel(label: 'KRITIS',  range: '0–39',   color: _colorRed,   bg: _colorRedBg,   icon: Icons.warning_amber_rounded,       active: status == QoSStatus.poor,      desc: 'Layanan terganggu parah'),
      _AlertLevel(label: 'WASPADA', range: '40–59',  color: _colorAmber, bg: _colorAmberBg, icon: Icons.info_outline_rounded,         active: status == QoSStatus.fair,      desc: 'Kualitas di bawah standar'),
      _AlertLevel(label: 'NORMAL',  range: '60–79',  color: _accent,     bg: _accentGlow,   icon: Icons.check_circle_outline_rounded, active: status == QoSStatus.good,      desc: 'Layanan beroperasi normal'),
      _AlertLevel(label: 'PRIMA',   range: '80–100', color: _colorGreen, bg: _colorGreenBg, icon: Icons.verified_rounded,             active: status == QoSStatus.excellent, desc: 'Kualitas optimal'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: levels.map((lvl) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: lvl.active ? lvl.bg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: lvl.active ? lvl.color.withOpacity(0.5) : _divider),
            ),
            child: Row(
              children: [
                Icon(lvl.icon, size: 18, color: lvl.active ? lvl.color : _textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lvl.label, style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800,
                        letterSpacing: 1, color: lvl.active ? lvl.color : _textSecondary,
                      )),
                      Text(lvl.desc, style: TextStyle(
                        fontSize: 10,
                        color: lvl.active ? lvl.color.withOpacity(0.7) : _textSecondary.withOpacity(0.5),
                      )),
                    ],
                  ),
                ),
                Text(lvl.range, style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: lvl.active ? lvl.color : _textSecondary, fontFamily: 'monospace',
                )),
                if (lvl.active) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: lvl.color.withOpacity(0.2), borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('AKTIF', style: TextStyle(
                      fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1, color: lvl.color,
                    )),
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
  final String   label, range, desc;
  final Color    color, bg;
  final IconData icon;
  final bool     active;
  const _AlertLevel({
    required this.label, required this.range, required this.color,
    required this.bg,    required this.icon,  required this.active, required this.desc,
  });
}