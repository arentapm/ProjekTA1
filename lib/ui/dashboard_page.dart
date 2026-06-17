import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../models/data_qos.dart';
import '../services/qos_foreground_service.dart';
import '../services/network_service.dart';
import 'status.dart';
import 'monitoring_page.dart';
import 'stability.dart';
import '../qos/MonitoringController.dart';

const _primary    = Color(0xFF185FA5);
const _colorGreen = Color(0xFF3B6D11);
const _colorRed   = Color(0xFFA32D2D);
const _bgPage     = Color(0xFFF2F4F8);
const _textSec    = Color(0xFF6B7280);

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {

  DataQoS?              _latestQoS;
  double?               _prediction;
  Map<String, dynamic>? _evalMetrics;
  int                   _mlBufferLength     = 0;
  int                   _exportBufferLength = 0;
  String? _ssid;
  String? _ip;
  String? _band;

  final List<DataQoS> _localHistory = [];
  static const int _maxLocalHistory = 150;

  double?                    _forecastPrediction;
  List<double>               _forecastSeries      = [];
  List<Map<String, dynamic>> _forecastIntervals   = [];
  List<String>               _forecastTimeLabels  = [];
  String?                    _forecastModelName;
  DateTime?                  _forecastTime;
  String?                    _forecastError;
  DateTime?                  _forecastNextAt;

  bool _isMonitoring  = false;
  int  _selectedIndex = 0;

  WiFiSnapshot? _wiFiSnapshot;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onDataReceived);
    _checkServiceRunning();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onDataReceived);
    super.dispose();
  }

  Future<void> _checkServiceRunning() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (running && mounted) setState(() => _isMonitoring = true);
  }

  void _onDataReceived(Object data) {
    if (!mounted || data is! Map) return;
    final map     = Map<String, dynamic>.from(data);
    final hasData = map['hasData'] as bool? ?? false;
    if (!hasData) return;

    MonitoringController().updateFromServiceData(map);

    final qos = DataQoS(
      timestamp:  DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      throughput: (map['throughput'] as num?)?.toDouble() ?? 0.0,
      delay:      (map['delay']      as num?)?.toDouble() ?? 0.0,
      jitter:     (map['jitter']     as num?)?.toDouble() ?? 0.0,
      sinr:       (map['sinr']       as num?)?.toDouble() ?? 0.0,
    );

    setState(() {
      _latestQoS          = qos;
      _mlBufferLength     = (map['mlLen']     as int?) ?? 0;
      _exportBufferLength = (map['exportLen'] as int?) ?? 0;
      _ssid = map['ssid'] as String?;
      _ip   = map['ip']   as String?;
      _band = map['band'] as String?;

      _wiFiSnapshot = WiFiSnapshot(
        ssid:           map['ssid']          as String?  ?? '-',
        bssid:          map['bssid']         as String?  ?? '-',
        ip:             map['ip']            as String?  ?? '-',
        band:           map['band']          as String?  ?? '-',
        signalPowerDbm: (map['signalPower']  as num?)?.toDouble() ?? -100.0,
        frequencyMhz:   (map['frequency']   as num?)?.toInt(),
        is5GHz:         map['is5GHz']        as bool?    ?? false,
        sinrDb:         (map['sinr']         as num?)?.toDouble() ?? 0.0,
        neighborAPs:    [],
      );

      if (map['prediction'] != null) {
        _prediction  = (map['prediction'] as num?)?.toDouble();
        _evalMetrics = map['evaluation'] as Map<String, dynamic>?;
      }

      if (_localHistory.length >= _maxLocalHistory) _localHistory.removeAt(0);
      _localHistory.add(qos);
    });
  }

  void _onForecastResult({
    required double?                    prediction,
    required List<double>               series,
    required List<Map<String, dynamic>> intervals,
    required List<String>               timeLabels,
    required String?                    modelName,
    required DateTime?                  forecastTime,
    required DateTime?                  nextForecastAt,
    required String?                    error,
  }) {
    setState(() {
      _forecastPrediction = prediction;
      _forecastSeries     = series;
      _forecastIntervals  = intervals;
      _forecastTimeLabels = timeLabels;
      _forecastModelName  = modelName;
      _forecastTime       = forecastTime;
      _forecastNextAt     = nextForecastAt; 
      _forecastError      = error;
    });
  }

  Future<void> _startMonitoring() async {
    if (_isMonitoring) return;

    // ✅ FIX UTAMA: Request SEMUA permission di foreground (UI)
    // SEBELUM service background distart.
    //
    // Alasan: permission_handler butuh Android Activity untuk
    // menampilkan dialog. Background isolate tidak punya Activity
    // → PlatformException jika requestPermission dipanggil di sana.
    //
    // Urutan wajib:
    //   1. requestPermission() ← di sini (ada Activity)
    //   2. startService()      ← setelah permission granted
    //   3. onStart() di TaskHandler ← TIDAK boleh request permission

    // Request notification permission
    await FlutterForegroundTask.requestNotificationPermission();

    // Request location permission (untuk WiFi scan, SSID, BSSID)
    await NetworkService.requestPermission();

    // Cek apakah permission sudah granted
    final hasPermission = await NetworkService.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Izin lokasi diperlukan untuk membaca informasi WiFi. '
            'Aktifkan di Settings.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Inisialisasi foreground task
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'qos_monitoring_channel',
        channelName: 'Network QoS Monitoring',
        channelDescription: 'Monitoring jaringan berjalan di latar belakang',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // Start service — permission sudah granted di atas
    final result = await FlutterForegroundTask.startService(
      serviceId: 100,
      notificationTitle: 'QoS Monitoring Aktif',
      notificationText:  'Mengumpulkan data jaringan...',
      callback: startCallback,
    );

    if (result is! ServiceRequestSuccess) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memulai monitoring: $result')),
      );
      return;
    }

    setState(() => _isMonitoring = true);
  }

  Future<void> _stopMonitoring() async {
    if (!_isMonitoring) return;
    await FlutterForegroundTask.stopService();
    if (!mounted) return;
    setState(() {
      _isMonitoring       = false;
      _latestQoS          = null;
      _prediction         = null;
      _evalMetrics        = null;
      _mlBufferLength     = 0;
      _exportBufferLength = 0;
      _selectedIndex      = 0;
      _localHistory.clear();
      _forecastPrediction = null;
      _forecastSeries     = [];
      _forecastIntervals  = [];
      _forecastTimeLabels = [];
      _forecastModelName  = null;
      _forecastTime       = null;
      _forecastError      = null;
      _forecastNextAt = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Monitoring dihentikan')),
    );
  }

  void _onItemTapped(int index) {
    if (!_isMonitoring && index != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aktifkan monitoring terlebih dahulu'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final historySnapshot   = List<DataQoS>.unmodifiable(_localHistory);
    final double? currentQoSIndex = _latestQoS != null
        ? MonitoringController().calculateQoSIndex(_latestQoS!)
        : null;

    final pages = [
      _dashboardContent(currentQoSIndex),
      !_isMonitoring
          ? _placeholderPage('Monitoring belum aktif')
          : MonitoringPage(
              data:         _latestQoS,
              isMonitoring: _isMonitoring,
              qosHistory:   historySnapshot,
              wiFiSnapshot: _wiFiSnapshot,
            ),
      !_isMonitoring || _latestQoS == null
          ? _placeholderPage('Belum ada data prediksi')
          : StabilityPage(
              qos:               _latestQoS!,
              qosHistory:        historySnapshot,
              savedPrediction:   _forecastPrediction,
              savedSeries:       _forecastSeries,
              savedIntervals:    _forecastIntervals,
              savedTimeLabels:   _forecastTimeLabels,
              savedModelName:    _forecastModelName,
              savedForecastTime: _forecastTime,
              savedNextForecastAt: _forecastNextAt,
              savedError:        _forecastError,
              onForecastResult:  _onForecastResult,
            ),
      !_isMonitoring
          ? _placeholderPage('Monitoring belum aktif')
          : SystemStatusPage(exportBuffer: historySnapshot),
    ];

    return Scaffold(
      backgroundColor: _bgPage,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F1FB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.wifi_rounded, color: _primary, size: 17),
            ),
            const SizedBox(width: 10),
            const Text(
              'QoS Monitoring WiFi',
              style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap:        _onItemTapped,
          type:                  BottomNavigationBarType.fixed,
          backgroundColor:       Colors.transparent,
          elevation:             0,
          selectedItemColor:     _primary,
          unselectedItemColor:   Colors.grey.shade400,
          selectedLabelStyle:    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle:  const TextStyle(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.wifi_outlined),
              activeIcon: Icon(Icons.wifi_rounded),
              label: 'Monitoring',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.speed_outlined),
              activeIcon: Icon(Icons.speed_rounded),
              label: 'Stability',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.info_outline_rounded),
              activeIcon: Icon(Icons.info_rounded),
              label: 'Status',
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // DASHBOARD CONTENT
  // ══════════════════════════════════════════════════════════════════

  Widget _dashboardContent(double? currentQoSIndex) {
    return Container(
      color: _bgPage,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'QoS Monitor',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Traffic WiFi — Real-time',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                _statusBadge(),
              ],
            ),
            const SizedBox(height: 20),
            _monitorCard(),
            const SizedBox(height: 16),

            if (_isMonitoring && currentQoSIndex != null) ...[
              _qosIndexCard(currentQoSIndex),
              const SizedBox(height: 16),
            ],

            if (_isMonitoring && _latestQoS != null) ...[
              _infoCard(),
              const SizedBox(height: 16),
              _sectionLabel('PARAMETER QoS — TIPHON'),
              const SizedBox(height: 10),
              _parameterGrid(_latestQoS!),
            ] else if (_isMonitoring && _latestQoS == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(strokeWidth: 2),
                      SizedBox(height: 12),
                      Text('Mengumpulkan data...', style: TextStyle(fontSize: 12, color: _textSec)),
                    ],
                  ),
                ),
              )
            else
              _warningCard(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // QoS INDEX CARD
  // ══════════════════════════════════════════════════════════════════

  Widget _qosIndexCard(double index) {
    final status = _qosStatus(index);
    final color  = _qosColor(index);
    final bg     = _qosBg(index);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1), blurRadius: 16,
            spreadRadius: -4, offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.speed_rounded, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              const Text(
                'INDEKS QoS SAAT INI',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: _textSec, letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  status,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                index.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 48, fontWeight: FontWeight.w900,
                  color: color, height: 0.95,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Text(
                  '/ 100',
                  style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade400, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (_forecastPrediction != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Prediksi +30 mnt',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          _forecastPrediction! >= index
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          size: 14,
                          color: _forecastPrediction! >= index ? _colorGreen : _colorRed,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _forecastPrediction!.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800,
                            color: _forecastPrediction! >= index ? _colorGreen : _colorRed,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value:           (index / 100).clamp(0.0, 1.0),
              minHeight:       8,
              backgroundColor: Colors.grey.shade100,
              valueColor:      AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _zoneDot(const Color(0xFFFF3D00), '0–39'),
              const SizedBox(width: 8),
              _zoneDot(const Color(0xFFFFB300), '40–59'),
              const SizedBox(width: 8),
              _zoneDot(_primary, '60–79'),
              const SizedBox(width: 8),
              _zoneDot(const Color(0xFF00C853), '80–100'),
              const Spacer(),
              if (_forecastPrediction == null)
                GestureDetector(
                  onTap: () => _onItemTapped(2),
                  child: Row(
                    children: [
                      Text(
                        'Run prediksi',
                        style: TextStyle(fontSize: 10, color: _primary, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: _primary),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _zoneDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
      ],
    );
  }

  String _qosStatus(double v) {
    if (v >= 80) return 'SANGAT BAIK';
    if (v >= 60) return 'BAIK';
    if (v >= 40) return 'SEDANG';
    return 'BURUK';
  }

  Color _qosColor(double v) {
    if (v >= 80) return const Color(0xFF00C853);
    if (v >= 60) return _primary;
    if (v >= 40) return const Color(0xFFFFB300);
    return const Color(0xFFFF3D00);
  }

  Color _qosBg(double v) {
    if (v >= 80) return const Color(0x1A00C853);
    if (v >= 60) return const Color(0x1A185FA5);
    if (v >= 40) return const Color(0x1AFFB300);
    return const Color(0x1AFF3D00);
  }

  // ══════════════════════════════════════════════════════════════════
  // PARAMETER GRID
  // ══════════════════════════════════════════════════════════════════

  Widget _parameterGrid(DataQoS current) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.25,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _paramCard('Throughput', current.throughput.toStringAsFixed(2), 'Mbps',
            Icons.speed_rounded, _kategori('throughput', current.throughput)),
        _paramCard('Delay', current.delay.toStringAsFixed(2), 'ms',
            Icons.timer_outlined, _kategori('delay', current.delay)),
        _paramCard('Jitter', current.jitter.toStringAsFixed(2), 'ms',
            Icons.show_chart_rounded, _kategori('jitter', current.jitter)),
        _paramCard('SINR', current.sinr.toStringAsFixed(2), 'dB',
            Icons.signal_cellular_alt_rounded, _kategori('sinr', current.sinr)),
      ],
    );
  }

  String _kategori(String param, double v) {
    switch (param) {
      case 'throughput':
        if (v > 10) return 'Sangat Baik';
        if (v > 5)  return 'Baik';
        if (v > 1)  return 'Sedang';
        return 'Buruk';
      case 'delay':
        if (v == 0)  return 'Tidak Ada Data';
        if (v < 150) return 'Sangat Baik';
        if (v < 300) return 'Baik';
        if (v < 450) return 'Sedang';
        return 'Buruk';
      case 'jitter':
        if (v == 0)  return 'Tidak Ada Data';
        if (v < 75)  return 'Sangat Baik';
        if (v < 125) return 'Baik';
        if (v < 225) return 'Sedang';
        return 'Buruk';
      case 'sinr':
        if (v >= 25) return 'Sangat Baik';
        if (v >= 15) return 'Baik';
        if (v >= 10) return 'Sedang';
        return 'Buruk';
      default:
        return 'Baik';
    }
  }

  Color _kategoriColor(String k) {
    switch (k) {
      case 'Sangat Baik':    return _colorGreen;
      case 'Baik':           return _primary;
      case 'Sedang':         return const Color(0xFF854F0B);
      case 'Buruk':          return _colorRed;
      case 'Tidak Ada Data': return Colors.grey;
      default:               return Colors.grey;
    }
  }

  Color _kategoriBg(String k) {
    switch (k) {
      case 'Sangat Baik':    return const Color(0xFFEAF3DE);
      case 'Baik':           return const Color(0xFFE6F1FB);
      case 'Sedang':         return const Color(0xFFFAEEDA);
      case 'Buruk':          return const Color(0xFFFCEBEB);
      case 'Tidak Ada Data': return Colors.grey.shade100;
      default:               return Colors.grey.shade100;
    }
  }

  double _kategoriProgress(String k) {
    switch (k) {
      case 'Sangat Baik': return 1.0;
      case 'Baik':        return 0.75;
      case 'Sedang':      return 0.5;
      case 'Buruk':       return 0.25;
      default:            return 0.0;
    }
  }

  Widget _paramCard(String title, String value, String unit, IconData icon, String kategori) {
    final color    = _kategoriColor(kategori);
    final bgColor  = _kategoriBg(kategori);
    final progress = _kategoriProgress(kategori);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 15),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  kategori,
                  style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 11, color: _textSec)),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: color),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(fontSize: 10, color: _textSec, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value:           progress,
            minHeight:       4,
            borderRadius:    BorderRadius.circular(10),
            backgroundColor: Colors.grey.shade200,
            color:           color,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // WIDGET LAIN
  // ══════════════════════════════════════════════════════════════════

  Widget _statusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isMonitoring ? const Color(0xFFEAF3DE) : const Color(0xFFFCEBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isMonitoring ? _colorGreen.withOpacity(0.3) : _colorRed.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: _isMonitoring ? _colorGreen : _colorRed),
          const SizedBox(width: 6),
          Text(
            _isMonitoring ? 'Aktif' : 'Tidak Aktif',
            style: TextStyle(
              color: _isMonitoring ? _colorGreen : _colorRed,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _monitorCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _isMonitoring ? const Color(0xFFEAF3DE) : const Color(0xFFE6F1FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isMonitoring ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                  color: _isMonitoring ? _colorGreen : _primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status Monitoring',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    Text(
                      _isMonitoring ? 'Mengambil data tiap 1 detik' : 'Tekan tombol untuk memulai',
                      style: const TextStyle(fontSize: 11, color: _textSec),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isMonitoring ? _stopMonitoring : _startMonitoring,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isMonitoring ? _colorRed : _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(
                _isMonitoring ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded,
                size: 18,
              ),
              label: Text(
                _isMonitoring ? 'Stop Monitoring' : 'Aktifkan Monitoring',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    final ts        = _latestQoS!.timestamp.toString();
    final tsDisplay = ts.length >= 19 ? ts.substring(0, 19) : ts;
    final mlProgress = (_mlBufferLength / 1800).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: const Color(0xFFE6F1FB), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.wifi_rounded, color: _primary, size: 16),
              ),
              const SizedBox(width: 10),
              const Text(
                'INFORMASI SESI',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _primary, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow(Icons.access_time_rounded, 'Update terakhir', tsDisplay),
          const SizedBox(height: 8),
          _infoRow(Icons.wifi_rounded, 'SSID', _ssid ?? '-'),
          const SizedBox(height: 8),
          _infoRow(Icons.language_rounded, 'IP Address', _ip ?? '-'),
          const SizedBox(height: 8),
          _infoRow(Icons.network_cell_rounded, 'Band', _band ?? '-'),
          const SizedBox(height: 8),
          _infoRow(Icons.storage_rounded, 'Total data sesi', '$_exportBufferLength sampel'),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              const Text('Buffer ML', style: TextStyle(fontSize: 12, color: _textSec)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$_mlBufferLength / 1800',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value:           mlProgress,
                      minHeight:       3,
                      borderRadius:    BorderRadius.circular(4),
                      backgroundColor: Colors.grey.shade200,
                      color: mlProgress >= 1.0 ? _colorGreen : _primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Text('$label  ', style: const TextStyle(fontSize: 12, color: _textSec)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _warningCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFAEEDA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline_rounded, color: Color(0xFF854F0B), size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Monitoring belum aktif.\nSilakan aktifkan monitoring untuk membaca parameter QoS jaringan WiFi.',
              style: TextStyle(fontSize: 13, color: _textSec, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textSec, letterSpacing: 0.5),
    );
  }

  Widget _placeholderPage(String message) {
    return Container(
      color: _bgPage,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.sensors_off_rounded, color: Colors.grey.shade400, size: 28),
            ),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// PULSE DOT
// ══════════════════════════════════════════════════════════════════

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(0.5 + _ctrl.value * 0.5),
        ),
      ),
    );
  }
}