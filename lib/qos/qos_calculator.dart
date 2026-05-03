import 'dart:math';

// ════════════════════════════════════════════════════════════════════
// QoSCalculator — Estimasi SINR WiFi (hanya metode dinamis & label)
//
// File ini menyediakan:
//   [1] estimasiSINRDinamis() — SINR dari scan AP tetangga (benar)
//   [2] sinrKeLabel()         — label kualitas SINR
//   [3] rssiKeLabel()         — label kualitas RSSI (untuk log)
//
// Semua metode estimasi SINR menggunakan konversi domain linear
// yang benar:
//   SINR (dB) = 10 × log10( P_signal / (P_interference + P_noise) )
//   dengan P dalam satuan mW = 10^(dBm/10)
//
//
// Referensi:
//   Goldsmith, "Wireless Communications", Cambridge UP, 2005.
//   IEEE 802.11-2020 Standard, Annex E.
//   Halperin et al., ACM SIGCOMM 2010.
// ════════════════════════════════════════════════════════════════════

class QoSCalculator {

  // Noise floor per band (IEEE 802.11-2020 Annex E)
  static const double _noiseFloor24Ghz = -92.0; // dBm
  static const double _noiseFloor5Ghz  = -95.0; // dBm

  // ══════════════════════════════════════════════════════════════
  // ESTIMASI SINR DINAMIS
  //
  // Interferensi dihitung dari jumlah & kekuatan AP tetangga
  // di channel yang sama (co-channel) atau berdekatan (adjacent).
  //
  // Model reduksi:
  //   - Co-channel   → daya penuh (tidak ada reduksi filter)
  //   - Adjacent     → reduksi 20 dB (faktor 1/100 dalam linear)
  //   - Channel jauh → diabaikan (reduksi > 40 dB)
  //
  // Penjumlahan daya dalam skala linear (mW):
  //   P_interf_total = Σ P_AP[i]  (dalam mW)
  //
  // Rumus SINR akhir (domain linear):
  //   SINR = P_signal / (P_interference + P_noise)
  //   SINR_dB = 10 × log10(SINR)
  // ══════════════════════════════════════════════════════════════

  /// Estimasi SINR dengan interferensi dari AP tetangga.
  static SINREstimate estimasiSINRDinamis({
    required double           signalPowerDbm,
    required int              currentChannelMhz,
    required List<NeighborAP> neighborAPs,
  }) {
    // Validasi frekuensi
    if (currentChannelMhz <= 0) {
      return SINREstimate(
        sinrDb:          null,
        noiseDbm:        _noiseFloor24Ghz,
        interferenceDbm: null,
        coChannelCount:  0,
        adjChannelCount: 0,
        metode:          'invalid_frequency',
      );
    }

    final bool is5GHzBand = currentChannelMhz >= 4900;
    final double noiseDbm = is5GHzBand ? _noiseFloor5Ghz : _noiseFloor24Ghz;

    // Validasi RSSI
    if (signalPowerDbm <= -110 || signalPowerDbm >= 0) {
      return SINREstimate(
        sinrDb:          null,
        noiseDbm:        noiseDbm,
        interferenceDbm: null,
        coChannelCount:  0,
        adjChannelCount: 0,
        metode:          'invalid_rssi',
      );
    }

    // ── Jumlahkan interferensi dalam skala linear ─────────────────
    int    coChannelCount       = 0;
    int    adjChannelCount      = 0;
    double interferenceLinearMw = 0.0;

    for (final ap in neighborAPs) {
      if (ap.rssiDbm <= -110 || ap.rssiDbm >= 0) continue;

      final relasi = _cekRelasiChannel(
        currentMhz:  currentChannelMhz,
        neighborMhz: ap.frequencyMhz,
        is5GHz:      is5GHzBand,
      );

      switch (relasi) {
        case _ChannelRelasi.sama:
          coChannelCount++;
          interferenceLinearMw += _dbmKeLinear(ap.rssiDbm);
          break;
        case _ChannelRelasi.berdekatan:
          adjChannelCount++;
          // 20 dB reduksi = faktor 1/100 dalam skala linear
          interferenceLinearMw += _dbmKeLinear(ap.rssiDbm) / 100.0;
          break;
        case _ChannelRelasi.jauh:
          break;
      }
    }

    // ── Konversi interferensi ke dBm dengan clamping ──────────────
    // Batas atas -70 dBm (realistis untuk interferensi agregat).
    // Batas bawah noiseDbm - 10 dBm (tidak lebih kecil dari noise).
    final double interferenceDbm;
    if (interferenceLinearMw <= 0) {
      interferenceDbm = noiseDbm - 10.0;
    } else {
      final double rawDbm = _linearKeDbm(interferenceLinearMw);
      interferenceDbm = rawDbm.clamp(noiseDbm - 10.0, -70.0);
    }

    // ── Hitung SINR (domain linear) ───────────────────────────────
    final double pSignal = _dbmKeLinear(signalPowerDbm);
    final double pInterf = _dbmKeLinear(interferenceDbm);
    final double pNoise  = _dbmKeLinear(noiseDbm);
    final double denom   = pInterf + pNoise;

    if (denom <= 0.0 || pSignal <= 0.0) {
      return SINREstimate(
        sinrDb:          null,
        noiseDbm:        noiseDbm,
        interferenceDbm: interferenceDbm,
        coChannelCount:  coChannelCount,
        adjChannelCount: adjChannelCount,
        metode:          'error_denominator_zero',
      );
    }

    final double sinrDb = 10.0 * log(pSignal / denom) / ln10;

    return SINREstimate(
      sinrDb:          sinrDb,
      noiseDbm:        noiseDbm,
      interferenceDbm: interferenceDbm,
      coChannelCount:  coChannelCount,
      adjChannelCount: adjChannelCount,
      metode: neighborAPs.isEmpty ? 'dinamis_tanpa_tetangga' : 'dinamis',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // LABEL KUALITAS
  // ══════════════════════════════════════════════════════════════

  /// Label kualitas SINR (IEEE 802.11-2020 Table 17-17)
  static String sinrKeLabel(double sinrDb) {
    if (sinrDb >= 25) return 'Excellent';
    if (sinrDb >= 15) return 'Good';
    if (sinrDb >= 10) return 'Fair';
    if (sinrDb >= 0)  return 'Poor';
    return 'Unusable';
  }

  /// Label kualitas RSSI (Metageek Wi-Fi Signal Strength, 2021)
  static String rssiKeLabel(double rssiDbm) {
    if (rssiDbm >= -50) return 'Excellent';
    if (rssiDbm >= -60) return 'Good';
    if (rssiDbm >= -70) return 'Fair';
    if (rssiDbm >= -80) return 'Poor';
    return 'Unusable';
  }

  // ── Internal helpers ──────────────────────────────────────────

  static double _dbmKeLinear(double dbm) =>
      pow(10.0, dbm / 10.0).toDouble();

  static double _linearKeDbm(double mw) {
    if (mw <= 0) return -120.0;
    return 10.0 * log(mw) / ln10;
  }

  static _ChannelRelasi _cekRelasiChannel({
    required int  currentMhz,
    required int  neighborMhz,
    required bool is5GHz,
  }) {
    final int diff = (currentMhz - neighborMhz).abs();
    if (is5GHz) {
      if (diff == 0)  return _ChannelRelasi.sama;
      if (diff <= 20) return _ChannelRelasi.berdekatan;
      return _ChannelRelasi.jauh;
    } else {
      if (diff == 0)  return _ChannelRelasi.sama;
      if (diff < 25)  return _ChannelRelasi.berdekatan;
      return _ChannelRelasi.jauh;
    }
  }
}


// ════════════════════════════════════════════════════════════════════
// NeighborAP — (import dari network_service.dart di project nyata)
// ════════════════════════════════════════════════════════════════════
class NeighborAP {
  final String bssid;
  final int    frequencyMhz;
  final double rssiDbm;

  const NeighborAP({
    required this.bssid,
    required this.frequencyMhz,
    required this.rssiDbm,
  });
}


// ════════════════════════════════════════════════════════════════════
// SINREstimate — hasil estimasi + metadata debug
// ════════════════════════════════════════════════════════════════════
class SINREstimate {
  final double? sinrDb;
  final double  noiseDbm;
  final double? interferenceDbm;
  final int     coChannelCount;
  final int     adjChannelCount;
  final String  metode;

  const SINREstimate({
    required this.sinrDb,
    required this.noiseDbm,
    required this.interferenceDbm,
    required this.coChannelCount,
    required this.adjChannelCount,
    required this.metode,
  });

  bool   get isValid => sinrDb != null;
  String get label   => sinrDb != null
      ? QoSCalculator.sinrKeLabel(sinrDb!)
      : 'N/A';

  @override
  String toString() =>
      'SINREstimate('
      'sinr=${sinrDb?.toStringAsFixed(2)} dB | '
      'noise=$noiseDbm dBm | '
      'interf=${interferenceDbm?.toStringAsFixed(1)} dBm | '
      'coCh=$coChannelCount | adjCh=$adjChannelCount | '
      'metode=$metode)';
}

enum _ChannelRelasi { sama, berdekatan, jauh }