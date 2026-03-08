import 'dart:math';

class QoSCalculator {
    static double calculateThroughput(int deltaBytes, double intervalSeconds) {
    if (intervalSeconds <= 0) return 0;

    final bits = deltaBytes * 8;
    final kbps = bits / 1000 / intervalSeconds;

    return kbps;
  }


  static double calculateSINR({
    required double signalPowerDbm,
    required double interferenceDbm,
    required double noiseDbm,
  }) {
    final P = pow(10, signalPowerDbm / 10);
    final I = pow(10, interferenceDbm / 10);
    final N = pow(10, noiseDbm / 10);

    final sinrLinear = P / (I + N);

    return 10 * log(sinrLinear) / ln10;
  }

  static double calculateJitter(double previousDelay, double currentDelay) {
    return (currentDelay - previousDelay).abs();
  }
}
