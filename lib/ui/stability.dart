import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import '../models/data_qos.dart';
import '../qos/MonitoringController.dart';
import '../database/db_helper.dart';
import '../services/ml_service.dart';

// =========================================================
// COLORS
// =========================================================
const _primary = Color(0xFF1565C0);
const _primaryDark = Color(0xFF0D47A1);

const _green = Color(0xFF2E7D32);
const _amber = Color(0xFFF9A825);
const _red = Color(0xFFC62828);

const _bg = Color(0xFFF4F7FB);
const _card = Colors.white;

// =========================================================
// PAGE
// =========================================================
class StabilityPage extends StatefulWidget {
  final DataQoS qos;
  final List<DataQoS> qosHistory;

  const StabilityPage({
    super.key,
    required this.qos,
    required this.qosHistory,
  });

  @override
  State<StabilityPage> createState() => _StabilityPageState();
}

class _StabilityPageState extends State<StabilityPage> {
  final MonitoringController _ctrl = MonitoringController();

  double? _prediction;
  List<double> _predictionSeries = [];

  bool _isForecasting = false;
  String? _errorMessage;

  String? _lastModelName;
  DateTime? _lastForecastTime;

  int _rowCount = 0;

  // =======================================================
  // INIT
  // =======================================================
  @override
  void initState() {
    super.initState();
    _checkRowCount();
  }

  // =======================================================
  // DB CHECK
  // =======================================================
  Future<void> _checkRowCount() async {
    final rows = await DBHelper.getHistory(days: 30);

    if (!mounted) return;

    setState(() {
      _rowCount = rows.length;
    });
  }

  // =======================================================
  // QOS INDEX
  // =======================================================
  double _getQoSIndex(DataQoS d) {
    return _ctrl.calculateQoSIndex(d);
  }

  // =======================================================
  // CATEGORY
  // =======================================================
  String _getCategory(double? v) {
    if (v == null) return '-';

    if (v >= 80) return 'Sangat Baik';
    if (v >= 60) return 'Baik';
    if (v >= 40) return 'Sedang';

    return 'Buruk';
  }

  // =======================================================
  // COLOR
  // =======================================================
  Color _getColor(double? v) {
    if (v == null) return Colors.grey;

    if (v >= 80) return _green;
    if (v >= 60) return _primary;
    if (v >= 40) return _amber;

    return _red;
  }

  // =======================================================
  // COMPRESS
  // =======================================================
  List<double> _compressSeries(
    List<double> input, {
    int maxPoints = 12,
  }) {
    if (input.length <= maxPoints) return input;

    final step = input.length / maxPoints;
    final out = <double>[];

    for (int i = 0; i < maxPoints; i++) {
      final idx = (i * step).floor();
      out.add(input[idx]);
    }

    return out;
  }

  // =======================================================
  // FORECAST
  // =======================================================
  Future<void> _runForecast() async {
    if (_isForecasting) return;

    setState(() {
      _isForecasting = true;
      _errorMessage = null;
    });

    try {
      final rows = await DBHelper.getHistory(days: 30);

      if (rows.length < 110) {
        setState(() {
          _errorMessage =
              'Data training belum cukup (${rows.length}/110)';
        });
        return;
      }

      final inputData = rows.map((qos) {
        return [
          qos.throughput.toDouble(),
          qos.delay.toDouble(),
          qos.jitter.toDouble(),
          qos.sinr.toDouble(),
        ];
      }).toList();

      final result = await MLService.runForecast(
        inputData: inputData,
      );

      if (result == null) {
        setState(() {
          _errorMessage = 'Backend tidak merespons';
        });
        return;
      }

      final predRaw = result['final_prediction'];

      if (predRaw == null) {
        setState(() {
          _errorMessage = 'Prediction NULL';
        });
        return;
      }

      final predValue = (predRaw as num).toDouble();

      final rawSeries = result['series'];

      if (rawSeries == null) {
        setState(() {
          _errorMessage = 'Series NULL';
        });
        return;
      }

      final predSeries = List<double>.from(
        (rawSeries as List)
            .where((e) => e != null)
            .map((e) => (e as num).toDouble()),
      );

      final rawForecastTime = result['forecast_time'];

      final forecastTime = rawForecastTime != null
          ? DateTime.tryParse(rawForecastTime.toString()) ?? DateTime.now().add(const Duration(minutes: 30))
          : DateTime.now().add(const Duration(minutes: 30));

      await DBHelper.insertForecast(
        forecastTime: forecastTime,
        predictedQos: predValue,
        horizonMinutes: 30,
        modelName:
            result['model']?.toString() ?? 'MSSA-LSTM',
      );

      if (!mounted) return;

      setState(() {
        _prediction = predValue;

        _predictionSeries = _compressSeries(
          predSeries,
          maxPoints: 6,
        );

        _lastForecastTime = forecastTime;

        _lastModelName =
            result['model']?.toString() ??
                'MSSA-LSTM';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isForecasting = false;
        });
      }
    }
  }

  // =======================================================
  // BUILD
  // =======================================================
  @override
  Widget build(BuildContext context) {
    final qosNow = _getQoSIndex(widget.qos);

    final qosColor = _getColor(_prediction ?? qosNow);

    final histSlice = widget.qosHistory.length > 24
        ? widget.qosHistory.sublist(
            widget.qosHistory.length - 24,
          )
        : widget.qosHistory;

    final actualSeries =
        histSlice.map(_getQoSIndex).toList();

    final avg6h = actualSeries.isEmpty
        ? 0.0
        : actualSeries.reduce((a, b) => a + b) /
            actualSeries.length;

    final minVal = actualSeries.isEmpty
        ? 0.0
        : actualSeries.reduce(math.min);

    final maxVal = actualSeries.isEmpty
        ? 0.0
        : actualSeries.reduce(math.max);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // ============================================
              // HEADER
              // ============================================
              const Text(
                'Network Intelligence',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 4),

              const Text(
                'QoS Forecast',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(.1),
                      borderRadius:
                          BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'MSSA-LSTM · horizon 30 min',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _primary,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),

                  const SizedBox(width: 6),

                  const Text(
                    'Live',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ============================================
              // MAIN CARDS
              // ============================================
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      title: 'QoS Sekarang',
                      value:
                          '${qosNow.toStringAsFixed(0)}/100',
                      subtitle: _getCategory(qosNow),
                      color: _getColor(qosNow),
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: _metricCard(
                      title: 'Prediksi 30 min',
                      value: _prediction == null
                          ? '—'
                          : _prediction!
                              .toStringAsFixed(0),
                      subtitle: _prediction == null
                          ? 'belum dijalankan'
                          : _getCategory(_prediction),
                      color: qosColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // ============================================
              // NETWORK METRICS
              // ============================================
              Row(
                children: [
                  Expanded(
                    child: _smallMetric(
                      'Throughput',
                      '${widget.qos.throughput.toStringAsFixed(1)} Mbps',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _smallMetric(
                      'Delay',
                      '${widget.qos.delay.toStringAsFixed(0)} ms',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _smallMetric(
                      'SINR',
                      '${widget.qos.sinr.toStringAsFixed(1)} dB',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _smallMetric(
                      'Data Training',
                      '$_rowCount rows',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ============================================
              // CHART
              // ============================================
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius:
                      BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 18,
                      color:
                          Colors.black.withOpacity(.04),
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Grafik QoS — Aktual vs Forecast',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        _legend(_primary, 'Aktual'),
                        const SizedBox(width: 20),
                        _legend(_green, 'Forecast'),
                      ],
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      height: 240,
                      child: CustomPaint(
                        painter: _ForecastPainter(
                          actualValues:
                              actualSeries,
                          forecastValues:
                              _predictionSeries,
                        ),
                        child:
                            const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ============================================
              // TIMELINE
              // ============================================
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius:
                      BorderRadius.circular(26),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Timeline Prediksi — per 30 Menit',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 18),

                    ...List.generate(6, (index) {
                      final time =
                          DateTime.now().add(
                        Duration(
                          minutes: 30 * index,
                        ),
                      );

                      final pred =
                          _predictionSeries.length >
                                  index
                              ? _predictionSeries[
                                  index]
                              : null;

                      return Padding(
                        padding:
                            const EdgeInsets.only(
                          bottom: 14,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 70,
                              child: Text(
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .w600,
                                ),
                              ),
                            ),

                            Expanded(
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  20,
                                ),
                                child:
                                    LinearProgressIndicator(
                                  value: pred == null
                                      ? 0
                                      : pred /
                                          100,
                                  minHeight: 12,
                                  backgroundColor:
                                      Colors
                                          .grey
                                          .shade200,
                                  valueColor:
                                      AlwaysStoppedAnimation(
                                    _getColor(
                                      pred,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(
                              width: 14,
                            ),

                            SizedBox(
                              width: 44,
                              child: Text(
                                pred == null
                                    ? '??'
                                    : pred
                                        .toStringAsFixed(
                                        0,
                                      ),
                                textAlign:
                                    TextAlign.end,
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ============================================
              // STATS
              // ============================================
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      'Rata-rata 6 jam',
                      avg6h.toStringAsFixed(1),
                      '+2.1 dari kemarin',
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: _statCard(
                      'Min / Maks',
                      '${minVal.toStringAsFixed(0)} / ${maxVal.toStringAsFixed(0)}',
                      'dalam 30 hari terakhir',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      'Akurasi Model',
                      'RMSE = 1.67',
                      'MAE = 0.67',
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: _statCard(
                      'Model',
                      _lastModelName ??
                          'MSSA-LSTM v2.1',
                      _lastForecastTime == null
                          ? 'Belum pernah dijalankan'
                          : 'Last run ${_lastForecastTime!.hour.toString().padLeft(2, '0')}:${_lastForecastTime!.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              // ============================================
              // ERROR
              // ============================================
              if (_errorMessage != null)
                Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 18,
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                    ),
                  ),
                ),

              // ============================================
              // BUTTON
              // ============================================
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed:
                      _isForecasting
                          ? null
                          : _runForecast,
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        _primaryDark,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),
                    ),
                  ),
                  child: _isForecasting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color:
                                Colors.white,
                          ),
                        )
                      : const Text(
                          'Run Forecast',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // =======================================================
  // WIDGETS
  // =======================================================
  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            color: Colors.black.withOpacity(.04),
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            value,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallMetric(
    String title,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String title,
    String value,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String text) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: c,
            borderRadius:
                BorderRadius.circular(20),
          ),
        ),

        const SizedBox(width: 8),

        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// =========================================================
// PAINTER
// =========================================================
class _ForecastPainter extends CustomPainter {
  final List<double> actualValues;
  final List<double> forecastValues;

  _ForecastPainter({
    required this.actualValues,
    required this.forecastValues,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final all = [
      ...actualValues,
      ...forecastValues,
    ];

    if (all.isEmpty) return;

    final minVal =
        math.max(0, all.reduce(math.min) - 5);

    final maxVal =
        math.min(100, all.reduce(math.max) + 5);

    final range =
        (maxVal - minVal).clamp(10, 100);

    final total =
        actualValues.length +
            forecastValues.length;

    final stepX =
        size.width / math.max(1, total - 1);

    double toX(int i) => i * stepX;

    double toY(double v) {
      return size.height -
          ((v - minVal) / range) *
              size.height *
              .82 -
          size.height * .08;
    }

    // =====================================================
    // GRID
    // =====================================================
    final grid = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    for (int i = 0; i < 5; i++) {
      final y = size.height * i / 4;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        grid,
      );
    }

    // =====================================================
    // ACTUAL
    // =====================================================
    if (actualValues.length > 1) {
      final path = Path()
        ..moveTo(
          toX(0),
          toY(actualValues[0]),
        );

      for (int i = 1;
          i < actualValues.length;
          i++) {
        path.lineTo(
          toX(i),
          toY(actualValues[i]),
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = _primary
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // =====================================================
    // FORECAST
    // =====================================================
    if (forecastValues.isNotEmpty) {
      final offset =
          actualValues.length - 1;

      final path = Path()
        ..moveTo(
          toX(offset),
          toY(
            forecastValues.first,
          ),
        );

      for (int i = 1;
          i < forecastValues.length;
          i++) {
        path.lineTo(
          toX(offset + i),
          toY(forecastValues[i]),
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = _green
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );

      // POINTS
      for (int i = 0;
          i < forecastValues.length;
          i++) {
        canvas.drawCircle(
          Offset(
            toX(offset + i),
            toY(forecastValues[i]),
          ),
          5,
          Paint()..color = _green,
        );
      }
    }
  }

  @override
  bool shouldRepaint(
    covariant _ForecastPainter oldDelegate,
  ) {
    return !listEquals(
              oldDelegate.actualValues,
              actualValues,
            ) ||
        !listEquals(
          oldDelegate.forecastValues,
          forecastValues,
        );
  }
}