import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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

        await db.execute('''
        CREATE TABLE qos_stability_index (
          idQosIndex INTEGER PRIMARY KEY AUTOINCREMENT,
          id_qos INTEGER,
          qos_index_value REAL,
          created_at TEXT,
          FOREIGN KEY (id_qos) REFERENCES data_qos(id_qos)
        )
        ''');

        await db.execute('''
        CREATE TABLE model_prediksi (
          id_model INTEGER PRIMARY KEY AUTOINCREMENT,
          model_name TEXT,
          model_status INTEGER,
          created_at TEXT
        )
        ''');

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
  static Future<List<Map<String, dynamic>>> getQoS() async {
    final db = await database;
    return await db.query("data_qos", orderBy: "id_qos DESC");
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
