import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  // Use 'db' as the getter name consistently
  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  Future<Database> initDb() async {
    String path = join(await getDatabasesPath(), "vocab.db");
    return await openDatabase(
      path,
      version: 2, // Incremented to 2 because we added a new column
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE vocabulary (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT,
          description TEXT,
          examples TEXT,
          word_type TEXT,
          image_path TEXT,
          is_favorite INTEGER DEFAULT 0  -- 1. ADDED THIS COLUMN
        )
      ''');
      },
      // 2. ADDED THIS to handle updates if the app was already installed
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE vocabulary ADD COLUMN is_favorite INTEGER DEFAULT 0",
          );
        }
      },
    );
  }

  // FIXED: Changed 'database' to 'db' to match your getter
  Future<int> toggleFavorite(int id, bool isFavorite) async {
    Database dbClient = await db;
    return await dbClient.update(
      'vocabulary',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Create
  Future<int> insert(Map<String, dynamic> row) async {
    Database dbClient = await db;
    return await dbClient.insert("vocabulary", row);
  }

  // Read
  Future<List<Map<String, dynamic>>> queryAll() async {
    Database dbClient = await db;
    return await dbClient.query("vocabulary");
  }

  // Update
  Future<int> update(Map<String, dynamic> row) async {
    Database dbClient = await db;
    return await dbClient.update(
      "vocabulary",
      row,
      where: "id = ?",
      whereArgs: [row['id']],
    );
  }

  // Delete
  Future<int> delete(int id) async {
    Database dbClient = await db;
    return await dbClient.delete(
      "vocabulary",
      where: "id = ?",
      whereArgs: [id],
    );
  }
}
