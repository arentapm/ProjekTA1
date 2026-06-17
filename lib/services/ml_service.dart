import 'dart:convert';
import 'package:http/http.dart' as http;

class MLService {

  static const String baseUrl =
      'https://netpredict.cloud';

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

  static Future<Map<String, dynamic>?> runForecastFuture({
  required List<List<double>> inputData,
}) async {
  try {
    print('[MLService] Mengirim request ke $baseUrl/predict_future');
    print('[MLService] Input rows: ${inputData.length}');

    final response = await http.post(
      Uri.parse('$baseUrl/predict_future'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'input': inputData}),
    );

    print('[MLService] Status code: ${response.statusCode}');
    print('[MLService] Raw body: ${response.body}');  

    if (response.statusCode == 202) {
      final decoded = jsonDecode(response.body);
      return {'status': 'waiting', 'message': decoded['message']};
    }

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    print('[MLService] Decoded keys: ${decoded.keys.toList()}');
    print('[MLService] Status value: ${decoded['status']}');
    print('[MLService] Predictions value: ${decoded['predictions']}');

    if (decoded['status'] != 'success') {
      print('[MLService] Status bukan success: ${decoded['status']}');
      return null;
    }

    final rawList = decoded['predictions'];
    print('[MLService] rawList type: ${rawList.runtimeType}');

    if (rawList == null || (rawList as List).isEmpty) {
      print('[MLService] rawList null atau kosong');
      return null;
    }

    return {
      'status'      : 'success',
      'predictions' : List<double>.from(
        rawList.map((e) => (e as num).toDouble()),
      ),
    };

  } catch (e, s) {
    print('[MLService] EXCEPTION: $e');
    print('[MLService] STACKTRACE: $s');
    return null;
  }
}
}