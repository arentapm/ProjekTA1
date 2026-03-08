import 'package:flutter/material.dart';
import '../models/SystemStatus.dart';
import '../models/data_qos.dart';
import '../services/export_excel.dart';

class SystemStatusPage extends StatefulWidget {
  final List<DataQoS> qosHistory;

  const SystemStatusPage({
    super.key,
    required this.qosHistory,
  });

  @override
  State<SystemStatusPage> createState() => _SystemStatusPageState();
}

class _SystemStatusPageState extends State<SystemStatusPage> {
  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    await SystemStatus.loadModel();
    setState(() {}); // refresh UI setelah model siap
  }

  @override
  Widget build(BuildContext context) {
    final modelReady = SystemStatus.modelLoaded;

    return Scaffold(
      appBar: AppBar(title: const Text("System Status")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Status Sistem",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _statusItem("Model TFLite", modelReady),
            const SizedBox(height: 24),
            const Text(
              "Export Data Monitoring",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _exportCard(context),
          ],
        ),
      ),
    );
  }

  Widget _statusItem(String title, bool status) {
    return Card(
      child: ListTile(
        leading: Icon(
          status ? Icons.check_circle : Icons.error,
          color: status ? Colors.green : Colors.red,
        ),
        title: Text(title),
        subtitle: Text(status ? "Siap digunakan" : "Belum siap"),
      ),
    );
  }

  Widget _exportCard(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(
              Icons.download_rounded,
              size: 40,
              color: Colors.blue,
            ),
            const SizedBox(height: 10),
            const Text(
              "Export Data Monitoring",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Simpan data QoS ke file Excel atau CSV",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // ===== EXPORT EXCEL =====
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.table_chart),
                    label: const Text("Export Excel"),
                    onPressed: () async {
                      final path = await exportQoSToExcelFromObject(widget.qosHistory);

                      if (path != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("File Excel tersimpan di folder Download"),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Export gagal"),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}