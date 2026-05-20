import 'dart:io';
import 'package:excel/excel.dart';
import '../database/db_helper.dart';

// ════════════════════════════════════════════════════════════════
// Export SELURUH data dari SQLite ke Excel (tanpa filter)
// ════════════════════════════════════════════════════════════════
Future<String?> exportQoSToExcel() async {
  return _doExport(sinceTimestamp: null);
}

// ════════════════════════════════════════════════════════════════
// Export hanya data SEJAK timestamp tertentu (data sesi ini)
// ════════════════════════════════════════════════════════════════
Future<String?> exportQoSSessionToExcel({
  required DateTime since,
}) async {
  return _doExport(sinceTimestamp: since);
}

// ════════════════════════════════════════════════════════════════
// Core export — bisa filter by timestamp atau tidak
// ════════════════════════════════════════════════════════════════
Future<String?> _doExport({DateTime? sinceTimestamp}) async {
  try {
    final db = await DBHelper.database;

    final rows = sinceTimestamp != null
        ? await db.query(
            'data_qos',
            where:     'timestamp >= ?',
            whereArgs: [sinceTimestamp.toIso8601String()],
            orderBy:   'timestamp ASC',
          )
        : await db.query(
            'data_qos',
            orderBy: 'timestamp ASC',
          );

    if (rows.isEmpty) {
      print('EXPORT: tidak ada data');
      return null;
    }

    final label = sinceTimestamp != null ? 'sesi' : 'semua';
    print('EXPORT ($label): ${rows.length} baris...');

    var excel = Excel.createExcel();
    Sheet sheet = excel['QoS Monitoring'];

    // Header
    sheet.appendRow([
      'No', 'Timestamp',
      'Throughput (Mbps)', 'Delay (ms)',
      'Jitter (ms)', 'SINR (dB)',
    ]);

    // Data
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      sheet.appendRow([
        i + 1,
        row['timestamp'] ?? '',
        row['throughput'] ?? 0.0,
        row['delay'] ?? 0.0,
        row['jitter'] ?? 0.0,
        row['sinr'] ?? 0.0,
      ]);
    }

    final now      = DateTime.now();
    final suffix   = sinceTimestamp != null ? '_sesi' : '_semua';
    final fileName =
        'QoS$suffix'
        '_${now.year}${now.month.toString().padLeft(2,'0')}'
        '${now.day.toString().padLeft(2,'0')}'
        '_${now.hour.toString().padLeft(2,'0')}'
        '${now.minute.toString().padLeft(2,'0')}'
        '${now.second.toString().padLeft(2,'0')}.xlsx';

    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) dir.createSync(recursive: true);

    final path = '${dir.path}/$fileName';
    await File(path).writeAsBytes(excel.encode()!);

    print('EXPORT OK: $path (${rows.length} baris)');
    return path;

  } catch (e) {
    print('EXPORT ERROR: $e');
    return null;
  }
}

// ════════════════════════════════════════════════════════════════
// Hitung total baris di DB
// ════════════════════════════════════════════════════════════════
Future<int> getTotalQoSCount() async {
  try {
    final db     = await DBHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM data_qos',
    );
    return (result.first['count'] as int?) ?? 0;
  } catch (e) {
    return 0;
  }
}