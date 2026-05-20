import 'dart:convert';
import 'package:http/http.dart' as http;

class MLService {

  static const String baseUrl =
      'http://192.168.137.1:8000';

  static Future<Map<String, dynamic>?> runForecast({
    required List<List<double>> inputData,
  }) async {

    try {

      final response = await http.post(

        Uri.parse('$baseUrl/predict'),

        headers: {
          'Content-Type': 'application/json',
        },

        body: jsonEncode({
          'input': inputData,
        }),
      );

      print('================================');
      print('STATUS CODE: ${response.statusCode}');
      print('RAW RESPONSE: ${response.body}');
      print('================================');

      if (response.statusCode != 200) {
        return null;
      }

      final decoded =
          jsonDecode(response.body);

      // ==============================
      // VALIDASI ROOT
      // ==============================
      if (decoded == null) {
        print('decoded null');
        return null;
      }

      // ==============================
      // STATUS FAILED
      // ==============================
      if (decoded['status'] != 'completed') {

        print(
          'Backend failed: '
          '${decoded['message']}'
        );

        return null;
      }

      // ==============================
      // RESULT
      // ==============================
      final result =
          decoded['result'];

      if (result == null) {

        print('result null');

        return null;
      }

      print('FINAL PRED: ${result['final_prediction']}');

      return {
        'final_prediction':
            (result['final_prediction'] as num)
                .toDouble(),

        'series':
            List<double>.from(
          (result['series'] as List).map(
            (e) => (e as num).toDouble(),
          ),
        ),

        'forecast_time':
            result['forecast_time']
                .toString(),

        'model':
            result['model']
                .toString(),
      };

    } catch (e, s) {

      print('MLService ERROR: $e');
      print(s);

      return null;
    }
  }
}