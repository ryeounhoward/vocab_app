import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _exportData() async {
    try {
      // 1. Get Data
      List<Map<String, dynamic>> data = await _dbHelper.queryAll();
      if (data.isEmpty) {
        _showSnackBar("No data to export");
        return;
      }

      // 2. Convert to JSON
      String jsonString = jsonEncode(data);

      // 3. Save to a temporary location first
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/vocabulary_backup.json';
      final file = File(filePath);
      await file.writeAsString(jsonString);

      // 4. Use Share Plus to let user "Save to Device"
      // This works on all Android versions and avoids "Path not found" errors
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'Vocabulary Backup',
      );

      if (result.status == ShareResultStatus.success) {
        _showSnackBar("Export process completed!");
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
      List<dynamic> jsonData = jsonDecode(content);

      // 1. Fetch current words from the database to compare
      List<Map<String, dynamic>> existingData = await _dbHelper.queryAll();
      
      // We use a Set for faster lookup and convert to lowercase for accurate checking
      Set<String> existingWords = existingData
          .map((e) => e['word'].toString().toLowerCase().trim())
          .toSet();

      // Confirmation Dialog
      bool? confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Import Data"),
          content: Text("Total words in file: ${jsonData.length}\nOnly new words will be added. Continue?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Import")),
          ],
        ),
      );

      if (confirm == true) {
        int addedCount = 0;
        int skippedCount = 0;

        for (var item in jsonData) {
          Map<String, dynamic> row = Map<String, dynamic>.from(item);
          
          // Ensure the word exists in the JSON item
          if (row.containsKey('word')) {
            String wordInJson = row['word'].toString().toLowerCase().trim();

            // 2. Check if the word already exists in the database
            if (!existingWords.contains(wordInJson)) {
              row.remove('id'); // Remove old ID to let DB generate a new one
              await _dbHelper.insert(row);
              
              // Add to our Set to prevent duplicates if the SAME word 
              // appears twice in the same JSON file
              existingWords.add(wordInJson); 
              addedCount++;
            } else {
              skippedCount++;
            }
          }
        }

        _showSnackBar("Import Finished: $addedCount added, $skippedCount skipped (duplicates).");
      }
    }
  } catch (e) {
    _showSnackBar("Import Failed: $e");
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Backup & Restore")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_upload, color: Colors.blue),
              title: const Text("Export JSON"),
              subtitle: const Text("Save data to File Manager"),
              onTap: _exportData,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_download, color: Colors.green),
              title: const Text("Import JSON"),
              subtitle: const Text("Load data from File Manager"),
              onTap: _importData,
            ),
          ),
        ],
      ),
    );
  }
}