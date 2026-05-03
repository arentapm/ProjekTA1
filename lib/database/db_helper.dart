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

  static const int _dbVersion = 2;
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

    return openDatabase(
      path,
      version: 1,

      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },

      onCreate: (db, version) async {
        print('✅ DB CREATED (v$version)');
        await _createTables(db);
      },
       onUpgrade: (db, oldVersion, newVersion) async {
        print('🔄 DB UPGRADE: $oldVersion → $newVersion');
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
        // TAMBAHKAN VERSI SELANJUTNYA DI SINI
        // =====================================================
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  // DATA QOS
  // ════════════════════════════════════════════════════════════════

  /// Simpan satu baris metrik QoS. Kembalikan id_qos baru.
  static Future<int> insertQoS(Map<String, dynamic> data) async {
    final db = await database;
    data['timestamp'] ??= DateTime.now().toIso8601String();
    return db.insert('data_qos', data);
  }

  /// Ambil data [days] hari terakhir, diurutkan ASC (untuk chart).
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

    print('📊 getHistory($days hari): ${rows.length} baris');
    return rows.map(DataQoS.fromMap).toList();
  }

  /// Ambil [limit] baris terbaru, diurutkan DESC.
  static Future<List<DataQoS>> getQoSLastN({int limit = 50}) async {
    final db   = await database;
    final rows = await db.query(
      'data_qos',
      orderBy: 'timestamp DESC',
      limit:   limit,
    );
    return rows.map(DataQoS.fromMap).toList();
  }

  /// Alias dari getQoSLastN — dipakai oleh MonitoringController.fetchHistory().
  static Future<List<Map<String, dynamic>>> getQoSHistory({
    int limit = 100,
  }) async {
    final db   = await database;
    final rows = await db.query(
      'data_qos',
      orderBy: 'timestamp DESC',
      limit:   limit,
    );
    print('📊 getQoSHistory(limit=$limit): ${rows.length} baris');
    return rows;
  }

  /// Ambil 1 baris terbaru.
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

  // ════════════════════════════════════════════════════════════════
  // QOS STABILITY INDEX
  // ════════════════════════════════════════════════════════════════

  /// Simpan indeks stabilitas untuk id_qos tertentu.
  static Future<int> insertStabilityIndex({
    required int idQos,
    required double qosIndexValue,
  }) async {
    final db = await database;
    return db.insert('qos_stability_index', {
      'id_qos':          idQos,
      'qos_index_value': qosIndexValue,
      'created_at':      DateTime.now().toIso8601String(),
    });
  }

  /// Ambil semua indeks stabilitas untuk id_qos tertentu.
  static Future<List<Map<String, dynamic>>> getStabilityByQoS(int idQos) async {
    final db = await database;
    return db.query(
      'qos_stability_index',
      where:     'id_qos = ?',
      whereArgs: [idQos],
      orderBy:   'created_at DESC',
    );
  }

  /// Ambil [limit] indeks stabilitas terbaru.
  static Future<List<Map<String, dynamic>>> getLatestStability({
    int limit = 50,
  }) async {
    final db = await database;
    return db.query(
      'qos_stability_index',
      orderBy: 'created_at DESC',
      limit:   limit,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // MODEL PREDIKSI QOS
  // ════════════════════════════════════════════════════════════════

  /// Simpan model baru.
  static Future<int> insertModel({
    required String modelName,
    int modelStatus = 0,
  }) async {
    final db = await database;
    return db.insert('model_prediksi_qos', {
      'model_name':   modelName,
      'model_status': modelStatus,
      'created_at':   DateTime.now().toIso8601String(),
    });
  }

  /// Ambil semua model.
  static Future<List<Map<String, dynamic>>> getAllModels() async {
    final db = await database;
    return db.query('model_prediksi_qos', orderBy: 'created_at DESC');
  }

  /// Update status model.
  static Future<int> updateModelStatus({
    required int idModel,
    required int status,
  }) async {
    final db = await database;
    return db.update(
      'model_prediksi_qos',
      {'model_status': status},
      where:     'id_model = ?',
      whereArgs: [idModel],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // STATUS SISTEM
  // ════════════════════════════════════════════════════════════════

  /// Upsert status sistem (insert jika belum ada, update jika sudah ada).
  static Future<void> upsertStatusSistem({
    required String applicationStatus,
    required int monitoringStatus,
    required String modelStatus,
  }) async {
    final db   = await database;
    final rows = await db.query('status_sistem', limit: 1);

    final data = {
      'application_status': applicationStatus,
      'monitoring_status':  monitoringStatus,
      'model_status':       modelStatus,
      'updated_at':         DateTime.now().toIso8601String(),
    };

    if (rows.isEmpty) {
      await db.insert('status_sistem', data);
    } else {
      await db.update(
        'status_sistem',
        data,
        where:     'id_status_sistem = ?',
        whereArgs: [rows.first['id_status_sistem']],
      );
    }
  }

  /// Ambil status sistem terkini.
  static Future<Map<String, dynamic>?> getStatusSistem() async {
    final db   = await database;
    final rows = await db.query(
      'status_sistem',
      orderBy: 'updated_at DESC',
      limit:   1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ════════════════════════════════════════════════════════════════
  // DEBUG & UTILITY
  // ════════════════════════════════════════════════════════════════

  static Future<void> debugPrintAllQoS() async {
    final db   = await database;
    final rows = await db.query('data_qos', orderBy: 'id_qos DESC');
    print('========== DATA QoS (${rows.length} baris) ==========');
    for (final r in rows) {
      print(r);
    }
  }
}