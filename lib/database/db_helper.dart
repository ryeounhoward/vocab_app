import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  // Table Names
  static const String tableVocab = "vocabulary";
  static const String tableIdioms = "idioms";

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  Future<Database> initDb() async {
    String path = join(await getDatabasesPath(), "vocab.db");
    return await openDatabase(
      path,
      version: 6, // Version 6 adds synonyms column to vocabulary
      onCreate: (db, version) async {
        // Create Vocabulary Table
        await db.execute('''
        CREATE TABLE $tableVocab (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT,
          description TEXT,
          examples TEXT,
          word_type TEXT,
          image_path TEXT,
          synonyms TEXT,
          is_favorite INTEGER DEFAULT 0
        )
        ''');

        // Create Idioms Table
        await db.execute('''
        CREATE TABLE $tableIdioms (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          idiom TEXT,
          description TEXT,
          examples TEXT,
          image_path TEXT,
          is_favorite INTEGER DEFAULT 0
        )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE $tableVocab ADD COLUMN is_favorite INTEGER DEFAULT 0",
          );
        }
        if (oldVersion < 6) {
          await db.execute("ALTER TABLE $tableVocab ADD COLUMN synonyms TEXT");
        }
        // Force creation of idioms table if it doesn't exist during upgrade
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableIdioms (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              idiom TEXT,
              description TEXT,
              examples TEXT,
              image_path TEXT,
              is_favorite INTEGER DEFAULT 0
            )
          ''');
        }
      },
    );
  }

  // --- CRUD OPERATIONS ---

  // 1. Create (Insert)
  Future<int> insert(
    Map<String, dynamic> row, [
    String table = tableVocab,
  ]) async {
    Database dbClient = await db;
    return await dbClient.insert(table, row);
  }

  // 2. Read (Query All)
  Future<List<Map<String, dynamic>>> queryAll([
    String table = tableVocab,
  ]) async {
    Database dbClient = await db;
    return await dbClient.query(table, orderBy: "id DESC");
  }

  // 3. Update (REQUIRED FOR YOUR ERRORS)
  Future<int> update(
    Map<String, dynamic> row, [
    String table = tableVocab,
  ]) async {
    Database dbClient = await db;
    return await dbClient.update(
      table,
      row,
      where: "id = ?",
      whereArgs: [row['id']],
    );
  }

  // 4. Delete
  Future<int> delete(int id, [String table = tableVocab]) async {
    Database dbClient = await db;
    return await dbClient.delete(table, where: "id = ?", whereArgs: [id]);
  }

  // 5. Toggle Favorite (REQUIRED FOR YOUR ERRORS)
  Future<int> toggleFavorite(
    int id,
    bool isFavorite, [
    String table = tableVocab,
  ]) async {
    Database dbClient = await db;
    return await dbClient.update(
      table,
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 6. Clear Table
  Future<void> clearTable([String table = tableVocab]) async {
    Database dbClient = await db;
    await dbClient.delete(table);
  }
}
