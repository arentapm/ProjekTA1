import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MLService {
  static const String baseUrl = 'http://YOUR_BACKEND_URL/predict';


  static Future<Map<String, dynamic>?> predictWithEvaluation({
    required List<List<double>> input,
  }) async {
    try {
      if (input.isEmpty) return null;

      final response = await http
          .post(
            Uri.parse(baseUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({"data": input}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        print('[ML] HTTP ERROR ${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        print('[ML] FORMAT ERROR');
        return null;
      }

      return {
        "prediction": (decoded["prediction"] as num?)?.toDouble(),
        "evaluation": decoded["evaluation"] ?? {},
      };

    } on TimeoutException {
      print('[ML] TIMEOUT');
    } catch (e) {
      print('[ML] ERROR: $e');
    }

    return null;
  }
}