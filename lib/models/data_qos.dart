class DataQoS {

  final int? idQos;

  final DateTime timestamp;

  final double throughput;
  final double delay;
  final double jitter;
  final double sinr;

  final String? ssid;
  final String? ip;
  final String? band;

  DataQoS({
    this.idQos,
    required this.timestamp,
    required this.throughput,
    required this.delay,
    required this.jitter,
    required this.sinr,
    this.ssid,
    this.ip,
    this.band,
  });

  factory DataQoS.fromMap(Map<String, dynamic> map) {

    return DataQoS(
      idQos: map["id_qos"],
      timestamp: DateTime.parse(map["timestamp"]),
      throughput: (map["throughput"] as num).toDouble(),
      delay: (map["delay"] as num).toDouble(),
      jitter: (map["jitter"] as num).toDouble(),
      sinr: (map["sinr"] as num).toDouble(),
    );

  }

  Map<String, dynamic> toMap() {
    return {
      "timestamp": timestamp.toIso8601String(),
      "throughput": throughput,
      "delay": delay,
      "jitter": jitter,
      "sinr": sinr,
    };
  }

  /// Method sesuai class diagram
  DataQoS getQoSData() {
    return this;
  }

}