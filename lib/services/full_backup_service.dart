import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/db_helper.dart';

class FullBackupService {
  FullBackupService({DBHelper? dbHelper}) : _dbHelper = dbHelper ?? DBHelper();

  final DBHelper _dbHelper;

  static const String fullBackupZipFileName = 'app_full_backup.zip';
  static const String cheatSheetPrefsKey = 'cheat_sheet_docs_v1';

  Future<File?> buildFullBackupZipToTemp({
    void Function(double fraction, String label)? onProgress,
    String progressLabel = 'Preparing backup',
  }) async {
    void progress(double fraction) {
      onProgress?.call(fraction.clamp(0.0, 1.0), progressLabel);
    }

    List<Map<String, dynamic>> vocabData = await _dbHelper.queryAll(
      DBHelper.tableVocab,
    );
    List<Map<String, dynamic>> idiomData = await _dbHelper.queryAll(
      DBHelper.tableIdioms,
    );

    progress(0.05);

    // Read sort-words related preferences to include in backup
    final String? quizUseAll = await _dbHelper.getPreference(
      'quiz_use_all_words',
    );
    final String? quizSelectedIds = await _dbHelper.getPreference(
      'quiz_selected_word_ids',
    );
    final String? quizSelectedGroupId = await _dbHelper.getPreference(
      'quiz_selected_word_group_id',
    );

    final Map<String, dynamic> sortWordSettings = {};
    if (quizUseAll != null) {
      sortWordSettings['quiz_use_all_words'] = quizUseAll;
    }
    if (quizSelectedIds != null) {
      sortWordSettings['quiz_selected_word_ids'] = quizSelectedIds;
    }
    if (quizSelectedGroupId != null) {
      sortWordSettings['quiz_selected_word_group_id'] = quizSelectedGroupId;
    }

    final Map<String, dynamic> backupPayload = {
      "version": 1,
      "vocabulary": vocabData,
      "idioms": idiomData,
    };

    // Include word groups (by group name and word text) in ZIP backup
    final List<Map<String, dynamic>> wordGroupsPayload =
        await _buildWordGroupsPayload(vocabData);
    if (wordGroupsPayload.isNotEmpty) {
      backupPayload['word_groups'] = wordGroupsPayload;
    }

    if (sortWordSettings.isNotEmpty) {
      backupPayload['sort_word_settings'] = sortWordSettings;
    }

    // Include quiz history from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final String? quizHistory = prefs.getString('quiz_history');
    final int? quizHistoryNext = prefs.getInt('quiz_history_next_number');
    if (quizHistory != null) {
      backupPayload['quiz_history'] = quizHistory;
    }
    if (quizHistoryNext != null) {
      backupPayload['quiz_history_next_number'] = quizHistoryNext;
    }

    // Include notes
    final List<Map<String, dynamic>> notes = await _dbHelper.queryAll('notes');
    backupPayload['notes'] = notes;

    // Include cheat sheet metadata from SharedPreferences
    List<dynamic> cheatSheetDocs = const [];
    final String? cheatSheetRaw = prefs.getString(cheatSheetPrefsKey);
    if (cheatSheetRaw != null && cheatSheetRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(cheatSheetRaw);
        if (decoded is List) {
          cheatSheetDocs = decoded;
        }
      } catch (_) {}
    }
    if (cheatSheetDocs.isNotEmpty) {
      backupPayload['cheat_sheet_docs'] = cheatSheetDocs;
    }

    if (vocabData.isEmpty &&
        idiomData.isEmpty &&
        notes.isEmpty &&
        cheatSheetDocs.isEmpty) {
      return null;
    }

    final String jsonString = jsonEncode(backupPayload);
    final List<int> jsonBytes = utf8.encode(jsonString);

    progress(0.10);

    final tempDir = await getTemporaryDirectory();
    final String tempZipPath = p.join(tempDir.path, fullBackupZipFileName);

    final tempZipFile = File(tempZipPath);
    if (await tempZipFile.exists()) {
      await tempZipFile.delete();
    }

    final encoder = ZipFileEncoder();
    encoder.create(tempZipPath);

    // Add JSON first
    progress(0.15);
    final jsonArchiveFile = ArchiveFile(
      'data/backup.json',
      jsonBytes.length,
      jsonBytes,
    );
    encoder.addArchiveFile(jsonArchiveFile);

    // Add Photos + Cheat Sheet files
    progress(0.20);
    final List<MapEntry<File, String>> filesToZip = [];

    final String imagesPath = await _getLocalImagesPath();
    final Directory imgDir = Directory(imagesPath);
    if (await imgDir.exists()) {
      final imageFiles = await imgDir
          .list(followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      for (final file in imageFiles) {
        filesToZip.add(MapEntry(file, 'images/${p.basename(file.path)}'));
      }
    }

    final String cheatSheetsPath = await _getCheatSheetsPath();
    final Directory cheatDir = Directory(cheatSheetsPath);
    if (await cheatDir.exists()) {
      final cheatFiles = await cheatDir
          .list(followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      for (final file in cheatFiles) {
        filesToZip.add(MapEntry(file, 'cheat_sheets/${p.basename(file.path)}'));
      }
    }

    final int totalFiles = filesToZip.length;
    int processed = 0;
    for (final entry in filesToZip) {
      processed++;
      await encoder.addFile(entry.key, entry.value);

      if (totalFiles > 0) {
        final double fileFraction = processed / totalFiles;
        final double overallFraction = 0.20 + (fileFraction * 0.68);
        progress(overallFraction);
      }

      await Future.delayed(const Duration(milliseconds: 10));
    }

    progress(0.93);
    encoder.close();
    progress(1.0);

    return tempZipFile;
  }

  Future<String> _getLocalImagesPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "images");
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  Future<String> _getCheatSheetsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "cheat_sheets");
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  Future<List<Map<String, dynamic>>> _buildWordGroupsPayload(
    List<Map<String, dynamic>> vocabData,
  ) async {
    if (vocabData.isEmpty) return [];

    final Map<int, String> wordIdToText = {};
    for (final Map<String, dynamic> row in vocabData) {
      final dynamic idValue = row['id'];
      final dynamic wordValue = row['word'];
      if (idValue is int && wordValue != null) {
        final String wordText = wordValue.toString();
        if (wordText.trim().isNotEmpty) {
          wordIdToText[idValue] = wordText;
        }
      }
    }

    if (wordIdToText.isEmpty) return [];

    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllWordGroups();
    final List<Map<String, dynamic>> result = [];

    for (final Map<String, dynamic> group in groups) {
      final dynamic groupIdValue = group['id'];
      final dynamic groupNameValue = group['name'];
      if (groupIdValue is! int || groupNameValue == null) continue;

      final String groupName = groupNameValue.toString();
      if (groupName.trim().isEmpty) continue;

      final Set<int> wordIds = await _dbHelper.getWordIdsForGroup(groupIdValue);
      final List<String> wordsInGroup = [];
      for (final int wid in wordIds) {
        final String? wordText = wordIdToText[wid];
        if (wordText != null && wordText.trim().isNotEmpty) {
          wordsInGroup.add(wordText);
        }
      }

      if (wordsInGroup.isNotEmpty) {
        result.add({'name': groupName, 'words': wordsInGroup});
      }
    }

    return result;
  }
}
