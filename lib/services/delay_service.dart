import 'dart:io';

class DelayService {
  static Future<double> measureDelay() async {
    final stopwatch = Stopwatch()..start();

    try {
      final socket = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds.toDouble();
    } catch (_) {
      return 0;
    }
  }
}
