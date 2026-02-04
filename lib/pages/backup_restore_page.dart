import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
// Core archive types
import 'package:archive/archive_io.dart'; // For ZipFileEncoder streaming
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import 'google_drive_Service.dart';
import 'backup_preferences_page.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  GoogleSignInAccount? _googleAccount;

  int _lastProgressPercent = -1;

  StateSetter? _loadingDialogSetState;
  Completer<void>? _loadingDialogReady;
  bool _loadingDialogOpen = false;
  double? _loadingFraction;

  @override
  void initState() {
    super.initState();
    _fetchGoogleAccount();
  }

  Future<void> _fetchGoogleAccount() async {
    final account = await _googleDriveService.ensureSignedIn(
      interactive: false,
    );
    if (mounted) {
      setState(() {
        _googleAccount = account;
      });
    }
  }

  final DBHelper _dbHelper = DBHelper();
  final GoogleDriveService _googleDriveService = GoogleDriveService();

  static const String _fullBackupZipFileName = 'app_full_backup.zip';
  static const String _googleDriveIconAsset =
      'assets/images/Google_Drive_icon_(2020).svg';

  String _loadingMessage = '';

  // --- NOTES IMPORT/EXPORT ---
  Future<void> _exportNotesToJson() async {
    try {
      await _showLoadingDialog("Exporting notes to JSON...");
      // Fetch all notes from DB
      List<Map<String, dynamic>> notes = await _dbHelper.queryAll('notes');
      if (notes.isEmpty) {
        _showSnackBar("No notes found to export");
        return;
      }
      Map<String, dynamic> notesBackup = {"version": 1, "notes": notes};
      String jsonString = jsonEncode(notesBackup);
      Uint8List bytes = Uint8List.fromList(utf8.encode(jsonString));
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Notes JSON:',
        fileName: 'notes_backup.json',
        bytes: bytes,
      );
      if (outputPath != null) {
        _showSnackBar("Notes backup saved successfully!");
      }
    } catch (e) {
      _showSnackBar("Export Notes Error: $e");
    } finally {
      _hideLoadingDialog();
    }
  }

  Future<void> _importNotesFromJson() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        dynamic jsonData = jsonDecode(content);
        List<dynamic> notesToProcess = [];
        if (jsonData is Map && jsonData.containsKey('notes')) {
          notesToProcess = jsonData['notes'] ?? [];
        } else if (jsonData is List) {
          notesToProcess = jsonData;
        }
        bool? confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Import Notes"),
            content: Text(
              "Items found:\n- Notes: ${notesToProcess.length}\n\nExisting notes will be skipped. Continue?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Import"),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _showLoadingDialog("Importing notes from JSON...");
          try {
            int addedNotes = await _processNotesImport(notesToProcess);
            _showSnackBar("Notes import finished! Added: $addedNotes notes.");
          } finally {
            _hideLoadingDialog();
          }
        }
      }
    } catch (e) {
      _showSnackBar("Import Notes Failed: $e");
    }
  }

  Future<int> _processNotesImport(
    List<dynamic> notes, {
    void Function(int processed, int total)? onProgress,
  }) async {
    if (notes.isEmpty) return 0;
    List<Map<String, dynamic>> existingNotes = await _dbHelper.queryAll(
      'notes',
    );
    Set<String> existingKeys = existingNotes
        .map((e) => (e['id'] ?? '').toString())
        .toSet();
    int addedCount = 0;
    int processed = 0;
    final int total = notes.length;
    for (var item in notes) {
      processed++;
      Map<String, dynamic> row = Map<String, dynamic>.from(item);
      // Use a unique key for notes, e.g., title+content or id if available
      String? noteKey;
      if (row.containsKey('id')) {
        noteKey = row['id'].toString();
      } else if (row.containsKey('title') && row.containsKey('content')) {
        noteKey =
            row['title'].toString().trim() + row['content'].toString().trim();
      }
      if (noteKey != null && !existingKeys.contains(noteKey)) {
        row.remove('id');
        await _dbHelper.insert(row, 'notes');
        existingKeys.add(noteKey);
        addedCount++;
      }

      if (onProgress != null && total > 0) {
        if (processed == 1 || processed == total || processed % 25 == 0) {
          onProgress(processed, total);
        }
      }
    }

    onProgress?.call(total, total);
    return addedCount;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Loading dialog helpers ---
  Future<void> _showLoadingDialog(String message) async {
    if (!mounted) return;

    _loadingDialogReady = Completer<void>();
    _loadingDialogOpen = true;
    _loadingMessage = message;
    _loadingFraction = null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            _loadingDialogSetState = setState;
            final ready = _loadingDialogReady;
            if (ready != null && !ready.isCompleted) {
              ready.complete();
            }

            return WillPopScope(
              onWillPop: () async => false,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                content: SizedBox(
                  width: 300,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loadingMessage,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: _loadingFraction,
                        minHeight: 6,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // Ensure dialog is mounted before long work starts.
    await _loadingDialogReady?.future;
  }

  void _updateLoadingMessage(String message) {
    if (!mounted) return;
    if (_loadingMessage == message) return;
    _loadingMessage = message;
    final setter = _loadingDialogSetState;
    if (_loadingDialogOpen && setter != null) {
      setter(() {});
    } else {
      setState(() {});
    }
  }

  void _updateLoadingProgress(double fraction, String baseLabel) {
    if (!mounted) return;
    final double clamped = fraction.clamp(0.01, 1.0);
    final int percent = (clamped * 100).round();
    if (percent == _lastProgressPercent) return;
    _lastProgressPercent = percent;
    _loadingFraction = clamped;
    _updateLoadingMessage('$baseLabel ($percent%)');
  }

  void _resetProgressThrottle() {
    _lastProgressPercent = -1;
  }

  void _hideLoadingDialog() {
    if (!mounted) return;
    _loadingDialogOpen = false;
    _loadingDialogSetState = null;
    _loadingDialogReady = null;
    _loadingFraction = null;
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // --- HELPER: GET LOCAL IMAGE DIRECTORY ---
  Future<String> _getLocalImagesPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "images");
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  // ---------------------------------------------------------
  // 1. ORIGINAL JSON EXPORT (Your Old Code)
  // ---------------------------------------------------------
  Future<void> _exportData() async {
    try {
      await _showLoadingDialog("Exporting JSON backup...");
      List<Map<String, dynamic>> vocabData = await _dbHelper.queryAll(
        DBHelper.tableVocab,
      );
      List<Map<String, dynamic>> idiomData = await _dbHelper.queryAll(
        DBHelper.tableIdioms,
      );

      if (vocabData.isEmpty && idiomData.isEmpty) {
        _showSnackBar("No data found to export");
        return;
      }

      Map<String, dynamic> backupData = {
        "version": 1,
        "vocabulary": vocabData,
        "idioms": idiomData,
      };

      // Include word groups (by group name and word text) in JSON backup
      final List<Map<String, dynamic>> wordGroupsPayload =
          await _buildWordGroupsPayload(vocabData);
      if (wordGroupsPayload.isNotEmpty) {
        backupData['word_groups'] = wordGroupsPayload;
      }

      String jsonString = jsonEncode(backupData);
      Uint8List bytes = Uint8List.fromList(utf8.encode(jsonString));

      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select where to save your backup:',
        fileName: 'vocab_idioms_backup.json',
        bytes: bytes,
      );

      if (outputPath != null) {
        _showSnackBar("Backup saved successfully!");
      }
    } catch (e) {
      _showSnackBar("Export Error: $e");
    } finally {
      _hideLoadingDialog();
    }
  }

  // ---------------------------------------------------------
  // 2. ORIGINAL JSON IMPORT (Your Old Code)
  // ---------------------------------------------------------
  Future<void> _importData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        dynamic jsonData = jsonDecode(content);

        List<dynamic> vocabToProcess = [];
        List<dynamic> idiomsToProcess = [];
        List<dynamic> wordGroupsToProcess = [];

        if (jsonData is Map && jsonData.containsKey('vocabulary')) {
          vocabToProcess = jsonData['vocabulary'] ?? [];
          idiomsToProcess = jsonData['idioms'] ?? [];
          if (jsonData['word_groups'] is List) {
            wordGroupsToProcess = jsonData['word_groups'] as List<dynamic>;
          }
        } else if (jsonData is List) {
          vocabToProcess = jsonData;
        }

        bool? confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Import Data"),
            content: Text(
              "Items found:\n- Words: ${vocabToProcess.length}\n- Idioms: ${idiomsToProcess.length}\n\nExisting items will be skipped. Continue?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Import"),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await _showLoadingDialog("Importing JSON backup...");
          try {
            int addedWords = await _processImport(
              vocabToProcess,
              DBHelper.tableVocab,
              'word',
            );
            int addedIdioms = await _processImport(
              idiomsToProcess,
              DBHelper.tableIdioms,
              'idiom',
            );
            int createdWordGroups = await _processWordGroupsImport(
              wordGroupsToProcess,
            );
            _showSnackBar(
              "Import Finished!\nAdded: $addedWords words, $addedIdioms idioms, $createdWordGroups word groups.",
            );
          } finally {
            _hideLoadingDialog();
          }
        }
      }
    } catch (e) {
      _showSnackBar("Import Failed: $e");
    }
  }

  // ---------------------------------------------------------
  // 3. NEW ZIP EXPORT (JSON + Photos)
  // ---------------------------------------------------------
  Future<File?> _buildFullBackupZipToTemp({
    required String progressLabel,
  }) async {
    List<Map<String, dynamic>> vocabData = await _dbHelper.queryAll(
      DBHelper.tableVocab,
    );
    List<Map<String, dynamic>> idiomData = await _dbHelper.queryAll(
      DBHelper.tableIdioms,
    );
    _updateLoadingProgress(0.05, progressLabel);

    if (vocabData.isEmpty && idiomData.isEmpty) {
      _showSnackBar("No data found to export");
      return null;
    }

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

    // Add Database JSON (including sort word settings) to ZIP
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

    // --- Include notes in backup ---
    List<Map<String, dynamic>> notes = await _dbHelper.queryAll('notes');
    backupPayload['notes'] = notes;

    String jsonString = jsonEncode(backupPayload);
    List<int> jsonBytes = utf8.encode(jsonString);

    _updateLoadingProgress(0.10, progressLabel);

    // Create a temporary ZIP on disk using a streaming encoder so
    // the UI can update between files.
    final tempDir = await getTemporaryDirectory();
    final String tempZipPath = p.join(tempDir.path, _fullBackupZipFileName);

    // Remove any previous temporary ZIP.
    final tempZipFile = File(tempZipPath);
    if (await tempZipFile.exists()) {
      await tempZipFile.delete();
    }

    final encoder = ZipFileEncoder();
    encoder.create(tempZipPath);

    // Add the JSON backup as the first entry.
    _updateLoadingProgress(0.15, progressLabel);
    final jsonArchiveFile = ArchiveFile(
      'data/backup.json',
      jsonBytes.length,
      jsonBytes,
    );
    encoder.addArchiveFile(jsonArchiveFile);

    // Add Photos from app folder to ZIP, with progress updates.
    _updateLoadingProgress(0.20, progressLabel);
    String imagesPath = await _getLocalImagesPath();
    Directory imgDir = Directory(imagesPath);
    if (await imgDir.exists()) {
      final List<File> files = await imgDir
          .list(followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      final int totalFiles = files.length;
      int processed = 0;

      for (final File file in files) {
        processed++;
        final String filename = p.basename(file.path);
        await encoder.addFile(file, 'images/$filename');

        if (totalFiles > 0) {
          final double photoFraction = processed / totalFiles;
          // Photos occupy the middle 70% of the progress bar.
          final double overallFraction = 0.20 + (photoFraction * 0.70);
          _updateLoadingProgress(overallFraction, progressLabel);
        }

        // Yield briefly so the UI can repaint the spinner.
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    _updateLoadingProgress(0.93, progressLabel);
    encoder.close();
    return tempZipFile;
  }

  Future<void> _exportToZip() async {
    try {
      await _showLoadingDialog("Exporting ZIP backup (data + photos)...");
      final File? tempZipFile = await _buildFullBackupZipToTemp(
        progressLabel: 'Exporting ZIP backup',
      );
      if (tempZipFile == null) return;

      _updateLoadingProgress(0.96, 'Exporting ZIP backup');
      final List<int> zipBytes = await tempZipFile.readAsBytes();

      _updateLoadingProgress(0.99, 'Exporting ZIP backup');
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save Full Backup Zip:',
        fileName: _fullBackupZipFileName,
        bytes: Uint8List.fromList(zipBytes),
      );

      _updateLoadingProgress(1.0, 'Exporting ZIP backup');

      _showSnackBar("ZIP Backup saved successfully!");
    } catch (e) {
      _showSnackBar("Export Error: $e");
    } finally {
      _hideLoadingDialog();
    }
  }

  // ---------------------------------------------------------
  // 4. NEW ZIP IMPORT (JSON + Photos)
  // ---------------------------------------------------------
  Future<void> _importFromZipFile(File zipFile) async {
    try {
      await _showLoadingDialog("Reading ZIP backup (data + photos)...");
      _resetProgressThrottle();
      _updateLoadingProgress(0.02, 'Reading ZIP backup');

      Uint8List bytes = await zipFile.readAsBytes();
      Archive archive = ZipDecoder().decodeBytes(bytes);
      _updateLoadingProgress(0.10, 'Reading ZIP backup');

      // Find and decode the JSON data
      ArchiveFile? jsonFile = archive.findFile('data/backup.json');
      if (jsonFile == null) {
        _hideLoadingDialog();
        _showSnackBar("Invalid Zip: backup.json missing");
        return;
      }
      String content = utf8.decode(jsonFile.content as List<int>);
      dynamic jsonData = jsonDecode(content);

      // Extract Images to app storage
      String localImgPath = await _getLocalImagesPath();
      int photoCount = 0;
      final List<ArchiveFile> imageFiles = archive
          .where((f) => f.isFile && f.name.startsWith('images/'))
          .cast<ArchiveFile>()
          .toList();
      final int totalImages = imageFiles.length;
      for (int i = 0; i < imageFiles.length; i++) {
        final file = imageFiles[i];
        final String filename = p.basename(file.name);
        if (filename.isEmpty) continue;

        File localFile = File(p.join(localImgPath, filename));
        await localFile.writeAsBytes(file.content as List<int>);
        photoCount++;

        if (totalImages > 0 &&
            (i == 0 || i == totalImages - 1 || i % 10 == 0)) {
          final double f = 0.10 + ((i + 1) / totalImages) * 0.20;
          _updateLoadingProgress(f, 'Extracting photos');
        }
      }

      _updateLoadingProgress(0.35, 'Reading ZIP backup');

      // Done with heavy file work; hide the reading dialog before confirm.
      _hideLoadingDialog();

      // Use the common import handler
      List<dynamic> vocabToProcess = jsonData['vocabulary'] ?? [];
      List<dynamic> idiomsToProcess = jsonData['idioms'] ?? [];
      List<dynamic> wordGroupsToProcess = [];
      if (jsonData is Map && jsonData['word_groups'] is List) {
        wordGroupsToProcess = jsonData['word_groups'] as List<dynamic>;
      }

      // Optional: restore sort word settings if present in backup
      Map<String, dynamic>? sortWordSettings;
      if (jsonData is Map && jsonData['sort_word_settings'] is Map) {
        sortWordSettings = Map<String, dynamic>.from(
          jsonData['sort_word_settings'],
        );
      }

      // Optional: restore quiz history if present in backup
      String? quizHistory;
      int? quizHistoryNext;
      if (jsonData is Map && jsonData['quiz_history'] != null) {
        quizHistory = jsonData['quiz_history'].toString();
      }
      if (jsonData is Map && jsonData['quiz_history_next_number'] != null) {
        final dynamic rawNext = jsonData['quiz_history_next_number'];
        if (rawNext is int) {
          quizHistoryNext = rawNext;
        } else {
          quizHistoryNext = int.tryParse(rawNext.toString());
        }
      }

      // --- Notes import ---
      List<dynamic> notesToProcess = [];
      if (jsonData is Map && jsonData['notes'] is List) {
        notesToProcess = jsonData['notes'] as List<dynamic>;
      }

      bool? confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Import ZIP Backup"),
          content: Text(
            "Found:\n- $photoCount photos\n- ${vocabToProcess.length} words\n- ${idiomsToProcess.length} idioms\n- ${wordGroupsToProcess.length} word groups\n- ${notesToProcess.length} notes\n\nContinue?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Import"),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _showLoadingDialog("Importing ZIP backup (data + photos)...");
        _resetProgressThrottle();
        try {
          _updateLoadingProgress(0.01, 'Importing settings');

          if (sortWordSettings != null) {
            if (sortWordSettings.containsKey('quiz_use_all_words')) {
              await _dbHelper.setPreference(
                'quiz_use_all_words',
                sortWordSettings['quiz_use_all_words'].toString(),
              );
            }
            if (sortWordSettings.containsKey('quiz_selected_word_ids')) {
              await _dbHelper.setPreference(
                'quiz_selected_word_ids',
                sortWordSettings['quiz_selected_word_ids'].toString(),
              );
            }
            if (sortWordSettings.containsKey('quiz_selected_word_group_id')) {
              await _dbHelper.setPreference(
                'quiz_selected_word_group_id',
                sortWordSettings['quiz_selected_word_group_id'].toString(),
              );
            }
          }

          if (quizHistory != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('quiz_history', quizHistory);
            if (quizHistoryNext != null) {
              await prefs.setInt('quiz_history_next_number', quizHistoryNext);
            }
          }

          _updateLoadingProgress(0.08, 'Importing data');

          int addedWords = await _processImport(
            vocabToProcess,
            DBHelper.tableVocab,
            'word',
            onProgress: (done, total) {
              final double f = 0.08 + (done / total) * 0.52;
              _updateLoadingProgress(f, 'Importing words ($done/$total)');
            },
          );
          int addedIdioms = await _processImport(
            idiomsToProcess,
            DBHelper.tableIdioms,
            'idiom',
            onProgress: (done, total) {
              final double f = 0.60 + (done / total) * 0.18;
              _updateLoadingProgress(f, 'Importing idioms ($done/$total)');
            },
          );
          int createdWordGroups = await _processWordGroupsImport(
            wordGroupsToProcess,
            onProgress: (done, total) {
              final double f = 0.78 + (done / total) * 0.10;
              _updateLoadingProgress(f, 'Importing word groups ($done/$total)');
            },
          );
          int addedNotes = await _processNotesImport(
            notesToProcess,
            onProgress: (done, total) {
              final double f = 0.88 + (done / total) * 0.10;
              _updateLoadingProgress(f, 'Importing notes ($done/$total)');
            },
          );

          _updateLoadingProgress(0.99, 'Finalizing import');

          _showSnackBar(
            "Import Success!\nAdded $addedWords words, $addedIdioms idioms, $createdWordGroups word groups, $addedNotes notes, and $photoCount photos.",
          );

          // --- Refresh notes page if open ---
          if (mounted) {
            // ignore: use_build_context_synchronously
            Navigator.of(context).popUntil((route) => true); // pop dialog
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("Notes updated!")));
          }
        } finally {
          _hideLoadingDialog();
        }
      }
    } catch (e) {
      _showSnackBar("Import Error: $e");
    } finally {
      _hideLoadingDialog();
    }
  }

  Future<void> _importFromZip() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.single.path != null) {
        File zipFile = File(result.files.single.path!);
        await _importFromZipFile(zipFile);
      }
    } catch (e) {
      _showSnackBar("Import Error: $e");
    }
  }

  // ---------------------------------------------------------
  // 5. GOOGLE DRIVE EXPORT/IMPORT (FULL ZIP)
  // ---------------------------------------------------------
  Future<void> _exportFullZipToGoogleDrive() async {
    try {
      final account = await _googleDriveService.ensureSignedIn(
        interactive: true,
      );
      if (account == null) {
        _showSnackBar("Google Drive sign-in cancelled");
        return;
      }

      await _showLoadingDialog("Preparing full backup for Google Drive...");

      _updateLoadingProgress(0.05, 'Preparing backup');
      final File? tempZipFile = await _buildFullBackupZipToTemp(
        progressLabel: 'Preparing backup',
      );
      if (tempZipFile == null) return;

      _updateLoadingProgress(0.01, 'Uploading to Google Drive (starting...)');
      await _googleDriveService.uploadFile(
        tempZipFile,
        _fullBackupZipFileName,
        onProgress: (fraction, sent, total) {
          final mbStr = total > 0
              ? 'Uploading to Google Drive (${(sent / (1024 * 1024)).toStringAsFixed(2)} MB / ${(total / (1024 * 1024)).toStringAsFixed(2)} MB)'
              : 'Uploading to Google Drive';
          final shownFraction = (fraction.isNaN || fraction < 0.01)
              ? 0.01
              : fraction.clamp(0.01, 1.0);
          _updateLoadingProgress(shownFraction, mbStr);
          // Debug print to verify callback is called
          // ignore: avoid_print
          print(
            '[DriveUploadProgress] $sent/$total bytes (${(fraction * 100).toStringAsFixed(1)}%)',
          );
        },
      );

      _showSnackBar("Backup uploaded to Google Drive!");
    } catch (e) {
      _showSnackBar("Google Drive Export Error: $e");
    } finally {
      _hideLoadingDialog();
    }
  }

  Future<void> _importFullZipFromGoogleDrive() async {
    File? downloaded;
    try {
      final account = await _googleDriveService.ensureSignedIn(
        interactive: true,
      );
      if (account == null) {
        _showSnackBar("Google Drive sign-in cancelled");
        return;
      }

      await _showLoadingDialog("Downloading backup from Google Drive...");
      final tempDir = await getTemporaryDirectory();
      final String savePath = p.join(tempDir.path, _fullBackupZipFileName);
      int lastTotal = 0;
      downloaded = await _googleDriveService.downloadFile(
        _fullBackupZipFileName,
        savePath,
        onProgress: (fraction, sent, total) {
          lastTotal = total > 0 ? total : lastTotal;
          final mbStr = lastTotal > 0
              ? 'Downloading from Google Drive (${(sent / (1024 * 1024)).toStringAsFixed(2)} MB / ${(lastTotal / (1024 * 1024)).toStringAsFixed(2)} MB)'
              : 'Downloading from Google Drive';
          final shownFraction = (fraction.isNaN || fraction < 0.01)
              ? 0.01
              : fraction.clamp(0.01, 1.0);
          _updateLoadingProgress(shownFraction, mbStr);
          // Debug print to verify callback is called
          // ignore: avoid_print
          print(
            '[DriveDownloadProgress] $sent/$lastTotal bytes (${(fraction * 100).toStringAsFixed(1)}%)',
          );
        },
      );
    } catch (e) {
      _showSnackBar("Google Drive Import Error: $e");
      return;
    } finally {
      _hideLoadingDialog();
    }

    if (downloaded == null) return;
    await _importFromZipFile(downloaded);
  }

  // Helper function shared by both Import methods
  Future<int> _processImport(
    List<dynamic> list,
    String tableName,
    String keyName, {
    void Function(int processed, int total)? onProgress,
  }) async {
    if (list.isEmpty) return 0;
    List<Map<String, dynamic>> existingData = await _dbHelper.queryAll(
      tableName,
    );
    Set<String> existingKeys = existingData
        .map((e) => e[keyName].toString().toLowerCase().trim())
        .toSet();

    int addedCount = 0;
    int processed = 0;
    final int total = list.length;
    for (var item in list) {
      processed++;
      Map<String, dynamic> row = Map<String, dynamic>.from(item);
      if (row.containsKey(keyName)) {
        String keyInJson = row[keyName].toString().toLowerCase().trim();
        if (!existingKeys.contains(keyInJson)) {
          row.remove('id');
          await _dbHelper.insert(row, tableName);
          existingKeys.add(keyInJson);
          addedCount++;
        }
      }

      if (onProgress != null && total > 0) {
        if (processed == 1 || processed == total || processed % 50 == 0) {
          onProgress(processed, total);
        }
      }
    }

    onProgress?.call(total, total);
    return addedCount;
  }

  // --- WORD GROUP EXPORT/IMPORT HELPERS ---

  // Build a portable representation of word groups referencing words by text,
  // so we can safely restore them on another device where IDs differ.
  Future<List<Map<String, dynamic>>> _buildWordGroupsPayload(
    List<Map<String, dynamic>> vocabData,
  ) async {
    if (vocabData.isEmpty) return [];

    // Map word IDs to their text for quick lookup
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

  // Restore word groups from backup, matching words by their text.
  Future<int> _processWordGroupsImport(
    List<dynamic> groups, {
    void Function(int processed, int total)? onProgress,
  }) async {
    if (groups.isEmpty) return 0;

    // Build lookup from normalized word text to its current DB id
    final List<Map<String, dynamic>> allWords = await _dbHelper.queryAll(
      DBHelper.tableVocab,
    );
    final Map<String, int> wordKeyToId = {};
    for (final Map<String, dynamic> row in allWords) {
      final dynamic idValue = row['id'];
      final dynamic wordValue = row['word'];
      if (idValue is int && wordValue != null) {
        final String key = wordValue.toString().toLowerCase().trim();
        if (key.isNotEmpty) {
          wordKeyToId[key] = idValue;
        }
      }
    }

    if (wordKeyToId.isEmpty) return 0;

    // Existing groups by normalized name
    final List<Map<String, dynamic>> existingGroups = await _dbHelper
        .getAllWordGroups();
    final Map<String, int> groupNameToId = {};
    for (final Map<String, dynamic> row in existingGroups) {
      final dynamic idValue = row['id'];
      final dynamic nameValue = row['name'];
      if (idValue is int && nameValue != null) {
        final String key = nameValue.toString().toLowerCase().trim();
        if (key.isNotEmpty) {
          groupNameToId[key] = idValue;
        }
      }
    }

    int createdGroups = 0;
    final int total = groups.length;
    int processed = 0;

    for (final dynamic raw in groups) {
      processed++;
      try {
        if (raw is! Map) continue;
        final dynamic nameValue = raw['name'];
        final dynamic wordsValue = raw['words'];

        if (nameValue == null || wordsValue is! List) continue;

        final String groupName = nameValue.toString().trim();
        if (groupName.isEmpty) continue;

        final String groupKey = groupName.toLowerCase();
        int groupId;
        if (groupNameToId.containsKey(groupKey)) {
          groupId = groupNameToId[groupKey]!;
        } else {
          groupId = await _dbHelper.insertWordGroup(groupName);
          groupNameToId[groupKey] = groupId;
          createdGroups++;
        }

        final Set<int> wordIds = {};
        for (final dynamic w in wordsValue) {
          if (w == null) continue;
          final String key = w.toString().toLowerCase().trim();
          if (key.isEmpty) continue;
          final int? wid = wordKeyToId[key];
          if (wid != null) {
            wordIds.add(wid);
          }
        }

        if (wordIds.isNotEmpty) {
          await _dbHelper.setGroupWords(groupId, wordIds);
        }
      } finally {
        if (onProgress != null && total > 0) {
          if (processed == 1 || processed == total || processed % 10 == 0) {
            onProgress(processed, total);
          }
        }
      }
    }

    onProgress?.call(total, total);

    return createdGroups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Backup & Restore"), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                "Full Backup (Online)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              _buildCard(
                "Auto Backup Preferences",
                "Set up automatic backups",
                Icons.schedule,
                Colors.indigo,
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BackupPreferencesPage(),
                    ),
                  );
                },
              ),
              // Google Drive account label
              _buildSvgCard(
                "Export Full to Google Drive",
                "Upload full backup ZIP to Drive",
                _googleDriveIconAsset,
                () async {
                  if (_googleAccount == null) {
                    await _googleDriveService.ensureSignedIn(interactive: true);
                    await _fetchGoogleAccount();
                  } else {
                    await _exportFullZipToGoogleDrive();
                  }
                },
              ),
              _buildSvgCard(
                "Import Full from Google Drive",
                "Download and restore the backup ZIP",
                _googleDriveIconAsset,
                () async {
                  if (_googleAccount == null) {
                    await _googleDriveService.ensureSignedIn(interactive: true);
                    await _fetchGoogleAccount();
                  } else {
                    await _importFullZipFromGoogleDrive();
                  }
                },
              ),
              const SizedBox(height: 6),
              const Text(
                "Full Backup (Offline)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              _buildCard(
                "Export Full ZIP",
                "Save everything including images",
                Icons.all_inclusive,
                Colors.deepPurple,
                _exportToZip,
              ),
              _buildCard(
                "Import Full ZIP",
                "Restore everything from ZIP",
                Icons.unarchive,
                Colors.orange,
                _importFromZip,
              ),

              const Text(
                "Legacy Backup (Data Only)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              _buildCard(
                "Export JSON",
                "Save only words and idioms",
                Icons.file_upload,
                Colors.blue,
                _exportData,
              ),
              _buildCard(
                "Import JSON",
                "Restore from a JSON file",
                Icons.file_download,
                Colors.green,
                _importData,
              ),

              const Text(
                "Notes Backup (JSON)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              _buildCard(
                "Export Notes JSON",
                "Save all notes as JSON",
                Icons.note_add,
                Colors.teal,
                _exportNotesToJson,
              ),
              _buildCard(
                "Import Notes JSON",
                "Restore notes from JSON",
                Icons.note,
                Colors.indigo,
                _importNotesFromJson,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    String title,
    String sub,
    IconData icon,
    Color col,
    VoidCallback tap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: col,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title),
        subtitle: Text(sub),
        onTap: tap,
      ),
    );
  }

  Widget _buildSvgCard(
    String title,
    String sub,
    String assetPath,
    VoidCallback tap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF5F5F5),
          child: SvgPicture.asset(assetPath, width: 24, height: 24),
        ),
        title: Text(title),
        subtitle: Text(sub),
        onTap: tap,
      ),
    );
  }
}
