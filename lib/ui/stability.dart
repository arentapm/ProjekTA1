import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/data_qos.dart';

class StabilityPage extends StatelessWidget {

  final DataQoS qos;
  final double? qosIndex; // 🔥 FIX: pakai multi prediction

  // 🔥 FIX: pakai multi prediction
  final Map<String, double>? predictions;

  const StabilityPage({
    super.key,
    required this.qos,
    this.predictions,
    this.qosIndex,
  });

  // ================= QoS CATEGORY =================

  String getQoSCategory(double? index) {
    if (index == null) return "Unknown";
    if (index >= 3.5) return "Excellent";
    if (index >= 2.5) return "Good";
    if (index >= 1.5) return "Fair";
    return "Poor";
  }

  Color getQoSColor(double? index) {
    if (index == null) return Colors.grey;
    if (index >= 3.5) return Colors.green;
    if (index >= 2.5) return Colors.lightGreen;
    if (index >= 1.5) return Colors.orange;
    return Colors.red;
  }

  // ================= AMBIL NILAI UTAMA =================
  // 🔥 kita pakai 30 menit sebagai representasi utama

  double? get mainPrediction {
    return predictions?["30_min"];
  }

  // ================= STABILITY =================

  String getStability(double? index) {
    if (index == null) return "Unknown";
    if (index >= 2.5) return "STABLE";
    return "UNSTABLE";
  }

  Color getStabilityColor(double? index) {
    if (index == null) return Colors.grey;
    if (index >= 2.5) return Colors.green;
    return Colors.red;
  }

  // ================= HISTORY INFO =================

  Widget historyInfo() {

    return Container(
      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),

      child: const Text(
        "Prediksi menggunakan data historis mingguan (per detik) "
        "yang diproses menggunakan model LSTM + MSSA untuk "
        "memprediksi kondisi jaringan 30–120 menit ke depan.",
        style: TextStyle(fontSize: 12),
      ),
    );
  }

  // ================= CHART =================

  Widget predictionChart() {

    if (predictions == null) {
      return const Center(child: Text("Belum ada data prediksi"));
    }

    final values = [
      predictions?["30_min"] ?? 0,
      predictions?["60_min"] ?? 0,
      predictions?["90_min"] ?? 0,
      predictions?["120_min"] ?? 0,
    ];

    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Text(
            "Forecast QoS (30–120 Menit)",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          SizedBox(
            height: 180,

            child: LineChart(
              LineChartData(

                gridData: FlGridData(show: true),

                borderData: FlBorderData(show: false),

                titlesData: FlTitlesData(show: false),

                lineBarsData: [

                  LineChartBarData(
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: FlDotData(show: true),

                    spots: values
                        .asMap()
                        .entries
                        .map((e) => FlSpot(
                              e.key.toDouble(),
                              e.value,
                            ))
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

  // ================= METRIC TILE =================

  Widget metricTile(String title, String value) {

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),

      child: ListTile(
        title: Text(title),

        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {

    final index = mainPrediction;

    return Scaffold(

      appBar: AppBar(
        title: const Text("Network Stability"),
        centerTitle: true,
      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(20),

        child: Column(

          children: [

            // ================= QoS INDEX =================

            Text(
              "QoS Prediction (30m)",
              style: Theme.of(context).textTheme.titleLarge,
            ),

            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(20),

              decoration: BoxDecoration(
                color: getQoSColor(index).withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
              ),

              child: Column(
                children: [

                  Text(
                    index?.toStringAsFixed(2) ?? "-",
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    getQoSCategory(index),
                    style: TextStyle(
                      fontSize: 18,
                      color: getQoSColor(index),
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                ],
              ),
            ),

            const SizedBox(height: 25),

            // ================= STABILITY =================

            Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,

              decoration: BoxDecoration(
                color: getStabilityColor(index).withOpacity(0.15),
                borderRadius: BorderRadius.circular(15),
              ),

              child: Column(
                children: [

                  const Text("Predicted Stability"),

                  const SizedBox(height: 10),

                  Text(
                    getStability(index),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: getStabilityColor(index),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            historyInfo(),

            const SizedBox(height: 20),

            predictionChart(),

            const SizedBox(height: 25),

            // ================= REAL DATA =================

            metricTile(
                "Throughput", "${qos.throughput.toStringAsFixed(2)} kbps"),

            metricTile(
                "Delay", "${qos.delay.toStringAsFixed(2)} ms"),

            metricTile(
                "Jitter", "${qos.jitter.toStringAsFixed(2)} ms"),

            metricTile(
                "SINR", "${qos.sinr.toStringAsFixed(2)} dB"),

          ],
        ),
      ),
    );
  }
}