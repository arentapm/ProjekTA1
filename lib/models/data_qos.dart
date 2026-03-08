class DataQoS {
  final DateTime timestamp; //variabel

  final double throughput;
  final double delay;
  final double jitter;
  final double sinr;

  final String? ssid;
  final String? ip;
  final String? band;

  DataQoS({
    required this.timestamp,
    required this.throughput,
    required this.delay,
    required this.jitter,
    required this.sinr,
    this.ssid,
    this.ip,
    this.band,
  });

  /// Method sesuai class diagram
  DataQoS getQoSData() {
    return this;
  }
}
