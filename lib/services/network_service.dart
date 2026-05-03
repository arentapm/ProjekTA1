import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// ════════════════════════════════════════════════════════════════════
// NetworkService — Pengukuran QoS WiFi (4 Parameter: Throughput,
//                 Delay, Jitter, SINR)
//
//
// Definisi parameter final:
//   throughput = bytes_diterima × 8 / (waktu_detik × 1.000.000) [Mbps]
//   delay      = rata-rata |RTT[i] - RTT[i-1]| [ms]
//   jitter     = Σ|RTT[i] - RTT[i-1]| / N [ms]
//   sinr       = 10 × log10( P_sinyal / (P_interferensi + P_noise) ) [dB]
// ════════════════════════════════════════════════════════════════════

class NetworkService {
  static final NetworkInfo _info = NetworkInfo();

  static DateTime? _lastScanTime;
  static List<NeighborAP> _cachedNeighborAPs = [];
  static const Duration _scanTtl = Duration(seconds: 30);

  // ── Probe host untuk delay/jitter (HTTP HEAD, ringan) ─────────
  static const List<String> _probeHosts = [
    'http://clients3.google.com/generate_204',
    'http://connectivitycheck.gstatic.com/generate_204',
    'http://1.1.1.1',
  ];

  // ── URL file untuk throughput probe (~100 KB) ─────────────────
  static const List<String> _throughputUrls = [
    'https://speed.cloudflare.com/__down?bytes=102400',
    'https://httpbin.org/bytes/102400',
  ];

  // Jumlah probe per pengukuran delay/jitter
  static const int _probeCount = 4;

  // Timeout satu probe (ms)
  static const int _probeTimeoutMs = 1500;

  // Timeout download throughput (ms)
  // static const int _throughputTimeoutMs = 15000;

  // ════════════════════════════════════════════════════════════════
  // PERMISSION
  // ════════════════════════════════════════════════════════════════

  static Future<void> requestPermission() async {
    if (!await Permission.location.isGranted) {
      await Permission.location.request();
    }
  }

  // ════════════════════════════════════════════════════════════════
  // STATUS KONEKSI
  // ════════════════════════════════════════════════════════════════

  static Future<bool> isWifiConnected() async {
    final results = await Connectivity().checkConnectivity();
    if (results is List) {
      return (results as List).contains(ConnectivityResult.wifi);
    }
    return results == ConnectivityResult.wifi;
  }

// ════════════════════════════════════════════════════════════════
// THROUGHPUT — TrafficStats (Android Native via MethodChannel)
//
// throughput = (Δbytes × 8) / (Δtime × 1_000_000)  [Mbps]
//
// Catatan:
// - Menggunakan total RX bytes (downlink)
// - Perlu 2 sampel untuk menghasilkan nilai pertama
// ════════════════════════════════════════════════════════════════

static int? _lastRxBytes;
static DateTime? _lastTimestamp;

// ════════════════════════════════════════════════════════════════
// TRAFFIC STATS (Android)
// ════════════════════════════════════════════════════════════════

static Future<int> getRxBytes() async {
  try {
    final result = await MethodChannelHelper.trafficStats
        .invokeMethod('getRxBytes');
    final bytes = (result as int?) ?? 0;
    print('[NetworkService] getRxBytes OK: $bytes bytes');
    return bytes;
  } catch (e) {
    // Hanya print error, jangan return 0 — return -1 agar bisa dibedakan
    print('[NetworkService] getRxBytes error: $e');
    return -1; // ← return -1, bukan 0, agar updateTraffic bisa deteksi error
  }
}

static Future<int> getTxBytes() async {
  try {
    final result = await MethodChannelHelper.trafficStats
        .invokeMethod('getTxBytes');
    return (result as int?) ?? 0;
  } catch (e) {
    print('[NetworkService] getTxBytes error: $e');
    return 0;
  }
}

/// Ambil total RX bytes dari Android (TrafficStats)
static Future<int> _getTotalRxBytes() async {
  try {
    final result = await MethodChannelHelper.trafficStats
        .invokeMethod('getRxBytes');
    return (result as int?) ?? 0;
  } catch (e) {
    print('[NetworkService] getRxBytes error: $e');
    return 0;
  }
}

/// Hitung throughput dalam Mbps
/// Return null jika data belum siap (sampling pertama)
static Future<double?> getThroughputMbps() async {
  final now = DateTime.now();
  final currentRx = await _getTotalRxBytes();

  // ── Sampling pertama (belum bisa hitung) ──
  if (_lastRxBytes == null || _lastTimestamp == null) {
    _lastRxBytes = currentRx;
    _lastTimestamp = now;
    print('[NetworkService] throughput init...');
    return null;
  }

  final deltaBytes = currentRx - _lastRxBytes!;
  final deltaTimeSec =
      now.difference(_lastTimestamp!).inMilliseconds / 1000;

  // Validasi
  if (deltaTimeSec <= 0 || deltaBytes < 0) {
    _lastRxBytes = currentRx;
    _lastTimestamp = now;
    return null;
  }

  final throughputMbps =
      (deltaBytes * 8) / (deltaTimeSec * 1000000);

  // Update state
  _lastRxBytes = currentRx;
  _lastTimestamp = now;

  print('[NetworkService] throughput=${throughputMbps.toStringAsFixed(2)} Mbps');

  return throughputMbps;
}


  // ════════════════════════════════════════════════════════════════
  // [2] DELAY & JITTER — Active HTTP HEAD Probe
  //
  // Definisi final (tidak ada latency/packetLoss):
  //
  // Delay  = rata-rata RTT
  //        = Σ RTT[i] / N
  //            Mengukur perubahan delay antar paket yang berurutan.
  //            Jika RTT stabil → delay rendah.
  //
  // Jitter = variasi delay antar paket
  //        = Σ |RTT[i] - RTT[i-1]| / N
  //            Normalisasi per paket (bukan per selisih).
  //            Mengukur rata-rata variasi delay per paket dikirim.
  //
  // Catatan perbedaan delay vs jitter:
  //   - Delay pakai pembagi (N-1): rata-rata atas jumlah selisih
  //   - Jitter pakai pembagi N   : rata-rata atas jumlah paket
  //   - Keduanya dihitung dari jitterSum yang sama
  //
  // Referensi:
  //   RFC 3393 — IP Packet Delay Variation (IPDV)
  //   ITU-T Y.1541 — Network Performance Objectives for IP
  // ════════════════════════════════════════════════════════════════

  /// Ukur delay dan jitter via HTTP HEAD probing.
  /// Kembalikan [ProbeResult] dengan delay dan jitter dalam ms.
// ======================= PERBAIKAN DELAY & JITTER =======================
//
// DEFINISI FINAL:
//
// Delay  = rata-rata RTT
//        = Σ RTT[i] / N
//
// Jitter = variasi delay antar paket
//        = Σ |RTT[i] - RTT[i-1]| / N
//
// =======================================================================

static Future<ProbeResult> probeDelayJitter() async {
  final rtts = <double>[];

  String? workingHost;
  for (final host in _probeHosts) {
    if (await _isHostReachable(host)) {
      workingHost = host;
      break;
    }
  }

  if (workingHost == null) {
    return ProbeResult.empty();
  }

  for (int i = 0; i < _probeCount; i++) {
    final rtt = await _singleProbe(workingHost);
    if (rtt != null) {
      rtts.add(rtt);
    }

    if (i < _probeCount - 1) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  if (rtts.length < 2) {
    return ProbeResult.empty();
  }

  // ======================= DELAY =======================
  // Delay = rata-rata RTT
  double sumRtt = 0.0;
  for (final rtt in rtts) {
    sumRtt += rtt;
  }
  final delayMs = sumRtt / rtts.length;

  // ======================= JITTER ======================
  double diffSum = 0.0;
  for (int i = 1; i < rtts.length; i++) {
    diffSum += (rtts[i] - rtts[i - 1]).abs();
  }

  final jitterMs = diffSum / rtts.length;

  print('[QoS] delay=${delayMs.toStringAsFixed(1)} ms | '
      'jitter=${jitterMs.toStringAsFixed(1)} ms | '
      'samples=${rtts.length}');

  return ProbeResult(
    delayMs: delayMs,
    jitterMs: jitterMs,
    rttSamples: rtts,
  );
}

  static Future<double?> _singleProbe(String host) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = Duration(milliseconds: _probeTimeoutMs);

      final stopwatch = Stopwatch()..start();

      final request = await client
          .headUrl(Uri.parse(host))
          .timeout(Duration(milliseconds: _probeTimeoutMs));
      request.headers.set('Connection', 'close');

      final response = await request
          .close()
          .timeout(Duration(milliseconds: _probeTimeoutMs));

      await response.drain<void>();

      stopwatch.stop();
      client.close();

      if (response.statusCode >= 200 && response.statusCode < 500) {
        return stopwatch.elapsedMilliseconds.toDouble();
      }
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _isHostReachable(String host) async {
    final rtt = await _singleProbe(host);
    return rtt != null;
  }

  // ════════════════════════════════════════════════════════════════
  // [3] SINR — Estimasi Dinamis
  //
  // Rumus SINR
  //   SINR (dB) = 10 × log10( P_signal / (P_interference + P_noise) )
  //   dengan semua P dalam satuan linear mW:
  //     P_mW = 10^(dBm / 10)
  //
  // Interferensi:
  //   - AP co-band  → dihitung dari RSSI semua AP di band yang sama
  //                   (2.4 GHz atau 5 GHz), dijumlahkan dalam linear mW
  //   - Jika tidak ada AP tetangga → pakai nilai statis per band
  //
  // Referensi:
  //   Goldsmith, "Wireless Communications", Cambridge UP, 2005.
  //   IEEE 802.11-2020 Standard, Annex E.
  // ════════════════════════════════════════════════════════════════

  /// Estimasi SINR (dB) dari RSSI dan scan AP tetangga.
  /// Menggunakan konversi linear yang benar, bukan pengurangan dBm.
  static double estimateSINR({
    required double           rssiDbm,
    required bool             is5GHz,
    required List<NeighborAP> neighborAPs,
  }) {
    // Validasi RSSI
    if (rssiDbm <= -110 || rssiDbm >= 0) {
      return is5GHz ? 5.0 : 3.0; // fallback minimal
    }

    // Noise floor (karakteristik fisik, tidak berubah)
    // 2.4 GHz: -92 dBm | 5 GHz: -95 dBm
    // Referensi: IEEE 802.11-2020 Annex E
    final double noiseFloorDbm = is5GHz ? -95.0 : -92.0;

    // ── Hitung daya interferensi dari AP tetangga ─────────────────
    // Filter AP di band yang sama → sumber interferensi nyata
    final sameBandAPs = neighborAPs.where((ap) {
      if (ap.rssiDbm <= -110 || ap.rssiDbm >= 0) return false;
      if (is5GHz) return ap.frequencyMhz >= 4900;
      return ap.frequencyMhz < 4900 && ap.frequencyMhz >= 2400;
    }).toList();

    final double interferenceDbm;

    if (sameBandAPs.isEmpty) {
      // Tidak ada data scan → fallback nilai statis
      interferenceDbm = is5GHz ? -90.0 : -85.0;
      print('[NetworkService] SINR: tidak ada AP tetangga, '
          'pakai interferensi statis = $interferenceDbm dBm');
    } else {
      // Jumlahkan daya semua AP interferensi dalam skala linear (mW)
      // P_total = Σ 10^(RSSI_i / 10)
      double totalMw = 0.0;
      for (final ap in sameBandAPs) {
        totalMw += _dbmToMw(ap.rssiDbm);
      }
      // Konversi kembali ke dBm
      interferenceDbm = _mwToDbm(totalMw);
      print('[NetworkService] SINR: ${sameBandAPs.length} AP tetangga, '
          'interferensi total = ${interferenceDbm.toStringAsFixed(1)} dBm');
    }

    // ── Hitung SINR dengan rumus yang benar (domain linear) ───────
    //
    // =konversi semua nilai ke mW dulu, baru hitung rasio, kemudian konversi hasil ke dB.
    //
    //   SINR = P_signal / (P_interference + P_noise)   [linear]
    //   SINR_dB = 10 × log10(SINR)
    //
    final double pSignal       = _dbmToMw(rssiDbm);
    final double pInterference = _dbmToMw(interferenceDbm);
    final double pNoise        = _dbmToMw(noiseFloorDbm);
    final double denominator   = pInterference + pNoise;

    if (denominator <= 0.0 || pSignal <= 0.0) {
      return 0.0;
    }

    final double sinrLinear = pSignal / denominator;
    final double sinrDb     = 10.0 * log(sinrLinear) / ln10;

    print('[NetworkService] SINR: '
        'P_s=${rssiDbm.toStringAsFixed(1)} dBm | '
        'P_i=${interferenceDbm.toStringAsFixed(1)} dBm | '
        'P_n=${noiseFloorDbm.toStringAsFixed(1)} dBm | '
        'SINR=${sinrDb.toStringAsFixed(2)} dB');

    return sinrDb;
  }

  // ── Konversi dBm ↔ mW ────────────────────────────────────────
  static double _dbmToMw(double dbm) => pow(10.0, dbm / 10.0).toDouble();
  static double _mwToDbm(double mw) {
    if (mw <= 0) return -120.0;
    return 10.0 * log(mw) / ln10;
  }

  // ════════════════════════════════════════════════════════════════
  // RSSI & FREKUENSI
  // ════════════════════════════════════════════════════════════════

  static Future<double> getSignalPower() async {
    final rssi = await WiFiForIoTPlugin.getCurrentSignalStrength();
    return rssi?.toDouble() ?? -100.0;
  }

  static Future<int?> getFrequency() async {
    try {
      return await WiFiForIoTPlugin.getFrequency();
    } catch (_) {
      return null;
    }
  }

  static bool is5GHz(int? frequency) {
    if (frequency == null) return false;
    return frequency >= 4900 && frequency <= 5900;
  }

  static String getFrequencyBand(int? frequency) {
    if (frequency == null) return 'Unknown';
    if (frequency >= 4900 && frequency <= 5900) return '5 GHz';
    if (frequency >= 2400 && frequency <= 2500) return '2.4 GHz';
    return 'Unknown';
  }

  // ════════════════════════════════════════════════════════════════
  // WIFI SCAN — AP Tetangga
  // ════════════════════════════════════════════════════════════════

 static Future<List<NeighborAP>> getScanNeighborAPs({
  String? currentBssid,
}) async {
  // ✅ FIX BUG 3: Pakai cache jika belum expired
  // Android 9+ membatasi scan WiFi — maksimal 4 scan per 2 menit
  final now = DateTime.now();
  if (_lastScanTime != null &&
      now.difference(_lastScanTime!) < _scanTtl &&
      _cachedNeighborAPs.isNotEmpty) {
    print('[NetworkService] pakai cache SINR (${_cachedNeighborAPs.length} AP)');
    return _cachedNeighborAPs;
  }

  try {
    await requestPermission();
    if (!await Permission.location.isGranted) {
      print('[NetworkService] izin lokasi ditolak');
      return _cachedNeighborAPs; // kembalikan cache lama jika ada
    }

    final List<WifiNetwork>? networks = await WiFiForIoTPlugin.loadWifiList();
    if (networks == null || networks.isEmpty) {
      return _cachedNeighborAPs;
    }

    final neighbors = <NeighborAP>[];
    for (final net in networks) {
      if (currentBssid != null &&
          net.bssid?.toLowerCase() == currentBssid.toLowerCase()) {
        continue;
      }
      final freq = net.frequency;
      final rssi = net.level;
      if (freq == null || rssi == null) continue;
      if (rssi == 0 || rssi < -110) continue;

      neighbors.add(NeighborAP(
        bssid:        net.bssid ?? 'unknown',
        frequencyMhz: freq,
        rssiDbm:      rssi.toDouble(),
      ));
    }

    // Update cache
    _cachedNeighborAPs = neighbors;
    _lastScanTime      = now;

    print('[NetworkService] scan baru: ${neighbors.length} AP tetangga');
    return neighbors;

  } catch (e) {
    print('[NetworkService] getScanNeighborAPs error: $e');
    return _cachedNeighborAPs; // fallback ke cache
  }
}

  // ════════════════════════════════════════════════════════════════
  // WIFI SNAPSHOT
  // ════════════════════════════════════════════════════════════════

  static Future<WiFiSnapshot> getWifiSnapshot() async {
    final currentBssid = await getBSSID();
    final signalPower  = await getSignalPower();
    final freq         = await getFrequency();
    final ssid         = await getSSID();
    final ip           = await getIPAddress();
    final band5g       = is5GHz(freq);

    List<NeighborAP> neighbors = [];
    try {
      neighbors = await getScanNeighborAPs(
        currentBssid: currentBssid == 'Unknown' ? null : currentBssid,
      );
    } catch (e) {
      print('[NetworkService] scan tetangga gagal: $e');
    }

    final sinr = estimateSINR(
      rssiDbm:     signalPower,
      is5GHz:      band5g,
      neighborAPs: neighbors,
    );

    return WiFiSnapshot(
      signalPowerDbm: signalPower,
      frequencyMhz:   freq,
      ssid:           ssid,
      bssid:          currentBssid,
      ip:             ip,
      neighborAPs:    neighbors,
      is5GHz:         band5g,
      band:           getFrequencyBand(freq),
      sinrDb:         sinr,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // INFO JARINGAN
  // ════════════════════════════════════════════════════════════════

  static Future<String> getSSID() async {
    await requestPermission();
    final ssid = await _info.getWifiName();
    return ssid?.replaceAll('"', '') ?? 'Unknown';
  }

  static Future<String> getBSSID() async {
    await requestPermission();
    final bssid = await _info.getWifiBSSID();
    return bssid ?? 'Unknown';
  }

  static Future<String> getIPAddress() async {
    await requestPermission();
    final ip = await _info.getWifiIP();
    return ip ?? '0.0.0.0';
  }
}


// ════════════════════════════════════════════════════════════════════
// WiFiSnapshot
// ════════════════════════════════════════════════════════════════════

class WiFiSnapshot {
  final double           signalPowerDbm;
  final int?             frequencyMhz;
  final String           ssid;
  final String           bssid;
  final String           ip;
  final List<NeighborAP> neighborAPs;
  final bool             is5GHz;
  final String           band;
  final double           sinrDb;

  const WiFiSnapshot({
    required this.signalPowerDbm,
    required this.frequencyMhz,
    required this.ssid,
    required this.bssid,
    required this.ip,
    required this.neighborAPs,
    required this.is5GHz,
    required this.band,
    required this.sinrDb,
  });

  @override
  String toString() =>
      'WiFiSnapshot(ssid=$ssid | rssi=$signalPowerDbm dBm | '
      'band=$band | sinr=${sinrDb.toStringAsFixed(1)} dB | '
      'neighbors=${neighborAPs.length})';
}


// ════════════════════════════════════════════════════════════════════
// ProbeResult — Hasil pengukuran delay & jitter
//
// Packet loss DIHAPUS sesuai spesifikasi: hanya 4 parameter QoS.
// Field:
//   delayMs    — rata-rata |RTT[i]-RTT[i-1]| / (N-1) [ms]
//   jitterMs   — Σ|RTT[i]-RTT[i-1]| / N [ms]
//   rttSamples — semua nilai RTT mentah [ms]
// ════════════════════════════════════════════════════════════════════

class ProbeResult {
  final double       delayMs;
  final double       jitterMs;
  final List<double> rttSamples;

  const ProbeResult({
    required this.delayMs,
    required this.jitterMs,
    required this.rttSamples,
  });

  factory ProbeResult.empty() => const ProbeResult(
        delayMs:    0.0,
        jitterMs:   0.0,
        rttSamples: [],
      );

  /// True jika ada sampel RTT yang berhasil diukur
  bool get isValid => rttSamples.isNotEmpty;

  @override
  String toString() =>
      'ProbeResult('
      'delay=${delayMs.toStringAsFixed(1)} ms | '
      'jitter=${jitterMs.toStringAsFixed(1)} ms | '
      'samples=${rttSamples.length})';
}


// ════════════════════════════════════════════════════════════════════
// NeighborAP
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

  @override
  String toString() =>
      'NeighborAP(bssid=$bssid | freq=$frequencyMhz MHz | rssi=$rssiDbm dBm)';
}


// ════════════════════════════════════════════════════════════════════
// MethodChannelHelper — dipertahankan untuk kompatibilitas
// ════════════════════════════════════════════════════════════════════

class MethodChannelHelper {
  static final trafficStats = MethodChannel('com.example.app/traffic_stats');
  static final wifiNative   = MethodChannel('com.example.app/wifi');
}