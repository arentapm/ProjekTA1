// ════════════════════════════════════════════════════════════════════
// DataQoS — model sesuai tabel data_qos di ERD
//
// Kolom tabel:
//   id_qos     INTEGER PK
//   timestamp  DATETIME
//   throughput FLOAT
//   delay      FLOAT
//   jitter     FLOAT
//   sinr       FLOAT
//
// ════════════════════════════════════════════════════════════════════
class DataQoS {
  final int?     idQos;
  final DateTime timestamp;
  final double   throughput;
  final double   delay;
  final double   jitter;
  final double   sinr;

  const DataQoS({
    this.idQos,
    required this.timestamp,
    required this.throughput,
    required this.delay,
    required this.jitter,
    required this.sinr,
  });

  // ── From Map (DB) ─────────────────────────────────────────────
  factory DataQoS.fromMap(Map<String, dynamic> map) {
    return DataQoS(
      idQos:      map['id_qos'] as int?,
      timestamp:  DateTime.parse(map['timestamp'] as String),
      throughput: (map['throughput'] as num).toDouble(),
      delay:      (map['delay']      as num).toDouble(),
      jitter:     (map['jitter']     as num).toDouble(),
      sinr:       (map['sinr']       as num).toDouble(),

    );
  }

  // ── To Map ────────────────────────────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      'timestamp':  timestamp.toIso8601String(),
      'throughput': throughput,
      'delay':      delay,
      'jitter':     jitter,
      'sinr':       sinr,
    };
  }

  // ── Copy With ─────────────────────────────────────────────────
  DataQoS copyWith({
    int?     idQos,
    DateTime? timestamp,
    double?  throughput,
    double?  delay,
    double?  jitter,
    double?  sinr,
  }) {
    return DataQoS(
      idQos:      idQos      ?? this.idQos,
      timestamp:  timestamp  ?? this.timestamp,
      throughput: throughput ?? this.throughput,
      delay:      delay      ?? this.delay,
      jitter:     jitter     ?? this.jitter,
      sinr:       sinr       ?? this.sinr,
    );
  }

  @override
  String toString() {
    return 'DataQoS('
        'id=$idQos, '
        'tp=${throughput.toStringAsFixed(2)} Mbps, '
        'delay=${delay.toStringAsFixed(1)} ms, '
        'jitter=${jitter.toStringAsFixed(1)} ms, '
        'sinr=${sinr.toStringAsFixed(1)} dB)';
  }
}