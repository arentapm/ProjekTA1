import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/data_qos.dart';

// ════════════════════════════════════════════════════════════════════
// DBHelper — sinkronisasi dengan rancangan ERD
//
// Tabel:
//   - data_qos            : metrik QoS utama
//   - qos_stability_index : indeks stabilitas per baris QoS (1-to-many)
//   - model_prediksi_qos  : daftar model ML yang tersimpan
//   - status_sistem       : status aplikasi & monitoring (1 baris aktif)
// ════════════════════════════════════════════════════════════════════
class DBHelper {
  static Database? _db;

  static const int _dbVersion = 3;
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

  // ── Create tables ─────────────────────────────────────────────
  static Future<void> _createTables(Database db) async {
    // Tabel utama metrik QoS
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
        id_forecast INTEGER PRIMARY KEY AUTOINCREMENT,
        forecast_time DATETIME NOT NULL,
        predicted_qos REAL NOT NULL,
        horizon_minutes INTEGER NOT NULL,
        model_name TEXT,
        created_at DATETIME NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_forecast_time
      ON forecast_qos(forecast_time ASC)
    ''');

    // Tabel indeks stabilitas QoS (relasi ke data_qos)
    await db.execute('''
      CREATE TABLE qos_stability_index (
        id_qos_index    INTEGER PRIMARY KEY AUTOINCREMENT,
        id_qos          INTEGER NOT NULL,
        qos_index_value FLOAT,
        created_at      DATETIME NOT NULL,
        FOREIGN KEY (id_qos) REFERENCES data_qos(id_qos) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stability_qos ON qos_stability_index(id_qos)',
    );

    // Tabel model prediksi QoS
    await db.execute('''
      CREATE TABLE model_prediksi_qos (
        id_model     INTEGER PRIMARY KEY AUTOINCREMENT,
        model_name   VARCHAR(100) NOT NULL,
        model_status TINYINT      NOT NULL DEFAULT 0,
        created_at   DATETIME     NOT NULL
      )
    ''');

    // Tabel status sistem
    await db.execute('''
      CREATE TABLE status_sistem (
        id_status_sistem   INTEGER PRIMARY KEY AUTOINCREMENT,
        application_status VARCHAR(50),
        monitoring_status  TINYINT,
        model_status       VARCHAR(50),
        updated_at         DATETIME NOT NULL
      )
    ''');
  }
  // ════════════════════════════════════════════════════════════════
  //  MIGRATION SYSTEM
  // ════════════════════════════════════════════════════════════════
  static Future<void> _migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {

    for (int v = oldVersion + 1; v <= newVersion; v++) {

      switch (v) {

        // =====================================================
        // VERSION 2 (CONTOH PERUBAHAN)
        // =====================================================
        case 2:
          print('➡️ Applying migration v2');

          // contoh: tambah kolom baru
          await db.execute('''
            ALTER TABLE data_qos ADD COLUMN packet_loss FLOAT
          ''');

          break;

        // =====================================================
        // VERSION 3 
        // =====================================================
         case 3:

          await db.execute('''
            CREATE TABLE forecast_qos (

              id_forecast INTEGER PRIMARY KEY AUTOINCREMENT,

              forecast_time DATETIME NOT NULL,

              predicted_qos REAL NOT NULL,

              horizon_minutes INTEGER NOT NULL,

              model_name TEXT,

              created_at DATETIME NOT NULL
            )
          ''');

          await db.execute('''
            CREATE INDEX idx_forecast_time
            ON forecast_qos(forecast_time ASC)
          ''');

          break;
      }
    }
  }

  // =========================================================
  // INSERT QOS
  // =========================================================
  static Future<int> insertQoS(
    Map<String, dynamic> data,
  ) async {

    final db = await database;

    data['timestamp'] ??=
        DateTime.now().toIso8601String();

    return await db.insert(
      'data_qos',
      data,
    );
  }

  // =========================================================
  // GET HISTORY ASC
  // PENTING untuk forecasting
  // =========================================================
  static Future<List<Map<String, dynamic>>>
      getQoSHistoryAsc({
    int limit = 1000,
  }) async {

    final db = await database;

    final rows = await db.query(

      'data_qos',

      orderBy: 'timestamp ASC',

      limit: limit,
    );

    print(
      '📊 HISTORY ASC: ${rows.length} rows',
    );

    return rows;
  }

  // =========================================================
  // GET HISTORY DAYS
  // =========================================================
  static Future<List<DataQoS>>
      getHistory({
    int days = 7,
  }) async {

    final db = await database;

    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();

    final rows = await db.query(

      'data_qos',

      where: 'timestamp >= ?',

      whereArgs: [cutoff],

      orderBy: 'timestamp ASC',
    );

    return rows
        .map(DataQoS.fromMap)
        .toList();
  }

  // =========================================================
  // GET LATEST QOS
  // =========================================================
  static Future<DataQoS?> getLatest() async {

    final db = await database;

    final rows = await db.query(

      'data_qos',

      orderBy: 'timestamp DESC',

      limit: 1,
    );

    if (rows.isEmpty) return null;

    return DataQoS.fromMap(
      rows.first,
    );
  }

  // =========================================================
  // INSERT FORECAST
  // =========================================================
  static Future<int> insertForecast({

    required DateTime forecastTime,

    required double predictedQos,

    required int horizonMinutes,

    required String modelName,

  }) async {

    final db = await database;

    return await db.insert(
      'forecast_qos',
      {

        'forecast_time':
            forecastTime.toIso8601String(),

        'predicted_qos':
            predictedQos,

        'horizon_minutes':
            horizonMinutes,

        'model_name':
            modelName,

        'created_at':
            DateTime.now()
                .toIso8601String(),
      },
    );
  }

  // =========================================================
  // GET FORECAST HISTORY
  // =========================================================
  static Future<List<Map<String, dynamic>>>
      getForecastHistory({
    int limit = 200,
  }) async {

    final db = await database;

    return await db.query(

      'forecast_qos',

      orderBy: 'forecast_time ASC',

      limit: limit,
    );
  }

  // =========================================================
  // DELETE OLD FORECAST
  // =========================================================
  static Future<void> clearOldForecast({
    int keepLast = 500,
  }) async {

    final db = await database;

    await db.execute('''
      DELETE FROM forecast_qos
      WHERE id_forecast NOT IN (

        SELECT id_forecast
        FROM forecast_qos
        ORDER BY forecast_time DESC
        LIMIT $keepLast
      )
    ''');
  }

  // =========================================================
  // STATUS SISTEM
  // =========================================================
  static Future<void> upsertStatusSistem({

    required String applicationStatus,

    required int monitoringStatus,

    required String modelStatus,

  }) async {

    final db = await database;

    final rows = await db.query(
      'status_sistem',
      limit: 1,
    );

    final data = {

      'application_status':
          applicationStatus,

      'monitoring_status':
          monitoringStatus,

      'model_status':
          modelStatus,

      'updated_at':
          DateTime.now()
              .toIso8601String(),
    };

    if (rows.isEmpty) {

      await db.insert(
        'status_sistem',
        data,
      );

    } else {

      await db.update(

        'status_sistem',

        data,

        where:
            'id_status_sistem = ?',

        whereArgs: [
          rows.first['id_status_sistem']
        ],
      );
    }
  }

  // =========================================================
  // DEBUG
  // =========================================================
  static Future<void> debugPrintAllQoS() async {

    final db = await database;

    final rows = await db.query(
      'data_qos',
      orderBy: 'timestamp DESC',
    );

    print(
      '========== DATA QOS =========='
    );

    for (final r in rows) {

      print(r);
    }
  }
}