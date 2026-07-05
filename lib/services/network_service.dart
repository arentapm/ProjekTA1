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
// (permission):
//   requestPermission() = menampilkan dialog → HANYA dari UI/foreground
//   hasPermission()     = cek status saja    → AMAN dari background isolate
//
// Semua fungsi internal yang dipanggil dari background isolate
// (getWifiSnapshot, getScanNeighborAPs, getSSID, getBSSID, getIPAddress)
//
// Definisi parameter final:
//   throughput = bytes_diterima × 8 / (waktu_detik × 1.000.000) [Mbps]
//   delay      = rata-rata RTT [ms]
//   jitter     = Σ|RTT[i] - RTT[i-1]| / N [ms]
//   sinr       = 10 × log10( P_sinyal / (P_interferensi + P_noise) ) [dB]
//                model interferensi: co-channel vs adjacent-channel
//                (IEEE 802.11)
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

  // Jumlah probe per pengukuran delay/jitter
  static const int _probeCount = 4;

  // Timeout satu probe (ms)
  static const int _probeTimeoutMs = 1500;

  // ════════════════════════════════════════════════════════════════
  // PERMISSION
  //
  // ATURAN :
  //   requestPermission() → HANYA dipanggil dari UI (DashboardPage)
  //                         sebelum service background distart.
  //                         Memanggil ini dari background isolate
  //                         menyebabkan PlatformException karena
  //                         tidak ada Android Activity.
  //
  //   hasPermission()     → AMAN dipanggil dari mana saja termasuk
  //                         background isolate. Hanya membaca status,
  //                         tidak membuka dialog.
  // ════════════════════════════════════════════════════════════════

  /// Tampilkan dialog permission — HANYA dari UI/foreground.
  static Future<void> requestPermission() async {
    if (!await Permission.location.isGranted) {
      await Permission.location.request();
    }
  }

  /// Cek status permission tanpa membuka dialog.
  static Future<bool> hasPermission() async {
    return await Permission.location.isGranted;
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

  static Future<int> getRxBytes() async {
    try {
      final result = await MethodChannelHelper.trafficStats
          .invokeMethod('getRxBytes');
      final bytes = (result as int?) ?? 0;
      print('[NetworkService] getRxBytes OK: $bytes bytes');
      return bytes;
    } catch (e) {
      print('[NetworkService] getRxBytes error: $e');
      return -1;
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

  /// Hitung throughput dalam Mbps.
  /// Return null jika data belum siap (sampling pertama).
  static Future<double?> getThroughputMbps() async {
    final now = DateTime.now();
    final currentRx = await _getTotalRxBytes();

    if (_lastRxBytes == null || _lastTimestamp == null) {
      _lastRxBytes = currentRx;
      _lastTimestamp = now;
      print('[NetworkService] throughput init...');
      return null;
    }

    final deltaBytes = currentRx - _lastRxBytes!;
    final deltaTimeSec =
        now.difference(_lastTimestamp!).inMilliseconds / 1000;

    if (deltaTimeSec <= 0 || deltaBytes < 0) {
      _lastRxBytes = currentRx;
      _lastTimestamp = now;
      return null;
    }

    final throughputMbps =
        (deltaBytes * 8) / (deltaTimeSec * 1000000);

    _lastRxBytes = currentRx;
    _lastTimestamp = now;

    print('[NetworkService] throughput=${throughputMbps.toStringAsFixed(2)} Mbps');

    return throughputMbps;
  }

  // ════════════════════════════════════════════════════════════════
  // DELAY & JITTER — Active HTTP HEAD Probe
  //
  // Delay  = rata-rata RTT = Σ RTT[i] / N
  // Jitter = variasi delay = Σ |RTT[i] - RTT[i-1]| / N
  //
  // Referensi:
  //   RFC 3393 — IP Packet Delay Variation (IPDV)
  //   ITU-T Y.1541 — Network Performance Objectives for IP
  // ════════════════════════════════════════════════════════════════

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

    // Delay = rata-rata RTT
    double sumRtt = 0.0;
    for (final rtt in rtts) {
      sumRtt += rtt;
    }
    final delayMs = sumRtt / rtts.length;

    // Jitter = rata-rata variasi antar paket
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
  // SINR — Estimasi Dinamis (model IEEE 802.11: co-channel vs
  //        adjacent-channel)
  //
  // SINR (dB) = 10 × log10( P_signal / (P_interference + P_noise) )
  //   dengan semua P dalam satuan linear mW: P_mW = 10^(dBm / 10)
  //
  // Interferensi dari AP tetangga dibedakan jadi 3 kategori
  // berdasarkan jarak frekuensinya terhadap channel yang sedang
  // dipakai (currentChannelMhz):
  //   - Co-channel   (channel persis sama)        → interferensi penuh
  //   - Adjacent     (channel berdekatan)          → direduksi 20 dB
  //                                                  (filter WiFi
  //                                                  meredam sebagian)
  //   - Channel jauh (selisih > ambang)             → diabaikan
  //
  // Ambang "berdekatan": ≤20 MHz untuk 5 GHz, <25 MHz untuk 2.4 GHz
  // (mengikuti lebar channel WiFi standar).
  //
  // Referensi:
  //   Goldsmith, "Wireless Communications", Cambridge UP, 2005.
  //   IEEE 802.11-2020 Standard, Annex E.
  // ════════════════════════════════════════════════════════════════

  static double estimateSINR({
    required double           rssiDbm,
    required int?             currentChannelMhz,
    required List<NeighborAP> neighborAPs,
  }) {
    final bool is5GHzBand = (currentChannelMhz ?? 0) >= 4900;

    // Validasi RSSI sinyal sendiri
    if (rssiDbm <= -110 || rssiDbm >= 0) {
      return is5GHzBand ? 5.0 : 3.0;
    }

    // Validasi frekuensi channel
    if (currentChannelMhz == null || currentChannelMhz <= 0) {
      return is5GHzBand ? 5.0 : 3.0;
    }

    // Noise floor (karakteristik fisik, IEEE 802.11-2020 Annex E)
    final double noiseFloorDbm = is5GHzBand ? -95.0 : -92.0;

    // ── Jumlahkan interferensi, dibedakan co-channel vs adjacent ──
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
          interferenceLinearMw += _dbmToMw(ap.rssiDbm);
          break;
        case _ChannelRelasi.berdekatan:
          adjChannelCount++;
          // 20 dB reduksi = faktor 1/100 dalam skala linear
          interferenceLinearMw += _dbmToMw(ap.rssiDbm) / 100.0;
          break;
        case _ChannelRelasi.jauh:
          break;
      }
    }

    // ── Konversi interferensi ke dBm, dengan clamping ─────────────
    // Batas atas -70 dBm (realistis untuk interferensi agregat).
    // Batas bawah noiseFloorDbm - 10 dBm (tidak lebih kecil dari noise).
    final double interferenceDbm;
    if (interferenceLinearMw <= 0) {
      interferenceDbm = noiseFloorDbm - 10.0;
      print('[NetworkService] SINR: tidak ada interferensi co/adjacent-channel, '
          'pakai dasar = ${interferenceDbm.toStringAsFixed(1)} dBm');
    } else {
      final double rawDbm = _mwToDbm(interferenceLinearMw);
      interferenceDbm = rawDbm.clamp(noiseFloorDbm - 10.0, -70.0);
      print('[NetworkService] SINR: $coChannelCount co-channel, '
          '$adjChannelCount adjacent-channel, '
          'interferensi = ${interferenceDbm.toStringAsFixed(1)} dBm');
    }

    final double pSignal       = _dbmToMw(rssiDbm);
    final double pInterference = _dbmToMw(interferenceDbm);
    final double pNoise        = _dbmToMw(noiseFloorDbm);
    final double denominator   = pInterference + pNoise;

    if (denominator <= 0.0 || pSignal <= 0.0) return 0.0;

    final double sinrLinear = pSignal / denominator;
    final double sinrDb     = 10.0 * log(sinrLinear) / ln10;

    print('[NetworkService] SINR: '
        'P_s=${rssiDbm.toStringAsFixed(1)} dBm | '
        'P_i=${interferenceDbm.toStringAsFixed(1)} dBm | '
        'P_n=${noiseFloorDbm.toStringAsFixed(1)} dBm | '
        'SINR=${sinrDb.toStringAsFixed(2)} dB');

    return sinrDb;
  }

  /// Tentukan relasi channel AP tetangga terhadap channel sendiri:
  /// co-channel (sama), adjacent (berdekatan), atau jauh (diabaikan).
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
  //
  // FIX: requestPermission() DIHAPUS dari sini.
  // Fungsi ini bisa dipanggil dari background isolate via
  // getWifiSnapshot(). Memanggil requestPermission() di background
  // menyebabkan PlatformException (no Activity).
  //
  // Pengganti: cek hasPermission() → jika false, kembalikan cache.
  // requestPermission() hanya boleh dipanggil dari UI.
  // ════════════════════════════════════════════════════════════════

  static Future<List<NeighborAP>> getScanNeighborAPs({
    String? currentBssid,
  }) async {
    // Pakai cache jika belum expired
    // Android 9+ membatasi scan WiFi — maksimal 4 scan per 2 menit
    final now = DateTime.now();
    if (_lastScanTime != null &&
        now.difference(_lastScanTime!) < _scanTtl &&
        _cachedNeighborAPs.isNotEmpty) {
      print('[NetworkService] pakai cache SINR (${_cachedNeighborAPs.length} AP)');
      return _cachedNeighborAPs;
    }

    try {
      // ✅ FIX: hasPermission() bukan requestPermission()
      // Aman dipanggil dari background isolate
      if (!await hasPermission()) {
        print('[NetworkService] izin lokasi tidak ada, skip scan');
        return _cachedNeighborAPs;
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

      _cachedNeighborAPs = neighbors;
      _lastScanTime      = now;

      print('[NetworkService] scan baru: ${neighbors.length} AP tetangga');
      return neighbors;

    } catch (e) {
      print('[NetworkService] getScanNeighborAPs error: $e');
      return _cachedNeighborAPs;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // WIFI SNAPSHOT
  //
  // FIX: Fungsi ini dipanggil dari background isolate (_runPoll).
  // Semua fungsi yang dipanggil di sini tidak boleh memanggil
  // requestPermission() — sudah diperbaiki di getSSID, getBSSID,
  // getIPAddress, dan getScanNeighborAPs di bawah.
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

    // ✅ Pakai frekuensi asli (currentChannelMhz), bukan cuma flag
    // is5GHz — diperlukan untuk membedakan co-channel vs
    // adjacent-channel pada model interferensi IEEE 802.11.
    final sinr = estimateSINR(
      rssiDbm:           signalPower,
      currentChannelMhz: freq,
      neighborAPs:       neighbors,
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
  //
  // FIX: requestPermission() DIHAPUS dari getSSID, getBSSID,
  // getIPAddress — fungsi-fungsi ini bisa dipanggil dari background
  // isolate via getWifiSnapshot(). Ganti dengan hasPermission() check.
  //
  // requestPermission() tetap ada sebagai fungsi publik untuk
  // dipanggil dari UI (DashboardPage._startMonitoring).
  // ════════════════════════════════════════════════════════════════

  static Future<String> getSSID() async {
    // ✅ FIX: cek saja, tidak request
    if (!await hasPermission()) return 'Unknown';
    final ssid = await _info.getWifiName();
    return ssid?.replaceAll('"', '') ?? 'Unknown';
  }

  static Future<String> getBSSID() async {
    // ✅ FIX: cek saja, tidak request
    if (!await hasPermission()) return 'Unknown';
    final bssid = await _info.getWifiBSSID();
    return bssid ?? 'Unknown';
  }

  static Future<String> getIPAddress() async {
    // ✅ FIX: cek saja, tidak request
    if (!await hasPermission()) return '0.0.0.0';
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
// MethodChannelHelper
// ════════════════════════════════════════════════════════════════════

class MethodChannelHelper {
  static final trafficStats = MethodChannel('com.example.app/traffic_stats');
  static final wifiNative   = MethodChannel('com.example.app/wifi');
}

// ════════════════════════════════════════════════════════════════════
// _ChannelRelasi — kategori relasi channel AP tetangga vs channel
// sendiri, dipakai internal oleh estimateSINR()
// ════════════════════════════════════════════════════════════════════

enum _ChannelRelasi { sama, berdekatan, jauh }