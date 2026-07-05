import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/data_qos.dart';
import '../qos/MonitoringController.dart';

// ════════════════════════════════════════════════════════════════════
// DBHelper
//
// Tabel aktif (v5):
//   - data_qos     : metrik QoS utama
//   - forecast_qos : hasil prediksi + evaluasi aktual + interval_minutes
// ════════════════════════════════════════════════════════════════════
class DBHelper {
  static Database? _db;

  static const int _dbVersion = 5;
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
        // FIX (stuck di splash / ANR saat startup):
        // PRAGMA di bawah BISA tertahan kalau isolate lain (service
        // background yang auto-restart setelah install ulang) sedang
        // memegang lock di file DB yang sama. Dibungkus timeout supaya
        // proses buka DB TIDAK PERNAH menunggu tanpa batas — kalau gagal/
        // timeout, cukup di-skip (DB tetap bisa dipakai, cuma jalan di
        // journal mode default), bukan bikin seluruh app macet.
        try {
          await db
              .execute('PRAGMA foreign_keys = ON')
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          print('⚠️ PRAGMA foreign_keys gagal/timeout: $e');
        }

        try {
          // WAL: izinkan baca (forecast/history query) berjalan BERSAMAAN
          // dengan tulis (insert data aktual dari isolate background),
          // tanpa saling block. Default rollback-journal mode mengunci
          // seluruh file saat ada query panjang → insert data aktual
          // dari foreground service jadi tertunda/gagal (data aktual "berhenti").
          await db
              .execute('PRAGMA journal_mode=WAL')
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          print('⚠️ PRAGMA journal_mode=WAL gagal/timeout (lanjut pakai mode default): $e');
        }

        try {
          // Kalau tetap kebentur lock sesaat, retry max 3 detik sebelum
          // error, alih-alih langsung gagal (SQLITE_BUSY).
          await db
              .execute('PRAGMA busy_timeout=3000')
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          print('⚠️ PRAGMA busy_timeout gagal/timeout: $e');
        }
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

  // Schema v5: sudah include interval_minutes dari awal
  await db.execute('''
    CREATE TABLE forecast_qos (
      id_forecast      INTEGER PRIMARY KEY AUTOINCREMENT,
      forecast_time    DATETIME NOT NULL,
      predicted_qos    REAL     NOT NULL,
      horizon_minutes  INTEGER  NOT NULL,
      interval_minutes INTEGER  NOT NULL DEFAULT 30,
      model_name       TEXT,
      created_at       DATETIME NOT NULL,
      actual_qos       REAL,
      mae              REAL
    )
  ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_forecast_time ON forecast_qos(forecast_time ASC)',
  );

  print('✅ Tables created (v5 schema)');
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

          case 5:
          print('➡️ Migration v5');
          await db.execute(
            'ALTER TABLE forecast_qos ADD COLUMN interval_minutes INTEGER NOT NULL DEFAULT 30',
          );
          print('✅ forecast_qos: kolom interval_minutes ditambahkan');
          break;
      }
    }
  }

  static Future<void> debugPrintAllForecasts() async {
  final db   = await database;
  final rows = await db.query('forecast_qos', orderBy: 'created_at DESC');
  print('========== FORECAST QOS (${rows.length} rows) ==========');
  for (final r in rows) {
    print('id=${r['id_forecast']} created=${r['created_at']} '
          'target=${r['forecast_time']} pred=${r['predicted_qos']} '
          'actual=${r['actual_qos']} mae=${r['mae']}');
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
  // GET HISTORY ASC — untuk forecasting (LEGACY, tidak dipakai lagi
  // oleh runFutureForecast — lihat getQoSHistoryRecent di bawah)
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
  // GET HISTORY RECENT — N baris terakhir saja (ASC)
  //
  // FIX (#1 & #3): runFutureForecast() cuma butuh 110 baris terakhir,
  // tapi sebelumnya pakai getQoSHistoryAsc() yang menarik SELURUH
  // tabel (bisa puluhan ribu baris setelah monitoring jalan lama)
  // lalu di-slice di Dart. Itu bikin query SELECT lama -> mengunci
  // tabel data_qos lama -> insert data aktual dari background isolate
  // ikut tertahan selama proses prediksi.
  //
  // Versi ini langsung ORDER BY timestamp DESC + LIMIT di level SQL
  // (pakai index idx_qos_ts), jauh lebih cepat dan tidak menahan lock
  // lama-lama, lalu dibalik ke ASC supaya urutannya tetap kronologis
  // seperti yang dibutuhkan model.
  // =========================================================
  static Future<List<Map<String, dynamic>>> getQoSHistoryRecent({
    int limit = 110,
  }) async {
    final db   = await database;
    final rows = await db.query(
      'data_qos',
      orderBy: 'timestamp DESC',
      limit:   limit,
    );
    final asc = rows.reversed.toList();
    print('📊 HISTORY RECENT: ${asc.length}/$limit rows → dikirim ke backend');
    return asc;
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
    required int      intervalMinutes, 
    required String   modelName,
  }) async {
    final db = await database;
    return await db.insert('forecast_qos', {
      'forecast_time':   forecastTime.toIso8601String(),
      'predicted_qos':   predictedQos,
      'horizon_minutes': horizonMinutes,
      'interval_minutes': intervalMinutes,
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

  static Future<void> clearAllForecast() async {
  final db    = await database;
  final count = await db.delete('forecast_qos');
  print('🧹 forecast_qos direset total ($count baris dihapus)');
}

// =========================================================
  // GET LATEST FORECAST BATCH
  //
  // Mengambil semua baris forecast_qos dari sesi forecast TERAKHIR
  // saja (dikelompokkan berdasarkan created_at yang sama).
  // Dipakai untuk validasi MAE per-sesi, bukan rata-rata historis
  // seluruh forecast yang pernah dibuat.
  // =========================================================
 static Future<List<Map<String, dynamic>>> getLatestForecastBatch() async {
    final db = await database;

    // Ambil semua forecast, urut dari yang terbaru.
    final allDesc = await db.query(
      'forecast_qos',
      orderBy: 'created_at DESC',
    );
    if (allDesc.isEmpty) return [];

    // Gap-based grouping: mulai dari baris terbaru, lalu masukkan baris
    // berikutnya ke batch yang sama HANYA jika jaraknya dengan baris
    // sebelumnya (dalam urutan DESC) tidak lebih dari toleransi singkat.
    // Ini menghindari menarik batch forecast SEBELUMNYA yang kebetulan
    // jatuh dalam window absolut, terutama saat user menjalankan forecast
    // berkali-kali dalam jeda singkat (misal saat testing manual).
    const gapTolerance = Duration(seconds: 5);

    final batch = <Map<String, dynamic>>[allDesc.first];
    DateTime cursor = DateTime.parse(allDesc.first['created_at'] as String);

    for (int i = 1; i < allDesc.length; i++) {
      final rowTime = DateTime.parse(allDesc[i]['created_at'] as String);
      final gap = cursor.difference(rowTime); // cursor selalu >= rowTime krn DESC

      if (gap <= gapTolerance) {
        batch.add(allDesc[i]);
        cursor = rowTime;
      } else {
        // Gap terlalu jauh — baris ini (dan seterusnya) milik batch lama.
        break;
      }
    }

    batch.sort((a, b) =>
        (a['horizon_minutes'] as int).compareTo(b['horizon_minutes'] as int));
    return batch;
  }

  // =========================================================
  // GET MAE FOR LATEST BATCH
  //
  // Mengembalikan MAE rata-rata HANYA dari batch forecast terakhir,
  // dan HANYA jika seluruh titik di batch itu sudah punya actual_qos
  // (artinya sudah benar2 melewati window evaluasinya, bukan numpuk
  // dari evaluasi forecast lama).
  //
  // Return null kalau:
  //  - belum ada forecast sama sekali
  //  - batch terakhir belum ada satupun titik yang tereval
  // =========================================================
  static Future<Map<String, dynamic>?> getLatestBatchEvaluation() async {
    final batch = await getLatestForecastBatch();
    if (batch.isEmpty) return null;

    final evaluated = batch.where((f) => f['actual_qos'] != null).toList();

    if (evaluated.isEmpty) {
      // Belum ada satupun titik di batch ini yang tereval —
      // berarti masih dalam masa tunggu (< horizon pertama, 30 mnt)
      return {
        'status': 'pending',
        'totalPoints': batch.length,
        'evaluatedPoints': 0,
        'avgMae': null,
        'forecastTime': batch.first['forecast_time'],
      };
    }

    final sumMae = evaluated.fold<double>(
      0.0,
      (sum, f) => sum + (f['mae'] as num).toDouble(),
    );
    final avgMae = sumMae / evaluated.length;

    return {
      'status': evaluated.length == batch.length ? 'complete' : 'partial',
      'totalPoints': batch.length,
      'evaluatedPoints': evaluated.length,
      'avgMae': avgMae,
      'forecastTime': batch.first['forecast_time'],
    };
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
  // DEBUG
  // =========================================================
  static Future<void> debugPrintAllQoS() async {
    final db   = await database;
    final rows = await db.query('data_qos', orderBy: 'timestamp DESC');
    print('========== DATA QOS ==========');
    for (final r in rows) print(r);
  }
}