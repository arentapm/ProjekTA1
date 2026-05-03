import 'dart:io';
import 'package:excel/excel.dart';
import '../models/data_qos.dart';

/// Export seluruh [dataList] ke file Excel di folder Download.
/// [dataList] adalah exportBuffer dari MonitoringController —
/// tidak dibatasi, berisi semua data sejak start() sampai stop().
Future<String?> exportQoSToExcelFromObject(List<DataQoS> dataList) async {
  try {
    if (dataList.isEmpty) {
      print("EXPORT: tidak ada data untuk diekspor");
      return null;
    }

    var excel = Excel.createExcel();
    Sheet sheet = excel['QoS Monitoring'];

    // HEADER
    sheet.appendRow([
      'No',
      'Timestamp',
      'Throughput (Mbps)',
      'Delay (ms)',
      'Jitter (ms)',
      'SINR (dB)',
    ]);

    // DATA — seluruh dataList tanpa batasan
    for (int i = 0; i < dataList.length; i++) {
      final data = dataList[i];
      sheet.appendRow([
        i + 1,
        data.timestamp.toIso8601String(),
        data.throughput,
        data.delay,
        data.jitter,
        data.sinr,
      ]);
    }

    final now = DateTime.now();
    final fileName =
        "QoS_${now.year}${now.month.toString().padLeft(2, '0')}"
        "${now.day.toString().padLeft(2, '0')}_"
        "${now.hour.toString().padLeft(2, '0')}"
        "${now.minute.toString().padLeft(2, '0')}"
        "${now.second.toString().padLeft(2, '0')}.xlsx";

    Directory dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) {
      dir.createSync(recursive: true);
    }

    final String path = "${dir.path}/$fileName";
    await File(path).writeAsBytes(excel.encode()!);

    print("EXPORT OK: $path (${dataList.length} baris)");
    return path;

  } catch (e) {
    print("EXPORT ERROR: $e");
    return null;
  }
}