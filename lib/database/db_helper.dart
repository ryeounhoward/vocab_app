import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  // Table Names
  static const String tableVocab = "vocabulary";
  static const String tableIdioms = "idioms";
  static const String tableWordGroups = "word_groups";
  static const String tableWordGroupItems = "word_group_items";
  static const String tableIdiomGroups = "idiom_groups";
  static const String tableIdiomGroupItems = "idiom_group_items";
  static const String tablePreferences = "app_preferences";

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  Future<Database> initDb() async {
    String path = join(await getDatabasesPath(), "vocab.db");
    return await openDatabase(
      path,
      version: 9, // Version 9 adds app_preferences table
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

        // Create Word Groups Table
        await db.execute('''
        CREATE TABLE $tableWordGroups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL
        )
        ''');

        // Create Word Group Items Table (many-to-many between groups and vocabulary words)
        await db.execute('''
        CREATE TABLE $tableWordGroupItems (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          group_id INTEGER NOT NULL,
          word_id INTEGER NOT NULL
        )
        ''');

        // Create Idiom Groups Table
        await db.execute('''
        CREATE TABLE $tableIdiomGroups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL
        )
        ''');

        // Create Idiom Group Items Table (many-to-many between groups and idioms)
        await db.execute('''
        CREATE TABLE $tableIdiomGroupItems (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          group_id INTEGER NOT NULL,
          idiom_id INTEGER NOT NULL
        )
        ''');

        // Create simple key-value preferences table
        await db.execute('''
        CREATE TABLE $tablePreferences (
          key TEXT PRIMARY KEY,
          value TEXT
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

        // Add word group tables on upgrade
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableWordGroups (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableWordGroupItems (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              group_id INTEGER NOT NULL,
              word_id INTEGER NOT NULL
            )
          ''');
        }

        // Add idiom group tables on upgrade
        if (oldVersion < 8) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableIdiomGroups (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableIdiomGroupItems (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              group_id INTEGER NOT NULL,
              idiom_id INTEGER NOT NULL
            )
          ''');
        }

        // Add preferences table on upgrade
        if (oldVersion < 9) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tablePreferences (
              key TEXT PRIMARY KEY,
              value TEXT
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

  // --- APP PREFERENCES (KEY-VALUE) ---

  Future<void> setPreference(String key, String value) async {
    final Database dbClient = await db;
    await dbClient.insert(tablePreferences, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getPreference(String key) async {
    final Database dbClient = await db;
    final List<Map<String, dynamic>> rows = await dbClient.query(
      tablePreferences,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> removePreference(String key) async {
    final Database dbClient = await db;
    await dbClient.delete(tablePreferences, where: 'key = ?', whereArgs: [key]);
  }

  // --- WORD GROUP HELPERS ---

  Future<List<Map<String, dynamic>>> getAllWordGroups() async {
    final Database dbClient = await db;
    return dbClient.query(tableWordGroups, orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<int> insertWordGroup(String name) async {
    final Database dbClient = await db;
    return dbClient.insert(tableWordGroups, {'name': name});
  }

  Future<int> updateWordGroup(int id, String name) async {
    final Database dbClient = await db;
    return dbClient.update(
      tableWordGroups,
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteWordGroup(int id) async {
    final Database dbClient = await db;
    // Remove items first, then the group itself
    await dbClient.delete(
      tableWordGroupItems,
      where: 'group_id = ?',
      whereArgs: [id],
    );
    await dbClient.delete(tableWordGroups, where: 'id = ?', whereArgs: [id]);
  }

  Future<Set<int>> getWordIdsForGroup(int groupId) async {
    final Database dbClient = await db;
    final List<Map<String, dynamic>> rows = await dbClient.query(
      tableWordGroupItems,
      columns: ['word_id'],
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    return rows.map((row) => row['word_id']).whereType<int>().toSet();
  }

  Future<void> setGroupWords(int groupId, Set<int> wordIds) async {
    final Database dbClient = await db;

    final Batch batch = dbClient.batch();
    batch.delete(
      tableWordGroupItems,
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    for (final int wordId in wordIds) {
      batch.insert(tableWordGroupItems, {
        'group_id': groupId,
        'word_id': wordId,
      });
    }

    await batch.commit(noResult: true);
  }

  /// Add a single vocabulary word to a specific group (no-op if already there).
  Future<void> addWordToGroup(int groupId, int wordId) async {
    final Database dbClient = await db;

    final List<Map<String, dynamic>> existing = await dbClient.query(
      tableWordGroupItems,
      columns: ['id'],
      where: 'group_id = ? AND word_id = ?',
      whereArgs: [groupId, wordId],
      limit: 1,
    );

    if (existing.isNotEmpty) return;

    await dbClient.insert(tableWordGroupItems, {
      'group_id': groupId,
      'word_id': wordId,
    });
  }

  // --- IDIOM GROUP HELPERS ---

  Future<List<Map<String, dynamic>>> getAllIdiomGroups() async {
    final Database dbClient = await db;
    return dbClient.query(tableIdiomGroups, orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<int> insertIdiomGroup(String name) async {
    final Database dbClient = await db;
    return dbClient.insert(tableIdiomGroups, {'name': name});
  }

  Future<int> updateIdiomGroup(int id, String name) async {
    final Database dbClient = await db;
    return dbClient.update(
      tableIdiomGroups,
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteIdiomGroup(int id) async {
    final Database dbClient = await db;
    await dbClient.delete(
      tableIdiomGroupItems,
      where: 'group_id = ?',
      whereArgs: [id],
    );
    await dbClient.delete(tableIdiomGroups, where: 'id = ?', whereArgs: [id]);
  }

  Future<Set<int>> getIdiomIdsForGroup(int groupId) async {
    final Database dbClient = await db;
    final List<Map<String, dynamic>> rows = await dbClient.query(
      tableIdiomGroupItems,
      columns: ['idiom_id'],
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    return rows.map((row) => row['idiom_id']).whereType<int>().toSet();
  }

  Future<void> setGroupIdioms(int groupId, Set<int> idiomIds) async {
    final Database dbClient = await db;

    final Batch batch = dbClient.batch();
    batch.delete(
      tableIdiomGroupItems,
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    for (final int idiomId in idiomIds) {
      batch.insert(tableIdiomGroupItems, {
        'group_id': groupId,
        'idiom_id': idiomId,
      });
    }

    await batch.commit(noResult: true);
  }
}
