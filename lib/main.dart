import 'package:flutter/material.dart';
import 'package:flutter_application_1/database/db_helper.dart';
import 'ui/dashboard_page.dart';
// import 'qos/MonitoringController.dart';
import '../models/SystemStatus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
