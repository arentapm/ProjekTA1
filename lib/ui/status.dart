import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../models/data_qos.dart';
import '../services/export_excel.dart';
import '../database/db_helper.dart';
import '../database/session_prefs.dart';

const _primary    = Color(0xFF185FA5);
const _colorGreen = Color(0xFF3B6D11);
const _colorRed   = Color(0xFFA32D2D);
const _bgPage     = Color(0xFFF2F4F8);
const _textSec    = Color(0xFF6B7280);
const String baseUrl = "https://netpredict.cloud";

class SystemStatusPage extends StatefulWidget {
  /// exportBuffer dari MonitoringController — tidak dibatasi, akumulasi seluruh sesi.
  final List<DataQoS> exportBuffer;

  const SystemStatusPage({
    super.key,
    required this.exportBuffer,
  });

  @override
  State<SystemStatusPage> createState() => _SystemStatusPageState();
}

class _SystemStatusPageState extends State<SystemStatusPage> {

  // ── Backend connection ────────────────────────────────────────────────
  bool   _isCheckingConnection = false;
  bool?  _isConnected;
  String _responseTime         = "-";

  // ── App info ──────────────────────────────────────────────────────────
  String _appVersion   = "-";
  String _buildNumber  = "-";
  String _packageName  = "-";

  // ── Device info ───────────────────────────────────────────────────────
  String _osName      = "-";
  String _osVersion   = "-";
  String _deviceModel = "-";

  // ── Session / system stats ────────────────────────────────────────────
  final DateTime _sessionStart    = DateTime.now();
  String         _uptimeString    = "0 detik";
  DateTime?      _lastFetchTime;
  String         _lastFetchLabel  = "Belum ada";
  DateTime?      _lastExportTime;
  String         _lastExportLabel = "Belum pernah";
  int            _totalSessions   = 1;
  Timer?         _uptimeTimer;
  Timer?         _autoRefreshTimer;
  Timer?         _backendTimer;
  Timer?         _dbCountTimer; // FIX BUG#2: timer khusus refresh jumlah baris DB
  int           _totalDbRows     = 0;
  int _sessionRows     = 0;   
  int _rowsAtStart     = 0; 

  // ── Model meta ────────────────────────────────────────────────────────
  static const String _modelVersion     = "v1.0.0";
  static const String _modelLastTrained = "April 2025";
  static const String _modelFramework   = "TensorFlow / Keras";

  @override
  void initState() {
    super.initState();
    _loadPersistedData(); 
    _checkBackendConnection();
    _loadAppInfo();
    _loadDeviceInfo();
    _startUptimeTimer();
    _startAutoRefreshTimer();
    _loadTotalDbRows();
    _initDbBaseline();

    if (widget.exportBuffer.isNotEmpty) {
      _lastFetchTime  = DateTime.now();
      _lastFetchLabel = _timeAgoLabel(_lastFetchTime!);
    }
  }

  Future<void> _loadPersistedData() async {
  // 1. Last export dari SharedPreferences
  final lastExport = await SessionPrefs.loadLastExport();

  // 2. Last sync dari DB langsung — lebih akurat
  final lastSync = await _getLastSyncFromDb();

  // 3. Total sessions — increment setiap app dibuka
  final sessions = await SessionPrefs.incrementAndGetSession();

  if (mounted) {
    setState(() {
      if (lastExport != null) {
        _lastExportTime  = lastExport;
        _lastExportLabel = _timeAgoLabel(lastExport);
      }
      if (lastSync != null) {
        _lastFetchTime  = lastSync;
        _lastFetchLabel = _timeAgoLabel(lastSync);
      }
      _totalSessions = sessions;
    });
  }
}

Future<DateTime?> _getLastSyncFromDb() async {
  try {
    final db     = await DBHelper.database;
    final result = await db.rawQuery(
      'SELECT MAX(timestamp) as last_ts FROM data_qos',
    );
    final raw = result.first['last_ts'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  } catch (_) {
    return null;
  }
}

  Future<void> _loadTotalDbRows() async {
    final count = await _getDbCount();
    if (mounted) setState(() => _totalDbRows = count);
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _dbCountTimer?.cancel(); // FIX BUG#2: jangan lupa cancel timer baru
    super.dispose();
  }

  void _startUptimeTimer() {
    _updateUptime();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _updateUptime());
    });
  }

  void _updateUptime() {
    final diff = DateTime.now().difference(_sessionStart);
    if (diff.inHours > 0) {
      _uptimeString =
          "${diff.inHours}j ${diff.inMinutes.remainder(60)}m ${diff.inSeconds.remainder(60)}d";
    } else if (diff.inMinutes > 0) {
      _uptimeString = "${diff.inMinutes}m ${diff.inSeconds.remainder(60)}d";
    } else {
      _uptimeString = "${diff.inSeconds} detik";
    }
    if (_lastFetchTime != null)  _lastFetchLabel  = _timeAgoLabel(_lastFetchTime!);
    if (_lastExportTime != null) _lastExportLabel = _timeAgoLabel(_lastExportTime!);
  }

  Future<void> _initDbBaseline() async {
    final count = await _getDbCount();
    if (mounted) {
      setState(() {
        _rowsAtStart = count;
        _totalDbRows = count;
        _sessionRows = 0;
      });
    }
    print('[SystemStatus] baseline DB: $_rowsAtStart baris');
  }

  // ✅ Query COUNT dari DB
  Future<int> _getDbCount() async {
    try {
      final db     = await DBHelper.database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM data_qos',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      print('[SystemStatus] count error: $e');
      return 0;
    }
  }

   // ✅ Refresh count setiap interval
   // FIX BUG#2: fungsi ini sebelumnya tidak pernah dipanggil oleh siapa pun
   // (orphan function) — sekarang dipanggil berkala lewat _dbCountTimer
   // yang dibuat di _startAutoRefreshTimer().
  Future<void> _refreshDbCount() async {
    final count = await _getDbCount();
    if (mounted) {
      setState(() {
        _totalDbRows = count;
        // Data sesi = total sekarang dikurangi baseline awal
        _sessionRows = (_totalDbRows - _rowsAtStart).clamp(0, 999999);
      });
    }
  }

  void _startAutoRefreshTimer() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_isCheckingConnection) {
        _checkBackendConnection(silent: true);
      }
    });

    // FIX BUG#2: timer terpisah khusus untuk refresh jumlah baris DB,
    // dijalankan lebih sering (5 detik) supaya "Total Data" di kartu
    // Status Sesi & Sistem dan "Data tersedia" di Export Data Monitoring
    // sama-sama mengikuti data real-time yang masuk dari background
    // service, bukan beku di nilai awal saat halaman pertama dibuka.
    _dbCountTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshDbCount();
    });
  }

  String _timeAgoLabel(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return "${diff.inSeconds} detik lalu";
    if (diff.inMinutes < 60) return "${diff.inMinutes} menit lalu";
    if (diff.inHours < 24)   return "${diff.inHours} jam lalu";
    return "${diff.inDays} hari lalu";
  }

// Di system_status_page.dart
Future<void> _checkBackendConnection({bool silent = false}) async {
  print('=== CHECK BACKEND START ===');

  if (!silent) {
    setState(() {
      _isCheckingConnection = true;
      _isConnected = null;
    });
  }

  final stopwatch = Stopwatch()..start();

  // Coba maksimal 3x dengan jeda
  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      print('REQUEST TO: $baseUrl/ (attempt $attempt)');

      final response = await http
          .get(Uri.parse("$baseUrl/"))
          .timeout(const Duration(seconds: 60)); // naikkan ke 60 detik

      stopwatch.stop();
      print('STATUS CODE: ${response.statusCode}');

      if (mounted) {
        setState(() {
          _isConnected = response.statusCode == 200;
          _responseTime = "${stopwatch.elapsedMilliseconds} ms";
          _isCheckingConnection = false;
        });
      }
      return; // sukses, keluar dari loop

    } on TimeoutException {
      print('TIMEOUT attempt $attempt');
      if (attempt < 3) {
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }
      if (mounted) setState(() {
        _isConnected = false;
        _responseTime = "Timeout";
        _isCheckingConnection = false;
      });

    } on SocketException catch (e) {
      print('SOCKET ERROR: $e');
      if (mounted) setState(() {
        _isConnected = false;
        _responseTime = "No Connection";
        _isCheckingConnection = false;
      });
      return; // tidak perlu retry kalau memang tidak ada koneksi

    } catch (e, s) {
      print('UNKNOWN ERROR: $e\n$s');
      if (mounted) setState(() {
        _isConnected = false;
        _responseTime = "Error";
        _isCheckingConnection = false;
      });
      return;
    }
  }

  print('=== CHECK BACKEND END ===');
}

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion  = info.version;
          _buildNumber = info.buildNumber;
          _packageName = info.packageName;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        if (mounted) {
          setState(() {
            _osName      = "Android";
            _osVersion   = android.version.release;
            _deviceModel = "${android.manufacturer} ${android.model}";
          });
        }
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        if (mounted) {
          setState(() {
            _osName      = "iOS";
            _osVersion   = ios.systemVersion;
            _deviceModel = ios.utsname.machine;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final overallHealthy = _isConnected == true;
    final overallLoading = _isCheckingConnection && _isConnected == null;

    return Container(
      color: _bgPage,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(overallHealthy, overallLoading),
            const SizedBox(height: 20),

            _sectionLabel("INFORMASI APLIKASI"),
            const SizedBox(height: 10),
            _appInfoCard(),
            const SizedBox(height: 16),

            _sectionLabel("INFORMASI PERANGKAT"),
            const SizedBox(height: 10),
            _deviceInfoCard(),
            const SizedBox(height: 16),

            _sectionLabel("INFORMASI MODEL"),
            const SizedBox(height: 10),
            _modelInfoCard(),
            const SizedBox(height: 16),

            _sectionLabel("STATUS KONEKSI BACKEND"),
            const SizedBox(height: 10),
            _backendStatusCard(),
            const SizedBox(height: 16),

            _sectionLabel("STATUS SISTEM & SESI"),
            const SizedBox(height: 10),
            _systemStatusCard(),
            const SizedBox(height: 16),

            _sectionLabel("EXPORT DATA MONITORING"),
            const SizedBox(height: 10),
            _exportCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isHealthy, bool isLoading) {
    final chipColor = isLoading
        ? const Color(0xFF854F0B)
        : isHealthy ? _colorGreen : _colorRed;
    final chipBg = isLoading
        ? const Color(0xFFFAEEDA)
        : isHealthy ? const Color(0xFFEAF3DE) : const Color(0xFFFCEBEB);
    final chipLabel = isLoading ? "Mengecek..." : isHealthy ? "Online" : "Offline";
    final chipIcon  = isLoading
        ? Icons.sync_rounded
        : isHealthy ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Status Sistem",
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
            ),
            SizedBox(height: 2),
            Text("Informasi Aplikasi & Sistem",
                style: TextStyle(fontSize: 12, color: _textSec)),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: chipBg, borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(chipIcon, size: 13, color: chipColor),
              const SizedBox(width: 5),
              Text(chipLabel,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: chipColor)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _appInfoCard() {
    return _baseCard(
      icon: Icons.apps_rounded,
      title: "Informasi Aplikasi",
      subtitle: "Versi & identitas aplikasi",
      children: [
        _infoRow(Icons.tag_rounded,           "Versi",        _appVersion),
        const SizedBox(height: 10),
        _infoRow(Icons.build_rounded,         "Build Number", _buildNumber),
        const SizedBox(height: 10),
        _infoRow(Icons.label_outline_rounded, "Package Name", _packageName),
      ],
    );
  }

  Widget _deviceInfoCard() {
    return _baseCard(
      icon: Icons.phone_android_rounded,
      title: "Informasi Perangkat",
      subtitle: "Platform & sistem operasi",
      children: [
        _infoRow(Icons.devices_rounded,          "Perangkat", _deviceModel),
        const SizedBox(height: 10),
        _infoRow(Icons.android_rounded,          "OS",        _osName),
        const SizedBox(height: 10),
        _infoRow(Icons.system_update_alt_rounded,"Versi OS",  _osVersion),
      ],
    );
  }

  Widget _modelInfoCard() {
    return _baseCard(
      icon: Icons.model_training_rounded,
      title: "Model Prediksi QoS",
      subtitle: "Hybrid SSA-LSTM",
      children: [
        _infoRow(Icons.memory_rounded,     "Arsitektur",  "Hybrid SSA + LSTM"),
        const SizedBox(height: 10),
        _infoRow(Icons.psychology_rounded, "Metode",      "Singular Spectrum Analysis & LSTM"),
        const SizedBox(height: 10),
        _infoRow(Icons.timeline_rounded,   "Tipe",        "Time-Series Forecasting"),
        const SizedBox(height: 10),
        _infoRow(Icons.code_rounded,       "Framework",   _modelFramework),
        const SizedBox(height: 10),
        _infoRow(Icons.tag_rounded,        "Versi Model", _modelVersion),
        const SizedBox(height: 10),
        _infoRow(Icons.history_rounded,    "Last Trained",_modelLastTrained),
        const SizedBox(height: 10),
        _infoRow(Icons.cloud_outlined,     "Deployment",  "FastAPI REST API"),
      ],
    );
  }

  Widget _backendStatusCard() {
    final isOk      = _isConnected == true;
    final isLoading = _isCheckingConnection;
    final color   = isLoading
        ? const Color(0xFF854F0B)
        : isOk ? _colorGreen : _colorRed;
    final bgColor = isLoading
        ? const Color(0xFFFAEEDA)
        : isOk ? const Color(0xFFEAF3DE) : const Color(0xFFFCEBEB);
    final statusLabel = isLoading
        ? "Mengecek koneksi..."
        : isOk
            ? "ML Service aktif & merespons"
            : "ML Service tidak dapat dijangkau";
    final icon = isLoading
        ? Icons.sync_rounded
        : isOk ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: bgColor, borderRadius: BorderRadius.circular(12)),
                child: isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: color),
                      )
                    : Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("ML Service (FastAPI)",
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text(statusLabel,
                        style: const TextStyle(fontSize: 11, color: _textSec)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 14),
          _infoRow(Icons.link_rounded,      "Endpoint",      baseUrl),
          const SizedBox(height: 10),
          _infoRow(Icons.speed_rounded,     "Response Time", _responseTime),
          const SizedBox(height: 10),
          _infoRow(Icons.api_rounded,       "Tipe API",      "REST API (Async Job)"),
          const SizedBox(height: 10),
          _infoRow(Icons.autorenew_rounded, "Auto-refresh",  "Setiap 30 detik"),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _isCheckingConnection ? null : _checkBackendConnection,
              style: OutlinedButton.styleFrom(
                foregroundColor: _primary,
                side: BorderSide(color: _primary.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text("Cek Ulang Koneksi",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

    Widget _systemStatusCard() {
    return _baseCard(
      icon: Icons.monitor_heart_rounded,
      title: "Status Sesi & Sistem",
      subtitle: "Informasi sesi berjalan",
      children: [
        _infoRow(Icons.timer_outlined,        "Uptime Sesi", _uptimeString),
        const SizedBox(height: 10),
        // ✅ Pakai _totalDbRows — seluruh data di DB, sekarang real-time
        // berkat _dbCountTimer (FIX BUG#2)
        _infoRow(Icons.storage_rounded, "Total Data", "$_totalDbRows sampel"),
        const SizedBox(height: 10),
        _infoRow(Icons.sync_rounded,          "Last Sync",   _lastFetchLabel),
        const SizedBox(height: 10),
        _infoRow(Icons.download_done_rounded, "Last Export", _lastExportLabel),
        const SizedBox(height: 10),
        _infoRow(Icons.play_circle_outline,   "Sesi ke-",    "$_totalSessions"),
      ],
    );
  }

  Widget _exportCard(BuildContext context) {
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
                  color: const Color(0xFFE6F1FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.download_rounded,
                    color: _primary, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Export Data Monitoring",
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                    SizedBox(height: 2),
                    Text("Simpan data QoS ke file Excel",
                        style: TextStyle(fontSize: 11, color: _textSec)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: _bgPage, borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.storage_rounded,
                        size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 8),
                    const Text("Data tersedia",
                        style: TextStyle(fontSize: 12, color: _textSec)),
                    const Spacer(),
                    // ✅ FIX BUG#2: _totalDbRows sekarang ter-refresh
                    // otomatis tiap 5 detik lewat _dbCountTimer, jadi
                    // angka ini tidak lagi macet di 0.
                    Text(
                      "$_totalDbRows sampel",
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.history_rounded,
                        size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 8),
                    const Text("Terakhir export",
                        style: TextStyle(fontSize: 12, color: _textSec)),
                    const Spacer(),
                    Text(
                      _lastExportLabel,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.table_chart_rounded, size: 18),
              label: const Text("Export Excel",
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                // ✅ Tampilkan loading dialog
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const AlertDialog(
                    content: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 16),
                        Text('Mengekspor data...'),
                      ],
                    ),
                  ),
                );

                final path = await exportQoSToExcel();

                // ✅ Tutup loading dialog
                if (mounted) Navigator.of(context, rootNavigator: true).pop();

                if (path != null) {
                  final now = DateTime.now();
                  await SessionPrefs.saveLastExport(now);

                  setState(() {
                    _lastExportTime  = now;
                    _lastExportLabel = _timeAgoLabel(now);
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('File tersimpan: $path')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Export gagal')),
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _baseCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                    color: const Color(0xFFE6F1FB),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: _primary, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: _textSec)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Text("$label  ",
            style: const TextStyle(fontSize: 12, color: _textSec)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _textSec,
          letterSpacing: 0.5),
    );
  }
}