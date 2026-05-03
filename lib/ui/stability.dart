import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/data_qos.dart';

// =========================================================
// WARNA — SAMA PERSIS DENGAN MonitoringPage
// =========================================================
const _primary    = Color(0xFF185FA5);
const _colorGreen = Color(0xFF3B6D11);
const _colorAmber = Color(0xFF854F0B);
const _colorRed   = Color(0xFFA32D2D);
const _bgPage     = Color(0xFFF2F4F8);
const _textSec    = Color(0xFF6B7280);

// =========================================================
// ARC RING PAINTER
// =========================================================
class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..color = Colors.grey.shade200
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.color != color;
}

class _AnimatedArc extends StatefulWidget {
  final double value;
  final Color color;
  final Widget child;

  const _AnimatedArc({
    required this.value,
    required this.color,
    required this.child,
  });

  @override
  State<_AnimatedArc> createState() => _AnimatedArcState();
}

class _AnimatedArcState extends State<_AnimatedArc>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _anim = Tween<double>(begin: 0, end: widget.value / 100)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => CustomPaint(
          painter: _ArcPainter(progress: _anim.value, color: widget.color),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

// =========================================================
// CHART PAINTER — Aktual vs Prediksi
// =========================================================
class _ChartPainter extends CustomPainter {
  final List<double> actualValues;    // nilai QoS aktual dari history
  final List<double> predictedValues; // nilai QoS prediksi dari API
  final int splitIndex;               // index pemisah aktual vs prediksi

  _ChartPainter({
    required this.actualValues,
    required this.predictedValues,
    required this.splitIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final allValues = [...actualValues, ...predictedValues];
    if (allValues.isEmpty) return;

    final minVal = allValues.reduce(math.min).clamp(0, 100).toDouble();
    final maxVal = allValues.reduce(math.max).clamp(0, 100).toDouble();
    final range  = (maxVal - minVal).clamp(10, 100).toDouble();

    final totalPoints = actualValues.length + predictedValues.length;
    final stepX = size.width / (totalPoints - 1).clamp(1, totalPoints);

    double toY(double v) =>
        size.height - ((v - minVal) / range) * size.height * 0.85 - size.height * 0.05;
    double toX(int i) => i * stepX;

    // ── Grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // ── Split line (pemisah aktual vs prediksi)
    if (splitIndex > 0 && splitIndex < totalPoints) {
      final splitX = toX(splitIndex - 1);
      canvas.drawLine(
        Offset(splitX, 0),
        Offset(splitX, size.height),
        Paint()
          ..color = Colors.grey.shade400
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..shader = null,
      );
    }

    // ── Shaded area aktual
    if (actualValues.length > 1) {
      final fillPath = Path();
      fillPath.moveTo(toX(0), size.height);
      for (int i = 0; i < actualValues.length; i++) {
        fillPath.lineTo(toX(i), toY(actualValues[i]));
      }
      fillPath.lineTo(toX(actualValues.length - 1), size.height);
      fillPath.close();

      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF185FA5).withOpacity(0.18),
              const Color(0xFF185FA5).withOpacity(0.01),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
          ..style = PaintingStyle.fill,
      );
    }

    // ── Shaded area prediksi
    if (predictedValues.length > 1) {
      final offset = actualValues.length - 1;
      final fillPath = Path();
      fillPath.moveTo(toX(offset), size.height);
      for (int i = 0; i < predictedValues.length; i++) {
        fillPath.lineTo(toX(offset + i), toY(predictedValues[i]));
      }
      fillPath.lineTo(toX(offset + predictedValues.length - 1), size.height);
      fillPath.close();

      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF3B6D11).withOpacity(0.15),
              const Color(0xFF3B6D11).withOpacity(0.01),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
          ..style = PaintingStyle.fill,
      );
    }

    // ── Line aktual
    if (actualValues.length > 1) {
      final linePaint = Paint()
        ..color = _primary
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      path.moveTo(toX(0), toY(actualValues[0]));
      for (int i = 1; i < actualValues.length; i++) {
        final x0 = toX(i - 1);
        final x1 = toX(i);
        final y0 = toY(actualValues[i - 1]);
        final y1 = toY(actualValues[i]);
        path.cubicTo(
            x0 + (x1 - x0) * 0.5, y0, x0 + (x1 - x0) * 0.5, y1, x1, y1);
      }
      canvas.drawPath(path, linePaint);
    }

    // ── Line prediksi (dashed)
    if (predictedValues.length > 1) {
      final offset = actualValues.length - 1;
      final dashPaint = Paint()
        ..color = _colorGreen
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      path.moveTo(toX(offset), toY(predictedValues[0]));
      for (int i = 1; i < predictedValues.length; i++) {
        final x0 = toX(offset + i - 1);
        final x1 = toX(offset + i);
        final y0 = toY(predictedValues[i - 1]);
        final y1 = toY(predictedValues[i]);
        path.cubicTo(
            x0 + (x1 - x0) * 0.5, y0, x0 + (x1 - x0) * 0.5, y1, x1, y1);
      }

      // Dash effect manual
      final metrics  = path.computeMetrics().toList();
      const dashLen  = 8.0;
      const gapLen   = 5.0;
      for (final metric in metrics) {
        double dist = 0;
        bool draw   = true;
        while (dist < metric.length) {
          final len = draw ? dashLen : gapLen;
          final end = (dist + len).clamp(0, metric.length);
          if (draw) {
            canvas.drawPath(
              metric.extractPath(dist, end.toDouble()),
              dashPaint,
            );
          }
          dist += len;
          draw  = !draw;
        }
      }
    }

    // ── Dots aktual (titik terakhir)
    if (actualValues.isNotEmpty) {
      final lastI = actualValues.length - 1;
      canvas.drawCircle(
        Offset(toX(lastI), toY(actualValues[lastI])),
        5,
        Paint()..color = _primary,
      );
      canvas.drawCircle(
        Offset(toX(lastI), toY(actualValues[lastI])),
        3,
        Paint()..color = Colors.white,
      );
    }

    // ── Dots prediksi (titik terakhir)
    if (predictedValues.isNotEmpty) {
      final offset = actualValues.length - 1;
      final lastI  = predictedValues.length - 1;
      canvas.drawCircle(
        Offset(toX(offset + lastI), toY(predictedValues[lastI])),
        5,
        Paint()..color = _colorGreen,
      );
      canvas.drawCircle(
        Offset(toX(offset + lastI), toY(predictedValues[lastI])),
        3,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.actualValues != actualValues ||
      old.predictedValues != predictedValues;
}

// =========================================================
// MAIN PAGE
// =========================================================
class StabilityPage extends StatelessWidget {
  final DataQoS qos;

  /// Nilai prediksi tunggal untuk 30 menit ke depan (dari MLService)
  final double? prediction;

  /// List prediksi multi-titik dari API (List<double> QoS index)
  /// Setiap titik mewakili interval 30 menit ke depan
  final List<double> predictionSeries;

  /// History QoS aktual — diambil dari qosHistory di parent widget
  /// Digunakan untuk menampilkan grafik aktual vs prediksi
  final List<DataQoS> qosHistory;

  final Map<String, dynamic>? evalMetrics; 

  const StabilityPage({
    super.key,
    required this.qos,
    required this.qosHistory,
    this.prediction,
    this.predictionSeries = const [],
    this.evalMetrics, 
  });

  // ── HELPERS ─────────────────────────────────────────────
  String getQoSCategory(double? index) {
    if (index == null) return "Unknown";
    if (index >= 80) return "Sangat Baik";
    if (index >= 60) return "Baik";
    if (index >= 40) return "Sedang";
    return "Buruk";
  }

  Color getQoSColor(double? index) {
    if (index == null) return Colors.grey;
    if (index >= 80) return _colorGreen;
    if (index >= 60) return _primary;
    if (index >= 40) return _colorAmber;
    return _colorRed;
  }

  Color _lightBg(double? index) {
    if (index == null) return Colors.grey.shade100;
    if (index >= 80) return const Color(0xFFEAF3DE);
    if (index >= 60) return const Color(0xFFE6F1FB);
    if (index >= 40) return const Color(0xFFFAEEDA);
    return const Color(0xFFFCEBEB);
  }

  String getStability(double? index) {
    if (index == null) return "Unknown";
    if (index >= 60) return "STABLE";
    return "UNSTABLE";
  }

  Color getStabilityColor(double? index) {
    if (index == null) return Colors.grey;
    if (index >= 60) return _colorGreen;
    return _colorRed;
  }

  /// Hitung QoS index dari DataQoS
  /// ── TODO: Sesuaikan formula ini dengan formula yang dipakai saat training model
  /// Contoh formula sederhana berbasis normalisasi 4 parameter:
  double _calcQoSIndex(DataQoS d) {
    // Normalisasi throughput (asumsi max 20 Mbps = 20000 Kbps)
    final tNorm = (d.throughput / 20000).clamp(0.0, 1.0);
    // Normalisasi delay (semakin kecil semakin baik, max 600ms)
    final dNorm = (1 - (d.delay / 600).clamp(0.0, 1.0));
    // Normalisasi jitter (semakin kecil semakin baik, max 300ms)
    final jNorm = (1 - (d.jitter / 300).clamp(0.0, 1.0));
    // Normalisasi SINR (max 40 dB)
    final sNorm = (d.sinr / 40).clamp(0.0, 1.0);
    // Bobot sesuai standar QoS (bisa disesuaikan)
    return (tNorm * 0.35 + dNorm * 0.30 + jNorm * 0.20 + sNorm * 0.15) * 100;
  }

  /// Hitung RMSE antara aktual dan prediksi
  /// ── TODO: Aktifkan ketika predictionSeries sudah cukup panjang
  /// untuk dibandingkan 1:1 dengan actualSeries (len harus sama)
  double? _calcRMSE(List<double> actual, List<double> predicted) {
    if (actual.isEmpty || predicted.isEmpty) return null;
    final len = math.min(actual.length, predicted.length);
    if (len == 0) return null;
    double sum = 0;
    for (int i = 0; i < len; i++) {
      final diff = actual[i] - predicted[i];
      sum += diff * diff;
    }
    return math.sqrt(sum / len);
  }

  /// Hitung MAE antara aktual dan prediksi
  double? _calcMAE(List<double> actual, List<double> predicted) {
    if (actual.isEmpty || predicted.isEmpty) return null;
    final len = math.min(actual.length, predicted.length);
    if (len == 0) return null;
    double sum = 0;
    for (int i = 0; i < len; i++) {
      sum += (actual[i] - predicted[i]).abs();
    }
    return sum / len;
  }

  /// Hitung MAPE antara aktual dan prediksi
  double? _calcMAPE(List<double> actual, List<double> predicted) {
    if (actual.isEmpty || predicted.isEmpty) return null;
    final len = math.min(actual.length, predicted.length);
    if (len == 0) return null;
    double sum = 0;
    int count  = 0;
    for (int i = 0; i < len; i++) {
      if (actual[i] != 0) {
        sum += ((actual[i] - predicted[i]) / actual[i]).abs();
        count++;
      }
    }
    return count == 0 ? null : (sum / count) * 100;
  }

  // ── SECTION LABEL ────────────────────────────────────────
  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: _textSec,
        letterSpacing: 0.5,
      ),
    );
  }

  // ── INFO BOX (model prediksi) ─────────────────────────────
  Widget _historyInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F1FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primary.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.memory_rounded, color: _primary, size: 16),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "MODEL PREDIKSI",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Prediksi dilakukan menggunakan model Hybrid SSA-LSTM berbasis data historis yang telah diproses menggunakan metode MSSA. Output berupa nilai QoS Index per interval 30 menit ke depan.",
                  style: TextStyle(
                    fontSize: 12,
                    color: _textSec,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── INTERPRETASI ─────────────────────────────────────────
  Widget _interpretationBox(double? index) {
    if (index == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          "Belum ada hasil prediksi",
          style: TextStyle(color: _textSec),
        ),
      );
    }

    String desc;
    if (index >= 80) {
      desc = "Kualitas jaringan diprediksi sangat baik. Aktivitas seperti streaming, video call, dan download akan berjalan lancar tanpa gangguan.";
    } else if (index >= 60) {
      desc = "Kualitas jaringan cukup baik. Aktivitas umum masih dapat berjalan dengan stabil meskipun terdapat sedikit kemungkinan gangguan.";
    } else if (index >= 40) {
      desc = "Kualitas jaringan sedang. Kemungkinan terjadi delay atau jitter yang dapat mempengaruhi performa aplikasi real-time.";
    } else {
      desc = "Kualitas jaringan buruk. Disarankan untuk tidak melakukan aktivitas berat seperti streaming atau video call.";
    }

    final color   = getQoSColor(index);
    final bgColor = _lightBg(index);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.insights_rounded, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ANALISIS",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _textSec,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── GRAFIK AKTUAL VS PREDIKSI ─────────────────────────────
  Widget _predictionChart(List<double> actual, List<double> predicted) {
    final now = DateTime.now();

    // Label waktu aktual (mundur)
    List<String> actualLabels = List.generate(actual.length, (i) {
      final t = now.subtract(
          Duration(minutes: (actual.length - 1 - i) * 5));
      return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
    });

    // Label waktu prediksi (maju per 30 menit)
    List<String> predLabels = List.generate(predicted.length, (i) {
      final t = now.add(Duration(minutes: (i + 1) * 30));
      return "+${(i + 1) * 30}m";
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F1FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.show_chart_rounded,
                    color: _primary, size: 18),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Grafik QoS Index",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Aktual vs Prediksi",
                    style: TextStyle(fontSize: 11, color: _textSec),
                  ),
                ],
              ),
              const Spacer(),
              // Legend
              _legendDot(_primary, "Aktual"),
              const SizedBox(width: 10),
              _legendDot(_colorGreen, "Prediksi"),
            ],
          ),

          const SizedBox(height: 16),

          // Chart area
          SizedBox(
            height: 180,
            child: (actual.isEmpty && predicted.isEmpty)
                ? Center(
                    child: Text(
                      "Belum ada data grafik",
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 180),
                    painter: _ChartPainter(
                      actualValues: actual,
                      predictedValues: predicted,
                      splitIndex: actual.length,
                    ),
                  ),
          ),

          const SizedBox(height: 8),

          // X-axis labels (tampilkan beberapa saja agar tidak penuh)
          if (actual.isNotEmpty || predicted.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (actualLabels.isNotEmpty)
                  Text(
                    actualLabels.first,
                    style: TextStyle(
                        fontSize: 9, color: Colors.grey.shade400),
                  ),
                if (actualLabels.length > 2)
                  Text(
                    actualLabels[actualLabels.length ~/ 2],
                    style: TextStyle(
                        fontSize: 9, color: Colors.grey.shade400),
                  ),
                if (actualLabels.isNotEmpty)
                  Text(
                    "Sekarang",
                    style: TextStyle(
                      fontSize: 9,
                      color: _primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (predLabels.isNotEmpty)
                  Text(
                    predLabels.last,
                    style: TextStyle(
                      fontSize: 9,
                      color: _colorGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),

          // Info prediksi tiap titik
          if (predicted.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 12),
            const Text(
              "PREDIKSI PER INTERVAL",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _textSec,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(predicted.length, (i) {
                  final val   = predicted[i];
                  final color = getQoSColor(val);
                  final bg    = _lightBg(val);
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "+${(i + 1) * 30} min",
                          style: TextStyle(
                            fontSize: 9,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          val.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          getQoSCategory(val),
                          style: TextStyle(
                              fontSize: 8, color: color),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600)),
      ],
    );
  }

  // ── EVALUASI MODEL ────────────────────────────────────────
  // ── TODO: Metode _calcRMSE / _calcMAE / _calcMAPE menghitung secara
  //          real-time dari data aktual vs prediksi yang tersedia di Flutter.
  //          Nilai akan akurat ketika actual.length == predicted.length
  //          (yaitu ketika sudah ada cukup history prediksi sebelumnya).
  //          Jika ingin nilai evaluasi dari training (statis), ganti
  //          dengan hardcode: rmse = 2.34, mae = 1.87, mape = 3.21.
  Widget _evaluationCard(List<double> actual, List<double> predicted) {
  // Prioritaskan nilai dari backend jika ada
  final rmse = evalMetrics != null
      ? (evalMetrics!["rmse"] as num?)?.toDouble()
      : _calcRMSE(actual, predicted);
  final mae  = evalMetrics != null
      ? (evalMetrics!["mae"]  as num?)?.toDouble()
      : _calcMAE(actual, predicted);
  final mape = evalMetrics != null
      ? (evalMetrics!["mape"] as num?)?.toDouble()
      : _calcMAPE(actual, predicted);

  final hasData = rmse != null && mae != null && mape != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F1FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assessment_rounded,
                    color: _primary, size: 18),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Evaluasi Model",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Dihitung dari aktual vs prediksi",
                    style: TextStyle(fontSize: 11, color: _textSec),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 14),

          if (!hasData)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAEEDA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: _colorAmber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Evaluasi tersedia setelah ada data aktual dan prediksi yang dapat dibandingkan.",
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                    child: _evalMetricTile(
                        "RMSE",
                        rmse!.toStringAsFixed(2),
                        "Root Mean Squared Error",
                        rmse < 5
                            ? _colorGreen
                            : rmse < 10
                                ? _colorAmber
                                : _colorRed)),
                const SizedBox(width: 8),
                Expanded(
                    child: _evalMetricTile(
                        "MAE",
                        mae!.toStringAsFixed(2),
                        "Mean Absolute Error",
                        mae < 5
                            ? _colorGreen
                            : mae < 10
                                ? _colorAmber
                                : _colorRed)),
                const SizedBox(width: 8),
                Expanded(
                    child: _evalMetricTile(
                        "MAPE",
                        "${mape!.toStringAsFixed(1)}%",
                        "Mean Abs % Error",
                        mape < 5
                            ? _colorGreen
                            : mape < 15
                                ? _colorAmber
                                : _colorRed)),
              ],
            ),

          // ── TODO: Hapus komentar di bawah jika ingin pakai nilai statis
          // ── dari hasil training (jika backend tidak mengirim evaluasi):
          // Row(children: [
          //   Expanded(child: _evalMetricTile("RMSE", "2.34", "Root Mean Squared Error", _colorGreen)),
          //   const SizedBox(width: 8),
          //   Expanded(child: _evalMetricTile("MAE",  "1.87", "Mean Absolute Error",     _colorGreen)),
          //   const SizedBox(width: 8),
          //   Expanded(child: _evalMetricTile("MAPE", "3.2%", "Mean Abs % Error",        _colorGreen)),
          // ]),
        ],
      ),
    );
  }

  Widget _evalMetricTile(
      String label, String value, String desc, Color color) {
    final bg = color == _colorGreen
        ? const Color(0xFFEAF3DE)
        : color == _colorAmber
            ? const Color(0xFFFAEEDA)
            : const Color(0xFFFCEBEB);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: TextStyle(
              fontSize: 9,
              color: color.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    final index     = prediction;
    final qosColor  = getQoSColor(index);
    final bgColor   = _lightBg(index);
    final stabColor = getStabilityColor(index);
    final category  = getQoSCategory(index);

    // Ambil N data aktual terakhir dari qosHistory untuk grafik
    // Ambil max 12 titik agar grafik tidak terlalu padat
    final maxActual   = 12;
    final histSlice   = qosHistory.length > maxActual
        ? qosHistory.sublist(qosHistory.length - maxActual)
        : qosHistory;
    final actualSeries = histSlice.map(_calcQoSIndex).toList();

    return Scaffold(
      backgroundColor: _bgPage,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── QOS HERO CARD ─────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -30, right: -20,
                    child: Container(
                      width: 110, height: 110,
                      decoration: BoxDecoration(
                          color: bgColor, shape: BoxShape.circle),
                    ),
                  ),
                  Column(
                    children: [
                      const Text(
                        "QoS INDEX PREDICTION — 30 MIN AHEAD",
                        style: TextStyle(
                          fontSize: 11,
                          color: _textSec,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 20),

                      _AnimatedArc(
                        value: index ?? 0,
                        color: qosColor,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              index?.toStringAsFixed(1) ?? "–",
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w300,
                                color: qosColor,
                                height: 1,
                              ),
                            ),
                            Text(
                              "/ 100",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade400),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            color: qosColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),
                      Text(
                        "Scale: 0 (Worst) — 100 (Best)",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── STABILITY CARD ────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 16, horizontal: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: stabColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: stabColor == _colorGreen
                          ? const Color(0xFFEAF3DE)
                          : const Color(0xFFFCEBEB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      stabColor == _colorGreen
                          ? Icons.check_circle_outline_rounded
                          : Icons.warning_amber_rounded,
                      color: stabColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Predicted Stability",
                          style: TextStyle(
                              fontSize: 11, color: _textSec)),
                      Text(
                        getStability(index),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: stabColor,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 60,
                    child: LinearProgressIndicator(
                      value: (index ?? 0) / 100,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(6),
                      backgroundColor: Colors.grey.shade200,
                      color: stabColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── GRAFIK AKTUAL VS PREDIKSI ─────────────────────
            _sectionLabel("GRAFIK PREDIKSI"),
            const SizedBox(height: 10),
            _predictionChart(actualSeries, predictionSeries),

            const SizedBox(height: 16),

            // ── EVALUASI MODEL ────────────────────────────────
            _sectionLabel("EVALUASI MODEL"),
            const SizedBox(height: 10),
            _evaluationCard(actualSeries, predictionSeries),

            const SizedBox(height: 20),

            // ── MODEL INFO ────────────────────────────────────
            _sectionLabel("MODEL PREDIKSI"),
            const SizedBox(height: 8),
            _historyInfo(),

            const SizedBox(height: 12),

            // ── ANALISIS ──────────────────────────────────────
            _sectionLabel("ANALISIS HASIL"),
            const SizedBox(height: 8),
            _interpretationBox(index),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}