// import 'package:tflite_flutter/tflite_flutter.dart';

// late Interpreter interpreter;

// Future<void> loadModel() async {
//   interpreter = await Interpreter.fromAsset('model_qos.tflite');
// }

// import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';

// Future<List<double>> loadArray(String path) async {
//   final tensor = await TensorBuffer.createFromFile(path);
//   return tensor.getDoubleList();
// }

// final mins = await loadArray('assets/mins.npy');
// final maxs = await loadArray('assets/maxs.npy');

// List<double> normalize(List<double> input, List<double> mins, List<double> maxs) {
//   List<double> norm = [];

//   for (int i = 0; i < input.length; i++) {
//     double denom = maxs[i] - mins[i];
//     if (denom == 0) denom = 1;
//     norm.add((input[i] - mins[i]) / denom);
//   }

//   return norm;
// }

// var input = List.generate(1, (_) =>
//   List.generate(20, (_) =>
//     List.filled(5, 0.0)
//   )
// );

// var output = List.generate(1, (_) => [0.0]);

// interpreter.run(input, output);

// print(output[0][0]); // hasil prediksi QoS