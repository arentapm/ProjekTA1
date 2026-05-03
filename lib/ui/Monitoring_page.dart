import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_1/services/network_service.dart';
import '../models/data_qos.dart';


class MonitoringPage extends StatefulWidget {
  final DataQoS? data;
  final bool isMonitoring;
  final WiFiSnapshot? wiFiSnapshot;

  // [FIX 1] Hapus parameter prediction — tidak ada field quality di DataQoS.
  // Hasil prediksi ML tersimpan di DB (qos_stability_index), bukan di objek ini.

  final List<DataQoS> qosHistory;

  const MonitoringPage({
    super.key,
    required this.data,
    required this.isMonitoring,
    required this.qosHistory,
    required this.wiFiSnapshot,
  });

  @override
  State<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends State<MonitoringPage> {

  static const primary    = Color(0xFF185FA5);
  static const colorGreen = Color(0xFF3B6D11);
  static const colorAmber = Color(0xFF854F0B);
  static const colorRed   = Color(0xFFA32D2D);
  static const bgPage     = Color(0xFFF2F4F8);
  static const textSec    = Color(0xFF6B7280);

  // Getter langsung dari prop (tidak ada state lokal)
  List<double> get histThroughput => widget.qosHistory.map((q) => q.throughput).toList();
  List<double> get histDelay      => widget.qosHistory.map((q) => q.delay).toList();
  List<double> get histJitter     => widget.qosHistory.map((q) => q.jitter).toList();
  List<double> get histSINR       => widget.qosHistory.map((q) => q.sinr).toList();

  // ── STATISTIK ─────────────────────────────────────────────────────────
  double _avg(List<double> list) {
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  double _max(List<double> list) =>
      list.isEmpty ? 0 : list.reduce((a, b) => a > b ? a : b);

  double _min(List<double> list) =>
      list.isEmpty ? 0 : list.reduce((a, b) => a < b ? a : b);

  // ── TREN ──────────────────────────────────────────────────────────────
  String hitungTren(List<double> history, {bool invertedGood = false}) {
    if (history.length < 10) return "→ Data belum cukup";

    final recent = history.sublist(history.length - 5);
    final prev   = history.sublist(history.length - 10, history.length - 5);

    final avgRecent = _avg(recent);
    final avgPrev   = _avg(prev);
    final delta     = avgRecent - avgPrev;
    final threshold = avgPrev * 0.02;

    if (invertedGood) {
      if (delta < -threshold) return "↘ Membaik";
      if (delta > threshold)  return "↗ Memburuk (waspada)";
      return "→ Stabil";
    } else {
      if (delta > threshold)  return "↗ Meningkat";
      if (delta < -threshold) return "↘ Menurun (waspada)";
      return "→ Stabil";
    }
  }

  String hitungRTT(double delay) {
    if (delay <= 0) return "Tidak tersedia";
    return "${(delay * 2).toStringAsFixed(0)} ms (estimasi)";
  }

  String kualitasSinyalWifi(double sinr) {
    if (sinr >= 25) return "Excellent — sangat dekat router";
    if (sinr >= 15) return "Good — jarak sedang";
    if (sinr >= 10) return "Fair — agak jauh";
    if (sinr >= 0)  return "Poor — banyak interferensi";
    return "Very Poor — sinyal sangat lemah";
  }

  String estimasiKualitasLink(double sinr) {
    if (sinr >= 25) return "Sangat baik — throughput maksimal";
    if (sinr >= 15) return "Baik — cukup untuk semua aktivitas";
    if (sinr >= 10) return "Cukup — video call masih bisa";
    if (sinr >= 0)  return "Buruk — hanya browsing ringan";
    return "Kritis — koneksi tidak stabil";
  }

  // [FIX 2] utilisasiBand tidak lagi menerima band — hitung dengan asumsi
  // WiFi modern (nilai referensi 300 Mbps sebagai kapasitas umum).
  // Jika kelak band tersedia dari sumber lain, tinggal ganti nilainya.
  String utilisasiBand(double throughputMbps) {
    const maxMbps = 300.0; // referensi kapasitas WiFi umum
    final persen  = (throughputMbps / maxMbps * 100).clamp(0.0, 100.0);
    return "${persen.toStringAsFixed(1)}% dari kapasitas referensi";
  }

  // ── KATEGORI ──────────────────────────────────────────────────────────
  String kategoriThroughput(double v) {
    if (v > 10) return "Sangat Baik";
    if (v > 5)  return "Baik";
    if (v > 1)  return "Sedang";
    return "Buruk";
  }

  String kategoriDelay(double v) {
    if (v < 150) return "Sangat Baik";
    if (v < 300) return "Baik";
    if (v < 450) return "Sedang";
    return "Buruk";
  }

  String kategoriJitter(double v) {
    if (v < 75)  return "Sangat Baik";
    if (v < 125) return "Baik";
    if (v < 225) return "Sedang";
    return "Buruk";
  }

  String kategoriSINR(double v) {
    if (v >= 25) return "Sangat Baik";
    if (v >= 15) return "Baik";
    if (v >= 10) return "Sedang";
    return "Buruk";
  }

  Color kategoriColor(String k) {
    switch (k) {
      case "Sangat Baik": return colorGreen;
      case "Baik":        return primary;
      case "Sedang":      return colorAmber;
      case "Buruk":       return colorRed;
      default:            return Colors.grey;
    }
  }

  Color kategoriLightBg(String k) {
    switch (k) {
      case "Sangat Baik": return const Color(0xFFEAF3DE);
      case "Baik":        return const Color(0xFFE6F1FB);
      case "Sedang":      return const Color(0xFFFAEEDA);
      case "Buruk":       return const Color(0xFFFCEBEB);
      default:            return Colors.grey.shade100;
    }
  }

  double kategoriProgress(String k) {
    switch (k) {
      case "Sangat Baik": return 1.0;
      case "Baik":        return 0.75;
      case "Sedang":      return 0.5;
      case "Buruk":       return 0.25;
      default:            return 0;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case "good": return colorGreen;
      case "warn": return colorAmber;
      case "bad":  return colorRed;
      default:     return Colors.grey;
    }
  }

  // ── BOTTOM SHEET ──────────────────────────────────────────────────────
  void _showDetailSheet({
    required String title,
    required String subtitle,
    required String emoji,
    required double value,
    required String unit,
    required String kategori,
    required List<double> history,
    required List<Map<String, String>> thresholds,
    required List<Map<String, String>> impacts,
    required List<Map<String, String>> extraInfo,
  }) {
    final color   = kategoriColor(kategori);
    final lightBg = kategoriLightBg(kategori);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      Text(subtitle, style: const TextStyle(fontSize: 12, color: textSec)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(20)),
                  child: Text(kategori,
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _shStatCard("Saat ini", value.toStringAsFixed(2), unit, color),
                  const SizedBox(width: 8),
                  _shStatCard("Rata-rata", _avg(history).toStringAsFixed(2), unit, textSec),
                  const SizedBox(width: 8),
                  _shStatCard(
                    (title == "Delay" || title == "Jitter") ? "Terbaik" : "Tertinggi",
                    (title == "Delay" || title == "Jitter")
                        ? _min(history).toStringAsFixed(2)
                        : _max(history).toStringAsFixed(2),
                    unit,
                    textSec,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _miniBarChart(history, color, title),
              const SizedBox(height: 16),
              _shSectionTitle("STANDAR TIPHON / ITU-T"),
              ...thresholds.map((t) => _shRow(t["label"]!, t["value"]!)),
              const SizedBox(height: 14),
              _shSectionTitle("DAMPAK KE PENGALAMAN PENGGUNA"),
              ...impacts.map((i) => _impactItem(i["text"]!, _statusColor(i["status"] ?? "neutral"))),
              const SizedBox(height: 14),
              _shSectionTitle("INFORMASI DARI DATA TERUKUR"),
              ...extraInfo.map((e) => _shRow(e["key"]!, e["value"]!)),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: const Text("Tutup", style: TextStyle(color: Colors.black87)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HELPER WIDGETS ────────────────────────────────────────────────────
  Widget _shStatCard(String label, String val, String unit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: textSec)),
            const SizedBox(height: 4),
            Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color)),
            Text(unit, style: const TextStyle(fontSize: 9, color: textSec)),
          ],
        ),
      ),
    );
  }

  Widget _miniBarChart(List<double> history, Color color, String title) {
    final data = history.length > 20 ? history.sublist(history.length - 20) : history;
    if (data.isEmpty) {
      return const Text("Belum ada data histori",
          style: TextStyle(fontSize: 11, color: textSec));
    }
    final maxH = data.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Histori ${data.length} data terakhir",
              style: const TextStyle(fontSize: 11, color: textSec)),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.asMap().entries.map((e) {
                final ratio = maxH == 0 ? 0.0 : e.value.abs() / maxH;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 6.0 + 50 * ratio,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.4 + 0.6 * (e.key / data.length)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shSectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textSec)),
  );

  Widget _shRow(String key, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(key, style: const TextStyle(fontSize: 13, color: textSec)),
        Flexible(
          child: Text(val,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );

  Widget _impactItem(String text, Color dotColor) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: textSec))),
      ],
    ),
  );

  // ── IMPACT ────────────────────────────────────────────────────────────
  List<Map<String, String>> _impactThroughput(double mbps) => [
    {"text": "Streaming 4K: ${mbps > 25 ? "Lancar" : mbps > 5 ? "Perlu buffer" : "Tidak memadai"}", "status": mbps > 25 ? "good" : mbps > 5 ? "warn" : "bad"},
    {"text": "Video call HD: ${mbps > 1.5 ? "Lancar" : "Tidak stabil"}", "status": mbps > 1.5 ? "good" : "bad"},
    {"text": "Gaming online: ${mbps > 3 ? "Stabil" : "Mungkin lag"}", "status": mbps > 3 ? "good" : "warn"},
    {"text": "Download file: ${mbps > 5 ? "Cepat" : mbps > 1 ? "Sedang" : "Lambat"}", "status": mbps > 5 ? "good" : "warn"},
  ];

  List<Map<String, String>> _impactDelay(double ms) => [
    {"text": "Game online: ${ms < 150 ? "Playable" : ms < 300 ? "Terasa lag" : "Tidak bisa dimainkan"}", "status": ms < 150 ? "good" : ms < 300 ? "warn" : "bad"},
    {"text": "Video call: ${ms < 150 ? "Tidak ada lag" : "Delay terasa"}", "status": ms < 150 ? "good" : "warn"},
  ];

  List<Map<String, String>> _impactJitter(double ms) => [
    {"text": "VoIP & Video Call: ${ms < 75 ? "Sangat jernih" : ms < 125 ? "Normal" : "Putus-putus"}", "status": ms < 75 ? "good" : "warn"},
  ];

  List<Map<String, String>> _impactSINR(double sinr) => [
    {"text": "Kualitas link WiFi: ${kualitasSinyalWifi(sinr)}", "status": sinr >= 15 ? "good" : "warn"},
  ];

  // ── EXTRA INFO ────────────────────────────────────────────────────────
  // [FIX 3] Hapus akses d.ssid, d.band, d.ip — field tidak ada di DataQoS.
  // Informasi yang ditampilkan hanya dari 4 parameter terukur.

List<Map<String, String>> _extraThroughput(DataQoS d, List<double> hist) => [
  {"key": "Sumber Pengukuran", "value": "Monitoring jaringan lokal (real-time)"},
  {"key": "Throughput Saat Ini", "value": "${d.throughput.toStringAsFixed(2)} Mbps"},
  {"key": "Utilisasi (ref. 300 Mbps)", "value": utilisasiBand(d.throughput)},
  {"key": "Tren", "value": hitungTren(hist)},
];

  List<Map<String, String>> _extraDelay(DataQoS d, List<double> hist) => [
    {"key": "Metode Pengukuran", "value": "Delay antar paket jaringan"},
    {"key": "RTT Estimasi",      "value": hitungRTT(d.delay)},
    {"key": "Rata-rata",         "value": "${_avg(hist).toStringAsFixed(2)} ms"},
    {"key": "Tren",              "value": hitungTren(hist, invertedGood: true)},
  ];

  List<Map<String, String>> _extraJitter(DataQoS d, List<double> hist) => [
    {"key": "Cara Hitung", "value": "Variasi delay antar paket"},
    {"key": "Rata-rata",   "value": "${_avg(hist).toStringAsFixed(2)} ms"},
    {"key": "Tren",        "value": hitungTren(hist, invertedGood: true)},
  ];

  List<Map<String, String>> _extraSINR(DataQoS d, List<double> hist) {
    // [FIX 4] Tanpa field band, gunakan noise floor rata-rata WiFi (-93 dBm)
    const noiseFloor   = -93.0;
    final rssiEstimasi = d.sinr + noiseFloor;
    return [
      {"key": "Cara Hitung",    "value": "SINR = RSSI − Noise Floor"},
      {"key": "RSSI Estimasi",  "value": "${rssiEstimasi.toStringAsFixed(1)} dBm"},
      {"key": "Noise Floor",    "value": "$noiseFloor dBm (rata-rata WiFi)"},
      {"key": "Kualitas Link",  "value": estimasiKualitasLink(d.sinr)},
      {"key": "Tren",           "value": hitungTren(hist)},
    ];
  }

  // ── PARAMETER CARD ────────────────────────────────────────────────────
  Widget _paramCard({
    required String title,
    required String emoji,
    required double value,
    required String unit,
    required String threshold,
    required String kategori,
    required List<double> history,
    required List<Map<String, String>> thresholds,
    required List<Map<String, String>> impacts,
    required List<Map<String, String>> extraInfo,
    required String subtitle,
  }) {
    final color    = kategoriColor(kategori);
    final lightBg  = kategoriLightBg(kategori);
    final progress = kategoriProgress(kategori);

    return GestureDetector(
      onTap: () => _showDetailSheet(
        title: title, subtitle: subtitle, emoji: emoji,
        value: value, unit: unit, kategori: kategori,
        history: history, thresholds: thresholds,
        impacts: impacts, extraInfo: extraInfo,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 15))),
                ),
                Icon(Icons.info_outline_rounded, size: 15, color: color.withOpacity(0.5)),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 11, color: textSec)),
            const SizedBox(height: 2),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: value.toStringAsFixed(2),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: color)),
                  TextSpan(text: " $unit",
                      style: const TextStyle(fontSize: 11, color: textSec)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress, minHeight: 5,
              borderRadius: BorderRadius.circular(10), color: color),
            const SizedBox(height: 6),
            Text("Threshold: $threshold",
                style: const TextStyle(fontSize: 9, color: textSec)),
            Text(kategori,
                style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ── HERO CARD ─────────────────────────────────────────────────────────
  // [FIX 5] Hapus tampilan ssid/band/ip — field tidak ada di DataQoS
Widget _heroCard(double throughputMbps, String kategori) {
  final color   = kategoriColor(kategori);
  final lightBg = kategoriLightBg(kategori);

  final ssid = widget.wiFiSnapshot?.ssid ?? "-";
  final band = widget.wiFiSnapshot?.band ?? "-";
  final ip   = widget.wiFiSnapshot?.ip   ?? "-";

  return Container(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      children: [
        const Text("KECEPATAN UNDUH",
            style: TextStyle(fontSize: 11, color: textSec)),

        const SizedBox(height: 6),

        Text(throughputMbps.toStringAsFixed(2),
            style: TextStyle(fontSize: 56, fontWeight: FontWeight.w300, color: color)),

        const Text("Mbps", style: TextStyle(fontSize: 14, color: textSec)),

        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(20)),
          child: Text(kategori,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),

        const SizedBox(height: 12),

        // 🔥 TAMBAHAN INFO WIFI
        Text("SSID: $ssid", style: const TextStyle(fontSize: 11, color: textSec)),
        Text("IP: $ip", style: const TextStyle(fontSize: 11, color: textSec)),
        Text("Band: $band", style: const TextStyle(fontSize: 11, color: textSec)),

        if (widget.data != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              "⏱ ${widget.data!.timestamp.toString().substring(0, 19)}",
              style: const TextStyle(fontSize: 11, color: textSec),
            ),
          ),
      ],
    ),
  );
}

  // ── CHART ─────────────────────────────────────────────────────────────
  Widget _throughputChart() {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Kecepatan unduh realtime",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text("${histThroughput.length} data",
                  style: const TextStyle(fontSize: 10, color: textSec)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    color: primary,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                        show: true, color: primary.withOpacity(0.08)),
                    spots: histThroughput.isEmpty
                        ? [const FlSpot(0, 0)]
                        : histThroughput
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key.toDouble(), e.value))
                            .toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, double value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: textSec)),
            const SizedBox(height: 6),
            Text(value.toStringAsFixed(2),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Text("Mbps", style: TextStyle(fontSize: 9, color: textSec)),
          ],
        ),
      ),
    );
  }

@override
Widget build(BuildContext context) {
  final throughputMbps = widget.data?.throughput ?? 0.0;
  final delay          = widget.data?.delay       ?? 0.0;
  final jitter         = widget.data?.jitter      ?? 0.0;
  final sinr           = widget.data?.sinr        ?? 0.0;

  final katThroughput  = kategoriThroughput(throughputMbps);
  final katDelay       = kategoriDelay(delay);
  final katJitter      = kategoriJitter(jitter);
  final katSINR        = kategoriSINR(sinr);

  return Scaffold(
    backgroundColor: bgPage,
    body: widget.data == null
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text("Monitoring belum aktif",
                    style: TextStyle(color: textSec)),
              ],
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // 🔥 HERO CARD (SUDAH CENTER + RESPONSIVE)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _heroCard(throughputMbps, katThroughput),
                  ),
                ),

                const SizedBox(height: 16),

                const Text("PARAMETER QoS — TIPHON",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textSec,
                        letterSpacing: 0.5)),

                const SizedBox(height: 10),

                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.15,
                  children: [
                    _paramCard(
                      title: "Throughput", emoji: "📶",
                      value: throughputMbps, unit: "Mbps",
                      threshold: ">10 Mbps", kategori: katThroughput,
                      subtitle: "Kecepatan transfer data WiFi",
                      history: histThroughput,
                      thresholds: const [
                        {"label": "Sangat Baik", "value": "> 10 Mbps"},
                        {"label": "Baik",        "value": "5 – 10 Mbps"},
                        {"label": "Sedang",      "value": "1 – 5 Mbps"},
                        {"label": "Buruk",       "value": "< 1 Mbps"},
                      ],
                      impacts:   _impactThroughput(throughputMbps),
                      extraInfo: _extraThroughput(widget.data!, histThroughput),
                    ),
                    _paramCard(
                      title: "Delay", emoji: "⏱️",
                      value: delay, unit: "ms",
                      threshold: "<150 ms", kategori: katDelay,
                      subtitle: "Delay antar paket VPN",
                      history: histDelay,
                      thresholds: const [
                        {"label": "Sangat Baik", "value": "< 150 ms"},
                        {"label": "Baik",        "value": "150 – 300 ms"},
                        {"label": "Sedang",      "value": "300 – 450 ms"},
                        {"label": "Buruk",       "value": "> 450 ms"},
                      ],
                      impacts:   _impactDelay(delay),
                      extraInfo: _extraDelay(widget.data!, histDelay),
                    ),
                    _paramCard(
                      title: "Jitter", emoji: "📉",
                      value: jitter, unit: "ms",
                      threshold: "<75 ms", kategori: katJitter,
                      subtitle: "Variasi delay antar paket",
                      history: histJitter,
                      thresholds: const [
                        {"label": "Sangat Baik", "value": "< 75 ms"},
                        {"label": "Baik",        "value": "75 – 125 ms"},
                        {"label": "Sedang",      "value": "125 – 225 ms"},
                        {"label": "Buruk",       "value": "> 225 ms"},
                      ],
                      impacts:   _impactJitter(jitter),
                      extraInfo: _extraJitter(widget.data!, histJitter),
                    ),
                    _paramCard(
                      title: "SINR", emoji: "📡",
                      value: sinr, unit: "dB",
                      threshold: "≥25 dB", kategori: katSINR,
                      subtitle: "RSSI − Noise Floor (WiFi)",
                      history: histSINR,
                      thresholds: const [
                        {"label": "Sangat Baik", "value": "≥ 25 dB"},
                        {"label": "Baik",        "value": "15 – 24 dB"},
                        {"label": "Sedang",      "value": "10 – 14 dB"},
                        {"label": "Buruk",       "value": "< 10 dB"},
                      ],
                      impacts:   _impactSINR(sinr),
                      extraInfo: _extraSINR(widget.data!, histSINR),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                _throughputChart(),

                const SizedBox(height: 12),

                Row(
                  children: [
                    _statCard("Rata-rata", _avg(histThroughput)),
                    const SizedBox(width: 8),
                    _statCard("Tertinggi", _max(histThroughput)),
                    const SizedBox(width: 8),
                    _statCard("Terendah",  _min(histThroughput)),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
  );
}
}