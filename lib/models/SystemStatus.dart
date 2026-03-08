import 'package:tflite_flutter/tflite_flutter.dart';

class SystemStatus {
  static bool modelLoaded = false;
  static Interpreter? interpreter;

  static Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset('assets/model_mssa_lstm_final.tflite');
      modelLoaded = true;
      print("MODEL KELOAD 🔥 (SystemStatus)");
    } catch (e) {
      modelLoaded = false;
      print("GAGAL LOAD MODEL ❌: $e");
    }
  }
}
