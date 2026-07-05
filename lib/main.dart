import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'database/db_helper.dart';
//import 'models/SystemStatus.dart';
import 'ui/dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // v8+: initCommunicationPort() ada di versi 8.x ke atas
  // Jika masih error, jalankan: flutter pub upgrade flutter_foreground_task
  FlutterForegroundTask.initCommunicationPort();

  // FIX (stuck di splash / ANR saat startup):
  // SEBELUMNYA: `await DBHelper.database` di sini membuat runApp() BARU
  // dipanggil setelah DB selesai dibuka. Kalau isolate lain (foreground
  // service, yang auto-restart lewat autoRunOnMyPackageReplaced /
  // autoRunOnBoot) kebetulan sedang buka/konfigurasi DB yang sama di waktu
  // bersamaan, proses buka DB di sini bisa tertahan lama menunggu lock ->
  // runApp() tidak pernah terpanggil -> splash screen tidak pernah hilang
  // (Flutter belum sempat gambar frame pertama) -> akhirnya Android
  // menganggap app tidak merespons (ANR).
  //
  // FIX: panggil runApp() SEKARANG JUGA supaya frame pertama langsung
  // tergambar dan splash hilang. DBHelper.database tetap dipicu di
  // background (tidak di-await) — getter-nya sudah lazy & cache sendiri
  // (`_db ??= await _initDB()`), jadi pemanggil berikutnya (mis. saat user
  // tekan "Aktifkan Monitoring") otomatis menunggu hasil yang sama tanpa
  // perlu init ulang.
  unawaited(DBHelper.database);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DashboardPage(),
    );
  }
}