import 'dart:convert';
import 'package:http/http.dart' as http;

class MLService {
  static const String baseUrl = 'https://netpredict.cloud';

  // =========================================================
  // /predict — 1 prediksi real-time (tidak berubah)
  // =========================================================
  static Future<Map<String, dynamic>?> runForecast({
    required List<List<double>> inputData,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'input': inputData}),
      );

      print('[MLService /predict] status=${response.statusCode}');
      print('[MLService /predict] body=${response.body}');

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded == null) return null;

      if (decoded['status'] != 'success') {
        print('[MLService /predict] status bukan success: ${decoded['status']}');
        return null;
      }

      final result = decoded['result'];
      if (result == null) return null;

      return {
        'final_prediction': (result['final_prediction'] as num).toDouble(),
        'series': List<double>.from(
          (result['series'] as List).map((e) => (e as num).toDouble()),
        ),
        'forecast_time': result['forecast_time'].toString(),
        'model': result['model'].toString(),
      };
    } catch (e, s) {
      print('[MLService /predict] EXCEPTION: $e\n$s');
      return null;
    }
  }

  // =========================================================
  // /predict_future — START JOB
  //
  // Mengirim 110 baris data + interval yang dipilih user (5 atau 30),
  // backend langsung balas job_id 
  //
  // WAJIB mengirim `intervalMinutes` di body request,supaya backend tahu mode mana yang dijalankan:
  //   - 5  -> hanya 300 step (≈5 menit simulasi) 
  //   - 30 -> 4 titik x 30 menit = total 2 jam simulasi
  //
  // Return:
  //   {'status': 'queued', 'job_id': '...'}                  → sukses mulai job
  //   {'status': 'waiting', 'message': '...'}                → data belum cukup (202)
  //   {'status': 'loading', 'message': '...'}                → model masih loading (503)
  //   null                                                    → error tak terduga
  // =========================================================
  static Future<Map<String, dynamic>?> startForecastFutureJob({
    required List<List<double>> inputData,
    required int intervalMinutes, // parameter baru, wajib diisi (5 atau 30)
  }) async {
    try {
      print('[MLService] Mengirim ke $baseUrl/predict_future');
      print('[MLService] Input rows: ${inputData.length}, interval: $intervalMinutes menit');

      final response = await http.post(
        Uri.parse('$baseUrl/predict_future'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'input': inputData,
          'interval_minutes': intervalMinutes, // dikirim ke backend
        }),
      ).timeout(const Duration(seconds: 20));

      print('[MLService] Status code: ${response.statusCode}');
      print('[MLService] Body: ${response.body}');

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      // 202 = data belum cukup
      if (response.statusCode == 202) {
        return {
          'status': 'waiting',
          'message': decoded['message'] as String? ?? 'Data belum cukup',
        };
      }

      // 503 = model masih loading
      if (response.statusCode == 503) {
        return {
          'status': 'loading',
          'message': decoded['message'] as String? ?? 'Model masih loading',
        };
      }

      if (response.statusCode != 200) {
        print('[MLService] HTTP error: ${response.statusCode}');
        return null;
      }

      if (decoded['status'] != 'queued' || decoded['job_id'] == null) {
        print('[MLService] Response tidak sesuai format job: $decoded');
        return null;
      }

      return {
        'status': 'queued',
        'job_id': decoded['job_id'].toString(),
      };
    } catch (e, s) {
      print('[MLService] EXCEPTION startForecastFutureJob: $e\n$s');
      return null;
    }
  }

  // =========================================================
  // /predict_future/{job_id} — POLL STATUS
  //
  // Return:
  //   {'status': 'processing', 'progress': 42.5}
  //   {'status': 'success', 'progress': 100,
  //    'predictions_5m_detail': [...], 'predictions_30m': [...]}
  //   {'status': 'error', 'message': '...'}
  //   null  → gagal hubungi server
  // =========================================================
  static Future<Map<String, dynamic>?> pollForecastFutureJob({
    required String jobId,
  }) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/predict_future/$jobId'))
          .timeout(const Duration(seconds: 15));

      print('[MLService poll] status=${response.statusCode} body=${response.body}');

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 404) {
        return {
          'status': 'error',
          'message': decoded['message'] as String? ?? 'job_id tidak ditemukan',
        };
      }

      if (response.statusCode == 500) {
        return {
          'status': 'error',
          'message': decoded['message'] as String? ?? 'Forecast gagal diproses',
        };
      }

      if (response.statusCode != 200) {
        print('[MLService poll] HTTP error: ${response.statusCode}');
        return null;
      }

      return decoded;
    } catch (e, s) {
      print('[MLService poll] EXCEPTION: $e\n$s');
      return null;
    }
  }
}