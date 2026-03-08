import 'package:flutter/material.dart';
import '../qos/MonitoringController.dart';
import '../models/data_qos.dart';
import '../services/network_service.dart';
import '../ui/status.dart';
import '../ui/Monitoring_page.dart';
// import '../services/export_excel.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;

  final MonitoringController _controller = MonitoringController();
  DataQoS? _current;
  bool _isMonitoring = false;

  final List<DataQoS> _qosHistory = [];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  // ================= START =================
  Future<void> _startMonitoring() async {
    await NetworkService.requestPermission();

    await _controller.startMonitoring((result) async {
      final ssid = await NetworkService.getSSID();
      final ip = await NetworkService.getIPAddress();
      final freq = await NetworkService.getFrequency();
      final band = NetworkService.getFrequencyBand(freq);

      if (!mounted) return;

      setState(() {
        _isMonitoring = true;

        final newData = DataQoS(
          timestamp: DateTime.now(),
          throughput: result.throughput,
          delay: result.delay,
          jitter: result.jitter,
          sinr: result.sinr,
          ssid: ssid,
          ip: ip,
          band: band,
        );
        _current = newData;
        _qosHistory.add(newData);
      });
    });
  }

  // ================= STOP =================
  void _stopMonitoring() {
    _controller.stopMonitoring();

    if (!mounted) return;

    setState(() {
      _isMonitoring = false;
      _current = null;
      _selectedIndex = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Monitoring dihentikan")),
    );
  }

  // ================= DASHBOARD CONTENT =================
  Widget _dashboardContent() {
    return Container(
      color: const Color(0xffF5F7FB),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _monitorCard(),
            const SizedBox(height: 20),

            if (_current != null) ...[
              _wifiInfoCard(),
              const SizedBox(height: 20),
              _parameterGrid(),
            ] else
              _warningCard(),
          ],
        ),
      ),
    );
  }

  // ================= MONITOR CARD =================
  Widget _monitorCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Status Monitoring",
                    style: TextStyle(fontWeight: FontWeight.w500)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isMonitoring ? Colors.green[50] : Colors.red[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _isMonitoring ? "Aktif" : "Tidak Aktif",
                    style: TextStyle(
                        color: _isMonitoring ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed:
                    _isMonitoring ? _stopMonitoring : _startMonitoring,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isMonitoring ? Colors.red : const Color(0xff4A6CF7),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                    _isMonitoring ? "Stop Monitoring" : "Aktifkan Monitoring"),
              ),
            )
          ],
        ),
      ),
    );
  }

  // ================= WARNING =================
  Widget _warningCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          "Monitoring belum aktif.\nSilahkan aktifkan monitoring untuk membaca parameter QoS jaringan WiFi.",
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  // ================= WIFI INFO =================
  Widget _wifiInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Informasi WiFi",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("SSID : ${_current?.ssid ?? '-'}"),
            Text("IP   : ${_current?.ip ?? '-'}"),
            Text("Band : ${_current?.band ?? '-'}"),
            const SizedBox(height: 8),
            Text("Update terakhir : ${_current?.timestamp ?? '-'}"),
          ],
        ),
      ),
    );
  }

  // ================= PARAMETER GRID =================
  Widget _parameterGrid() {
    final throughputMbps = ((_current?.throughput ?? 0) / 1000);

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _modernParam(
            "Throughput", "${throughputMbps.toStringAsFixed(2)} Mbps"),
        _modernParam(
            "Delay", "${(_current?.delay ?? 0).toStringAsFixed(2)} ms"),
        _modernParam(
            "Jitter", "${(_current?.jitter ?? 0).toStringAsFixed(2)} ms"),
        _modernParam(
            "SINR", "${(_current?.sinr ?? 0).toStringAsFixed(2)} dB"),
      ],
    );
  }

  Widget _modernParam(String title, String value) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold))
          ],
        ),
      ),
    );
  }

  // ================= MAIN BUILD =================
  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboardContent(),
      MonitoringPage(data: _current, isMonitoring: _isMonitoring),
      const Center(child: Text("Visualisasi")),
      const Center(child: Text("Stability")),
      SystemStatusPage(qosHistory: _qosHistory),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("QoS Monitoring WiFi"),
        backgroundColor: const Color(0xff4A6CF7),
        elevation: 0,
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 8,
        selectedItemColor: const Color(0xff4A6CF7),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: "Dashboard"),
          BottomNavigationBarItem(
              icon: Icon(Icons.wifi), label: "Monitoring"),
          BottomNavigationBarItem(
              icon: Icon(Icons.show_chart), label: "Visualisasi"),
          BottomNavigationBarItem(
              icon: Icon(Icons.speed), label: "Stability"),
          BottomNavigationBarItem(
              icon: Icon(Icons.info), label: "Status"),
        ],
      ),
    );
  }
}