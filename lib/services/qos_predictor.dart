import 'dart:convert';
import 'package:http/http.dart' as http;

class MLService {

  static const String baseUrl = "http://192.168.1.14:8000";

  // 🔥 FIX: return multi-step
  static Future<Map<String, double>?> predict({
    required List<List<double>> sequence,
  }) async {

    try {

      final url = Uri.parse("$baseUrl/predict");

      final response = await http
          .post(
            url,
            headers: {
              "Content-Type": "application/json",
            },
            body: jsonEncode({
              "input": sequence
            }),
          )
          .timeout(const Duration(seconds: 10));

      // ================= STATUS CODE CHECK =================
      if (response.statusCode != 200) {
        print("Backend HTTP Error: ${response.statusCode}");
        return null;
      }

      // ================= PARSE RESPONSE =================
      final data = jsonDecode(response.body);

      print("Backend Response: $data"); // 🔥 FIX typo

      // ================= ERROR HANDLING =================
      if (data["status"] != "success") {
        print("Backend Error: $data");
        return null;
      }

      // ================= VALIDATE FIELD =================
      if (!data.containsKey("predictions")) {
        print("Invalid response format");
        return null;
      }

      final pred = data["predictions"];

      // ================= RETURN MULTI OUTPUT =================
      return {
        "30_min": (pred["30_min"] as num).toDouble(),
        "60_min": (pred["60_min"] as num).toDouble(),
        "90_min": (pred["90_min"] as num).toDouble(),
        "120_min": (pred["120_min"] as num).toDouble(),
      };

    } catch (e) {

      print("MLService error: $e");
      return null;

    }

  }

}