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
  static const String tableNotifications = "notifications";

  // NEW: Notes Table Name
  static const String tableNotes = "notes";

  Future<bool> _columnExists(Database db, String table, String column) async {
    final result = await db.rawQuery('PRAGMA table_info($table)');
    return result.any((row) => row['name'] == column);
  }

  Future<void> _ensureNotificationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableNotifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        body TEXT,
        route TEXT,
        route_args TEXT,
        created_at INTEGER,
        read INTEGER DEFAULT 0
      )
    ''');
  }

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  Future<Database> initDb() async {
    String path = join(await getDatabasesPath(), "vocab.db");
    return await openDatabase(
      path,
      // NEW: Incremented version to 14 to add notifications table
      version: 14,
      onCreate: (db, version) async {
        // Create Vocabulary Table
        await db.execute('''
        CREATE TABLE $tableVocab (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word TEXT,
          pronunciation TEXT,
          description TEXT,
          examples TEXT,
          tense_data TEXT,
          related_forms TEXT,
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

        // Create Word Group Items Table
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

        // Create Idiom Group Items Table
        await db.execute('''
        CREATE TABLE $tableIdiomGroupItems (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          group_id INTEGER NOT NULL,
          idiom_id INTEGER NOT NULL
        )
        ''');

        // Create Preferences Table
        await db.execute('''
        CREATE TABLE $tablePreferences (
          key TEXT PRIMARY KEY,
          value TEXT
        )
        ''');

        // NEW: Create Notes Table
        await db.execute('''
        CREATE TABLE $tableNotes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          category TEXT,
          content TEXT,
          color INTEGER,
          date TEXT
        )
        ''');

        // NEW: Create Notifications Table
        await db.execute('''
        CREATE TABLE $tableNotifications (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          body TEXT,
          route TEXT,
          route_args TEXT,
          created_at INTEGER,
          read INTEGER DEFAULT 0
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
        if (oldVersion < 9) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tablePreferences (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        }

        // NEW: Upgrade logic for Version 10 (Notes)
        if (oldVersion < 10) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableNotes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT,
              category TEXT,
              content TEXT,
              color INTEGER,
              date TEXT
            )
          ''');
        }

        // NEW: Upgrade logic for Version 11 (Vocabulary tense/conjugation data)
        if (oldVersion < 11) {
          await db.execute(
            "ALTER TABLE $tableVocab ADD COLUMN tense_data TEXT",
          );
        }

        // NEW: Upgrade logic for Version 12 (Vocabulary pronunciation)
        if (oldVersion < 12) {
          await db.execute(
            "ALTER TABLE $tableVocab ADD COLUMN pronunciation TEXT",
          );
        }

        // NEW: Upgrade logic for Version 13 (Vocabulary related forms)
        if (oldVersion < 13) {
          final hasColumn = await _columnExists(
            db,
            tableVocab,
            'related_forms',
          );
          if (!hasColumn) {
            await db.execute(
              "ALTER TABLE $tableVocab ADD COLUMN related_forms TEXT",
            );
          }
        }

        // NEW: Upgrade logic for Version 14 (Notifications)
        if (oldVersion < 14) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableNotifications (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT,
              body TEXT,
              route TEXT,
              route_args TEXT,
              created_at INTEGER,
              read INTEGER DEFAULT 0
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

  // 3. Update
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

  // 5. Toggle Favorite
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

  // --- NEW: NOTES SPECIFIC OPERATIONS ---

  Future<int> insertNote(Map<String, dynamic> note) async {
    final dbClient = await db;
    return await dbClient.insert(tableNotes, note);
  }

  Future<List<Map<String, dynamic>>> getAllNotes() async {
    final dbClient = await db;
    // Order by date, newest first
    return await dbClient.query(tableNotes, orderBy: "date DESC");
  }

  Future<int> updateNote(Map<String, dynamic> note) async {
    final dbClient = await db;
    return await dbClient.update(
      tableNotes,
      note,
      where: 'id = ?',
      whereArgs: [note['id']],
    );
  }

  Future<int> deleteNote(int id) async {
    final dbClient = await db;
    return await dbClient.delete(tableNotes, where: 'id = ?', whereArgs: [id]);
  }

  // --- NOTIFICATIONS ---

  Future<int> insertNotification(Map<String, dynamic> notification) async {
    final dbClient = await db;
    await _ensureNotificationsTable(dbClient);
    return await dbClient.insert(tableNotifications, notification);
  }

  Future<List<Map<String, dynamic>>> getAllNotifications() async {
    final dbClient = await db;
    await _ensureNotificationsTable(dbClient);
    return await dbClient.query(
      tableNotifications,
      orderBy: 'created_at DESC, id DESC',
    );
  }

  Future<int> markNotificationRead(int id) async {
    final dbClient = await db;
    await _ensureNotificationsTable(dbClient);
    return await dbClient.update(
      tableNotifications,
      {'read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> markAllNotificationsRead() async {
    final dbClient = await db;
    await _ensureNotificationsTable(dbClient);
    return await dbClient.update(tableNotifications, {'read': 1});
  }

  Future<int> getUnreadNotificationCount() async {
    final dbClient = await db;
    await _ensureNotificationsTable(dbClient);
    final result = await dbClient.rawQuery(
      'SELECT COUNT(*) as count FROM $tableNotifications WHERE read = 0',
    );
    return (result.first['count'] as int?) ?? 0;
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

  Future<Map<int, List<Map<String, dynamic>>>> getWordGroupsForWordIds(
    Set<int> wordIds,
  ) async {
    if (wordIds.isEmpty) return <int, List<Map<String, dynamic>>>{};
    final Database dbClient = await db;
    final List<int> ids = wordIds.toList();
    final String placeholders = List.filled(ids.length, '?').join(',');

    final List<Map<String, Object?>> rows = await dbClient.rawQuery('''
      SELECT
        wgi.word_id AS item_id,
        wg.id AS group_id,
        wg.name AS group_name
      FROM $tableWordGroupItems wgi
      JOIN $tableWordGroups wg ON wg.id = wgi.group_id
      WHERE wgi.word_id IN ($placeholders)
      ORDER BY wg.name COLLATE NOCASE ASC
    ''', ids);

    final Map<int, List<Map<String, dynamic>>> result =
        <int, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final int? itemId = row['item_id'] as int?;
      final int? groupId = row['group_id'] as int?;
      final String name = (row['group_name'] ?? '').toString().trim();
      if (itemId == null || groupId == null || name.isEmpty) continue;
      result.putIfAbsent(itemId, () => <Map<String, dynamic>>[]).add({
        'id': groupId,
        'name': name,
      });
    }
    return result;
  }

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

  Future<Map<int, List<Map<String, dynamic>>>> getIdiomGroupsForIdiomIds(
    Set<int> idiomIds,
  ) async {
    if (idiomIds.isEmpty) return <int, List<Map<String, dynamic>>>{};
    final Database dbClient = await db;
    final List<int> ids = idiomIds.toList();
    final String placeholders = List.filled(ids.length, '?').join(',');

    final List<Map<String, Object?>> rows = await dbClient.rawQuery('''
      SELECT
        igi.idiom_id AS item_id,
        ig.id AS group_id,
        ig.name AS group_name
      FROM $tableIdiomGroupItems igi
      JOIN $tableIdiomGroups ig ON ig.id = igi.group_id
      WHERE igi.idiom_id IN ($placeholders)
      ORDER BY ig.name COLLATE NOCASE ASC
    ''', ids);

    final Map<int, List<Map<String, dynamic>>> result =
        <int, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final int? itemId = row['item_id'] as int?;
      final int? groupId = row['group_id'] as int?;
      final String name = (row['group_name'] ?? '').toString().trim();
      if (itemId == null || groupId == null || name.isEmpty) continue;
      result.putIfAbsent(itemId, () => <Map<String, dynamic>>[]).add({
        'id': groupId,
        'name': name,
      });
    }
    return result;
  }

  Future<void> addIdiomToGroup(int groupId, int idiomId) async {
    final Database dbClient = await db;
    final List<Map<String, dynamic>> existing = await dbClient.query(
      tableIdiomGroupItems,
      columns: ['id'],
      where: 'group_id = ? AND idiom_id = ?',
      whereArgs: [groupId, idiomId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await dbClient.insert(tableIdiomGroupItems, {
      'group_id': groupId,
      'idiom_id': idiomId,
    });
  }
}
