import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/data_qos.dart';
import '../qos/MonitoringController.dart';

// ════════════════════════════════════════════════════════════════════
// DBHelper
//
// Tabel aktif (v4):
//   - data_qos     : metrik QoS utama (id, timestamp, throughput, delay, jitter, sinr)
//   - forecast_qos : hasil prediksi + evaluasi aktual (actual_qos, mae)
// ════════════════════════════════════════════════════════════════════
class DBHelper {
  static Database? _db;

  static const int _dbVersion = 4;
  static const bool _isDevMode = false;

  // ── Get database ──────────────────────────────────────────────
  static Future<Database> get database async {
    _db ??= await _initDB();
    return _db!;
  }

  // ── Init ──────────────────────────────────────────────────────
  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, 'qos_monitoring.db');

    print('📁 DB PATH: $path');

    if (_isDevMode) {
      print('⚠️ DEV MODE: RESET DATABASE');
      await deleteDatabase(path);
    }

    return await openDatabase(
      path,
      version: _dbVersion,

      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },

      onCreate: (db, version) async {
        print('✅ DB CREATED (v$version)');
        await _createTables(db);
      },

      onUpgrade: (db, oldVersion, newVersion) async {
        print('🔄 MIGRATION: $oldVersion → $newVersion');
        await _migrate(db, oldVersion, newVersion);
      },
    );
  }

  // ── Create tables (fresh install — hanya tabel aktif) ─────────
  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE data_qos (
        id_qos     INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp  DATETIME NOT NULL,
        throughput FLOAT,
        delay      FLOAT,
        jitter     FLOAT,
        sinr       FLOAT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qos_ts ON data_qos(timestamp DESC)',
    );

    await db.execute('''
      CREATE TABLE forecast_qos (
        id_forecast     INTEGER PRIMARY KEY AUTOINCREMENT,
        forecast_time   DATETIME NOT NULL,
        predicted_qos   REAL     NOT NULL,
        horizon_minutes INTEGER  NOT NULL,
        model_name      TEXT,
        created_at      DATETIME NOT NULL,
        actual_qos      REAL,
        mae             REAL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_forecast_time ON forecast_qos(forecast_time ASC)',
    );

    print('✅ Tables created (v4 schema)');
  }

  // ════════════════════════════════════════════════════════════════
  // MIGRATION SYSTEM
  // ════════════════════════════════════════════════════════════════
  static Future<void> _migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (int v = oldVersion + 1; v <= newVersion; v++) {
      switch (v) {

        // ── v2: tambah kolom packet_loss (sudah jalan, jangan diubah) ──
        case 2:
          print('➡️ Migration v2');
          await db.execute(
            'ALTER TABLE data_qos ADD COLUMN packet_loss FLOAT',
          );
          break;

        // ── v3: buat tabel forecast_qos (sudah jalan, jangan diubah) ──
        case 3:
          print('➡️ Migration v3');
          await db.execute('''
            CREATE TABLE forecast_qos (
              id_forecast     INTEGER PRIMARY KEY AUTOINCREMENT,
              forecast_time   DATETIME NOT NULL,
              predicted_qos   REAL     NOT NULL,
              horizon_minutes INTEGER  NOT NULL,
              model_name      TEXT,
              created_at      DATETIME NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_forecast_time ON forecast_qos(forecast_time ASC)',
          );
          break;

        // ── v4: bersihkan skema + tambah evaluasi model ──────────────
        case 4:
          print('➡️ Migration v4');

          // 1. Restrukturisasi data_qos — hapus kolom packet_loss
          //    SQLite tidak support DROP COLUMN, jadi: copy → drop → rename
          await db.execute('''
            CREATE TABLE data_qos_new (
              id_qos     INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp  DATETIME NOT NULL,
              throughput FLOAT,
              delay      FLOAT,
              jitter     FLOAT,
              sinr       FLOAT
            )
          ''');
          await db.execute('''
            INSERT INTO data_qos_new (id_qos, timestamp, throughput, delay, jitter, sinr)
            SELECT id_qos, timestamp, throughput, delay, jitter, sinr
            FROM data_qos
          ''');
          await db.execute('DROP TABLE data_qos');
          await db.execute('ALTER TABLE data_qos_new RENAME TO data_qos');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_qos_ts ON data_qos(timestamp DESC)',
          );
          print('✅ data_qos: kolom packet_loss dihapus, 53k rows aman');

          // 2. Tambah kolom evaluasi ke forecast_qos
          await db.execute(
            'ALTER TABLE forecast_qos ADD COLUMN actual_qos REAL',
          );
          await db.execute(
            'ALTER TABLE forecast_qos ADD COLUMN mae REAL',
          );
          print('✅ forecast_qos: kolom actual_qos & mae ditambahkan');

          // 3. Hapus tabel yang tidak dipakai
          await db.execute('DROP TABLE IF EXISTS model_prediksi_qos');
          await db.execute('DROP TABLE IF EXISTS qos_stability_index');
          await db.execute('DROP TABLE IF EXISTS status_sistem');
          print('✅ Tabel tidak terpakai dihapus');

          print('✅ Migration v4 selesai');
          break;
      }
    }
  }

  // =========================================================
  // INSERT QOS
  // Setelah insert, langsung evaluasi forecast yang sudah jatuh tempo
  // =========================================================
  static Future<int> insertQoS(Map<String, dynamic> data) async {
    final db = await database;
    data['timestamp'] ??= DateTime.now().toIso8601String();
    final id = await db.insert('data_qos', data);
    // Evaluasi forecast yang sudah jatuh tempo setiap kali data baru masuk
    await evaluatePendingForecasts();
    return id;
  }

  // =========================================================
  // GET HISTORY ASC — untuk forecasting
  // =========================================================
  static Future<List<Map<String, dynamic>>> getQoSHistoryAsc() async {
  final db   = await database;
  final rows = await db.query(
    'data_qos',
    orderBy: 'timestamp ASC',
    // TIDAK ada limit — kirim semua data
  );
  print('📊 HISTORY ASC: ${rows.length} rows → dikirim ke backend');
  return rows;
}

  // =========================================================
  // GET HISTORY DAYS
  // =========================================================
  static Future<List<DataQoS>> getHistory({int days = 7}) async {
    final db     = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
    final rows = await db.query(
      'data_qos',
      where:     'timestamp >= ?',
      whereArgs: [cutoff],
      orderBy:   'timestamp ASC',
    );
    return rows.map(DataQoS.fromMap).toList();
  }

  // =========================================================
  // GET LATEST QOS
  // =========================================================
  static Future<DataQoS?> getLatest() async {
    final db   = await database;
    final rows = await db.query(
      'data_qos',
      orderBy: 'timestamp DESC',
      limit:   1,
    );
    if (rows.isEmpty) return null;
    return DataQoS.fromMap(rows.first);
  }

  // =========================================================
  // INSERT FORECAST
  // =========================================================
  static Future<int> insertForecast({
    required DateTime forecastTime,
    required double   predictedQos,
    required int      horizonMinutes,
    required String   modelName,
  }) async {
    final db = await database;
    return await db.insert('forecast_qos', {
      'forecast_time':   forecastTime.toIso8601String(),
      'predicted_qos':   predictedQos,
      'horizon_minutes': horizonMinutes,
      'model_name':      modelName,
      'created_at':      DateTime.now().toIso8601String(),
    });
  }

  // =========================================================
  // GET FORECAST HISTORY
  // =========================================================
  static Future<List<Map<String, dynamic>>> getForecastHistory({
    int limit = 200,
  }) async {
    final db = await database;
    return await db.query(
      'forecast_qos',
      orderBy: 'forecast_time ASC',
      limit:   limit,
    );
  }

  // =========================================================
  // DELETE OLD FORECAST
  // =========================================================
  static Future<void> clearOldForecast({int keepLast = 500}) async {
    final db = await database;
    await db.execute('''
      DELETE FROM forecast_qos
      WHERE id_forecast NOT IN (
        SELECT id_forecast FROM forecast_qos
        ORDER BY forecast_time DESC
        LIMIT $keepLast
      )
    ''');
  }

  // =========================================================
  // EVALUASI FORECAST — isi actual_qos & mae
  //
  // Dipanggil otomatis setiap insertQoS().
  // Cocokkan forecast_time yang sudah lewat dengan data aktual
  // dalam jendela ±10 menit. MAE = |predicted - actual|.
  // =========================================================
  static Future<void> evaluatePendingForecasts() async {
    final db = await database;

    // Ambil semua forecast yang belum dievaluasi dan forecast_time-nya sudah lewat
    final pending = await db.query(
      'forecast_qos',
      where:     'actual_qos IS NULL AND forecast_time <= ?',
      whereArgs: [DateTime.now().toIso8601String()],
    );

    if (pending.isEmpty) return;

    for (final forecast in pending) {
      final forecastTime = DateTime.parse(forecast['forecast_time'] as String);
      final windowStart  = forecastTime
          .subtract(const Duration(minutes: 10))
          .toIso8601String();
      final windowEnd    = forecastTime
          .add(const Duration(minutes: 10))
          .toIso8601String();

      // Cari data aktual dalam jendela ±10 menit
      final actuals = await db.query(
        'data_qos',
        where:     'timestamp >= ? AND timestamp <= ?',
        whereArgs: [windowStart, windowEnd],
        orderBy:   'timestamp ASC',
      );

      if (actuals.isEmpty) continue;

      // Rata-rata QoS index dari semua data aktual dalam window
      double sumQos = 0;
      int    count  = 0;
      final  ctrl   = MonitoringController();
      for (final row in actuals) {
        final qos = DataQoS.fromMap(row);
        sumQos += ctrl.calculateQoSIndex(qos);
        count++;
      }
      final actualQos  = sumQos / count;
      final predicted  = (forecast['predicted_qos'] as num).toDouble();
      final mae        = (predicted - actualQos).abs();

      await db.update(
        'forecast_qos',
        {
          'actual_qos': actualQos,
          'mae':        mae,
        },
        where:     'id_forecast = ?',
        whereArgs: [forecast['id_forecast']],
      );

      print('📊 Evaluasi #${forecast['id_forecast']}: '
            'predicted=${predicted.toStringAsFixed(2)} '
            'actual=${actualQos.toStringAsFixed(2)} '
            'mae=${mae.toStringAsFixed(2)}');
    }
  }

  // =========================================================
  // GET EVALUATED FORECASTS — untuk ditampilkan di UI
  // =========================================================
  static Future<List<Map<String, dynamic>>> getEvaluatedForecasts({
    int limit = 1000,
  }) async {
    final db = await database;
    return await db.query(
      'forecast_qos',
      where:   'actual_qos IS NOT NULL',
      orderBy: 'forecast_time DESC',
      limit:   limit,
    );
  }

  // =========================================================
  // GET AVERAGE MAE — akurasi keseluruhan model
  // =========================================================
  static Future<double?> getAverageMAE() async {
    final db     = await database;
    final result = await db.rawQuery(
      'SELECT AVG(mae) as avg_mae FROM forecast_qos WHERE mae IS NOT NULL',
    );
    if (result.isEmpty || result.first['avg_mae'] == null) return null;
    return (result.first['avg_mae'] as num).toDouble();
  }

  // =========================================================
  // DEBUG
  // =========================================================
  static Future<void> debugPrintAllQoS() async {
    final db   = await database;
    final rows = await db.query('data_qos', orderBy: 'timestamp DESC');
    print('========== DATA QOS ==========');
    for (final r in rows) print(r);
  }
}