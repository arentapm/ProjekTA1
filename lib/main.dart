import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'database/db_helper.dart';
import 'models/SystemStatus.dart';
import 'ui/dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // v8+: initCommunicationPort() ada di versi 8.x ke atas
  // Jika masih error, jalankan: flutter pub upgrade flutter_foreground_task
  FlutterForegroundTask.initCommunicationPort();

  await DBHelper.database;
  await SystemStatus.loadModel();

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