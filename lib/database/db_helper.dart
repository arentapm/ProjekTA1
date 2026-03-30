import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/data_qos.dart';

class DBHelper {
  static Database? _db;

  // ================= GET DATABASE =================
  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  // ================= INIT DATABASE =================
  static Future<Database> _initDB() async {
    String dbPath = await getDatabasesPath();
    String path = join(dbPath, 'qos_monitoring.db');

    print("📁 DATABASE FOLDER: $dbPath");
    print("📄 DATABASE FULL PATH: $path");

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        print("✅ DATABASE CREATED");

        await db.execute('''
        CREATE TABLE data_qos (
          id_qos INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT,
          throughput REAL,
          delay REAL,
          jitter REAL,
          sinr REAL
        )
        ''');
        // ================= TABLE QoS INDEX =================
        await db.execute('''
        CREATE TABLE qos_stability_index (
          idQosIndex INTEGER PRIMARY KEY AUTOINCREMENT,
          id_qos INTEGER,
          qos_index_value REAL,
          created_at TEXT,
          FOREIGN KEY (id_qos) REFERENCES data_qos(id_qos)
        )
        ''');
         // ================= TABLE MODEL =================
        await db.execute('''
        CREATE TABLE model_prediksi (
          id_model INTEGER PRIMARY KEY AUTOINCREMENT,
          model_name TEXT,
          model_status INTEGER,
          created_at TEXT
        )
        ''');
        // ================= TABLE STATUS =================
        await db.execute('''
        CREATE TABLE status_sistem (
          id_status_sistem INTEGER PRIMARY KEY AUTOINCREMENT,
          application_status TEXT,
          monitoring_status INTEGER,
          model_status TEXT,
          updated_at TEXT
        )
        ''');
      },
    );
  }

  // ================= INSERT QoS =================
  static Future<int> insertQoS(Map<String, dynamic> data) async {
    final db = await database;

    print("📥 INSERT DATA QoS:");
    print(data);

    int id = await db.insert("data_qos", data);

    print("✅ DATA QoS BERHASIL DISIMPAN ID: $id");

    return id;
  }

  // ================= GET ALL QoS =================
  static Future<List<Map<String, dynamic>>> getAllQoS() async {
    final db = await database;
    return await db.query("data_qos", orderBy: "id_qos DESC");
  }

   // ================= GET DATA TERAKHIR =================
  // digunakan untuk LSTM window

  static Future<List<Map<String, dynamic>>> getLastQoS(int limit) async {

    final db = await database;

    return await db.query(
      "data_qos",
      orderBy: "id_qos DESC",
      limit: limit,
    );
  }

  // ================= GET SEQUENCE UNTUK LSTM =================
  // menghasilkan format [110 x 4]

  static Future<List<List<double>>> getQoSSequence(int window) async {

    final history = await getLastQoS(window);

    if (history.length < window) {

      print("⚠️ DATA HISTORI BELUM CUKUP UNTUK LSTM");

      return [];
    }

    List<List<double>> sequence = history.map((row) {

      return [

        (row["throughput"] as num).toDouble(),
        (row["delay"] as num).toDouble(),
        (row["jitter"] as num).toDouble(),
        (row["sinr"] as num).toDouble(),

      ];

    }).toList();

    // karena query DESC, kita balik agar urutan waktu benar
    sequence = sequence.reversed.toList();

    print("✅ SEQUENCE LSTM BERHASIL DIBUAT");
    print("Window size: ${sequence.length}");

    return sequence;
  }

  static Future<List<DataQoS>> getLastNQoS(int n) async {

  final db = await DBHelper.database;

  final result = await db.query(
    'data_qos',
    orderBy: 'timestamp DESC',
    limit: n,
  );

  return result.map((map) => DataQoS.fromMap(map)).toList();

}

  // ================= PRINT SEMUA DATA =================
  static Future<void> debugPrintAllQoS() async {
    final db = await database;

    List<Map<String, dynamic>> result =
        await db.query("data_qos", orderBy: "id_qos DESC");

    print("");
    print("========== 📊 ISI DATABASE QoS ==========");

    if (result.isEmpty) {
      print("⚠️ DATABASE MASIH KOSONG");
    } else {
      for (var row in result) {
        print(row);
      }
    }

    print("========== END DATABASE ==========");
    print("");
  }
}
