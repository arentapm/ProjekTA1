import 'dart:convert';
import 'package:http/http.dart' as http;

class PredictionService {

  static Future<double?> predictQoS(List<double> qosData) async {

    final url = Uri.parse("http://192.168.1.10:8000/predict");

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "qos": qosData
      }),
    );

    if (response.statusCode == 200) {

      final data = jsonDecode(response.body);

      return data["prediction"];

    } else {
      return null;
    }
  }
}