import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/data_qos.dart';

class MonitoringPage extends StatefulWidget {
  final DataQoS? data;
  final bool isMonitoring;

  const MonitoringPage({
    super.key,
    required this.data,
    required this.isMonitoring,
  });

  @override
  State<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends State<MonitoringPage> {

  static const primary = Color(0xff4A6CF7);
  static const bg = Color(0xffF5F7FB);
  static const textSecondary = Color(0xff6B7280);

  final List<double> throughputHistory = [];
  final List<DateTime> timestamps = [];
  final List<DataQoS> qosHistory = [];

  // ================= UPDATE DATA REALTIME =================
  @override
  void didUpdateWidget(covariant MonitoringPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.data != null) {
      final data = widget.data!;
      final value = data.throughput / 1000;

      throughputHistory.add(value);
      timestamps.add(DateTime.now());
      qosHistory.add(data);

      if (throughputHistory.length > 60) {
        throughputHistory.removeAt(0);
        timestamps.removeAt(0);
      }
    }
  }

  // ================= STATISTIK =================
  double get avg30min {
    if (throughputHistory.isEmpty) return 0;
    return throughputHistory.reduce((a, b) => a + b) / throughputHistory.length;
  }

  double get maxToday =>
      throughputHistory.isEmpty ? 0 : throughputHistory.reduce((a, b) => a > b ? a : b);

  double get minToday =>
      throughputHistory.isEmpty ? 0 : throughputHistory.reduce((a, b) => a < b ? a : b);

  // ================= TIPHON =================
  String kategoriDelay(double v) {
    if (v < 150) return "Sangat Baik";
    if (v < 300) return "Baik";
    if (v < 450) return "Sedang";
    return "Buruk";
  }

  String kategoriJitter(double v) {
    if (v < 75) return "Sangat Baik";
    if (v < 125) return "Baik";
    if (v < 225) return "Sedang";
    return "Buruk";
  }

  String kategoriThroughput(double v) {
    if (v > 10) return "Sangat Baik";
    if (v > 5) return "Baik";
    if (v > 1) return "Sedang";
    return "Buruk";
  }

  String kategoriSINR(double v) {
    if (v > 20) return "Sangat Baik";
    if (v > 13) return "Baik";
    if (v > 0) return "Sedang";
    return "Buruk";
  }

  Color kategoriColor(String k) {
    switch (k) {
      case "Sangat Baik":
        return Colors.green;
      case "Baik":
        return primary;
      case "Sedang":
        return Colors.orange;
      case "Buruk":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget parameterBox(
    String title,
    double value,
    String unit,
    String kategori,
    String threshold,
  ) {
    final color = kategoriColor(kategori);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: textSecondary)),
          const SizedBox(height: 6),
          Text(
            "${value.toStringAsFixed(2)} $unit",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: kategori == "Buruk"
                ? 0.25
                : kategori == "Sedang"
                    ? 0.5
                    : kategori == "Baik"
                        ? 0.75
                        : 1,
            minHeight: 6,
            borderRadius: BorderRadius.circular(10),
            backgroundColor: Colors.grey.shade200,
            color: color,
          ),
          const SizedBox(height: 6),
          Text("Threshold: $threshold", style: const TextStyle(fontSize: 10, color: textSecondary)),
          Text(kategori, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget throughputChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Kecepatan Unduh Realtime", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    dotData: FlDotData(show: false),
                    spots: throughputHistory
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value))
                        .toList(),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget statCard(String title, double value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 11, color: textSecondary)),
            const SizedBox(height: 6),
            Text(value.toStringAsFixed(2),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text("Mbps", style: TextStyle(fontSize: 10))
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final throughput = (widget.data?.throughput ?? 0) / 1000;
    final delay = widget.data?.delay ?? 0;
    final jitter = widget.data?.jitter ?? 0;
    final sinr = widget.data?.sinr ?? 0;

    return Container(
      color: bg,
      child: widget.data == null
          ? const Center(child: Text("Monitoring belum aktif"))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [

                  // NILAI UTAMA
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      children: [
                        const Text("Kecepatan Unduh",
                            style: TextStyle(color: textSecondary)),
                        const SizedBox(height: 6),
                        Text(
                          throughput.toStringAsFixed(2),
                          style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: primary),
                        ),
                        const Text("Mbps"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.2,
                    children: [
                      parameterBox("Throughput", throughput, "Mbps",
                          kategoriThroughput(throughput), ">10 Mbps"),
                      parameterBox(
                          "Delay", delay, "ms", kategoriDelay(delay), "<150 ms"),
                      parameterBox("Jitter", jitter, "ms",
                          kategoriJitter(jitter), "<75 ms"),
                      parameterBox(
                          "SINR", sinr, "dB", kategoriSINR(sinr), ">20 dB"),
                    ],
                  ),

                  const SizedBox(height: 20),

                  throughputChart(),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      statCard("Rata-rata 30 menit", avg30min),
                      const SizedBox(width: 10),
                      statCard("Tertinggi Hari Ini", maxToday),
                      const SizedBox(width: 10),
                      statCard("Terendah Hari Ini", minToday),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}