import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
// import '../qos/MonitoringController.dart';
import 'dart:isolate';

class QosTaskHandler extends TaskHandler {

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    print("Foreground service started");
  }

  // ⭐ INI YANG WAJIB ADA
  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    // panggil pengambilan QoS di sini
    print("Collect QoS every second");
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    print("Foreground service stopped");
  }

  @override
  void onNotificationButtonPressed(String id) {
    print("Notification button pressed: $id");
  }
}
