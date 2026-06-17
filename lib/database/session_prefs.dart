import 'package:shared_preferences/shared_preferences.dart';

class SessionPrefs {
  static const _keyLastExport   = 'last_export_time';
  static const _keyTotalSessions = 'total_sessions';

  // ── Last Export ───────────────────────────────────────
  static Future<void> saveLastExport(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastExport, time.toIso8601String());
  }

  static Future<DateTime?> loadLastExport() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_keyLastExport);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  // ── Total Sessions ────────────────────────────────────
  static Future<int> incrementAndGetSession() async {
    final prefs   = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyTotalSessions) ?? 0;
    final next    = current + 1;
    await prefs.setInt(_keyTotalSessions, next);
    return next;
  }
}