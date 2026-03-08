import 'dart:io';
import 'package:excel/excel.dart';
import '../models/data_qos.dart';

Future<String?> exportQoSToExcelFromObject(List<DataQoS> dataList) async {
  try {
    var excel = Excel.createExcel();
    Sheet sheet = excel['QoS Monitoring'];

    // HEADER
    sheet.appendRow([
      'Timestamp',
      'SINR',
      'Throughput',
      'Delay',
      'Jitter'
    ]);

    // DATA
    for (var data in dataList) {
      sheet.appendRow([
        data.timestamp.toIso8601String(),
        data.sinr,
        data.throughput,
        data.delay,
        data.jitter,
      ]);
    }

    final now = DateTime.now();
    final fileName =
    "QoS_Monitoring_${now.year}${now.month}${now.day}_${now.hour}${now.minute}${now.second}.xlsx";

    // PATH DOWNLOAD ANDROID
    Directory dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) {
      dir.createSync(recursive: true);
    }

    String path = "${dir.path}/$fileName";

    File file = File(path);
    await file.writeAsBytes(excel.encode()!);

    return path;
  } catch (e) {
    print("EXPORT ERROR: $e");
    return null;
  }
}