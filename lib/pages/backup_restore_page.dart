import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // Required for Uint8List
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../database/db_helper.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final DBHelper _dbHelper = DBHelper();

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportData() async {
    try {
      // 1. Fetch data from both tables
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

      // 2. Create the backup structure
      Map<String, dynamic> backupData = {
        "version": 1,
        "vocabulary": vocabData,
        "idioms": idiomData,
      };

      // 3. Convert JSON string to Bytes (required for the save dialog)
      String jsonString = jsonEncode(backupData);
      Uint8List bytes = Uint8List.fromList(utf8.encode(jsonString));

      // 4. Open the File Explorer "Save As" Dialog
      // This will let the user pick the Downloads/Documents folder directly
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select where to save your backup:',
        fileName: 'vocab_idioms_backup.json',
        bytes: bytes, // On Android/iOS, this handles writing the file for you
      );

      if (outputPath != null) {
        _showSnackBar("Backup saved successfully!");
      } else {
        // User canceled the picker
        _showSnackBar("Export canceled");
      }
    } catch (e) {
      _showSnackBar("Export Error: $e");
      debugPrint(e.toString());
    }
  }

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

        // Detect format: Is it the new Map format or old List format?
        if (jsonData is Map && jsonData.containsKey('vocabulary')) {
          vocabToProcess = jsonData['vocabulary'] ?? [];
          idiomsToProcess = jsonData['idioms'] ?? [];
        } else if (jsonData is List) {
          // Backward compatibility: treat old list backups as Vocabulary
          vocabToProcess = jsonData;
        }

        // Confirmation Dialog
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

          _showSnackBar(
            "Import Finished!\nAdded: $addedWords words, $addedIdioms idioms.",
          );
        }
      }
    } catch (e) {
      _showSnackBar("Import Failed: $e");
      debugPrint(e.toString());
    }
  }

  // Helper function to handle duplicates and insertion for any table
  Future<int> _processImport(
    List<dynamic> list,
    String tableName,
    String keyName,
  ) async {
    if (list.isEmpty) return 0;

    // Fetch existing keys (word or idiom) to prevent duplicates
    List<Map<String, dynamic>> existingData = await _dbHelper.queryAll(
      tableName,
    );
    Set<String> existingKeys = existingData
        .map((e) => e[keyName].toString().toLowerCase().trim())
        .toSet();

    int addedCount = 0;
    for (var item in list) {
      Map<String, dynamic> row = Map<String, dynamic>.from(item);
      if (row.containsKey(keyName)) {
        String keyInJson = row[keyName].toString().toLowerCase().trim();

        if (!existingKeys.contains(keyInJson)) {
          row.remove('id'); // Remove old ID
          await _dbHelper.insert(row, tableName);
          existingKeys.add(keyInJson);
          addedCount++;
        }
      }
    }
    return addedCount;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Backup & Restore"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              "Manage your data across devices. Exporting creates a single file containing both your Vocabulary and Idioms.",
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.file_upload, color: Colors.white),
              ),
              title: const Text("Export Backup"),
              subtitle: const Text("Save words and idioms to a JSON file"),
              onTap: _exportData,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.green,
                child: Icon(Icons.file_download, color: Colors.white),
              ),
              title: const Text("Import Backup"),
              subtitle: const Text("Restore data from a JSON file"),
              onTap: _importData,
            ),
          ),
        ],
      ),
    );
  }
}
