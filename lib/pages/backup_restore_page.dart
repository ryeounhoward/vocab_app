import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../db_helper.dart'; // Ensure this points to your DBHelper file

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final DBHelper _dbHelper = DBHelper();

  // EXPORT DATA TO JSON
  Future<void> _exportData() async {
    try {
      // 1. Fetch data from DB
      List<Map<String, dynamic>> data = await _dbHelper.queryAll();
      
      if (data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No data to export")),
        );
        return;
      }

      // 2. Convert to JSON string
      String jsonString = jsonEncode(data);

      // 3. Save to temporary file
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/vocabulary_backup.json');
      await file.writeAsString(jsonString);

      // 4. Share the file
      await Share.shareXFiles([XFile(file.path)], text: 'My Vocabulary Backup');
    } catch (e) {
      debugPrint("Export Error: $e");
    }
  }

  // IMPORT DATA FROM JSON
  Future<void> _importData() async {
    try {
      // 1. Pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();

        // 2. Parse JSON
        List<dynamic> jsonData = jsonDecode(content);

        // 3. Confirm with user
        bool? confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Import Data"),
            content: Text("This will add ${jsonData.length} words to your list. Continue?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Import")),
            ],
          ),
        );

        if (confirm == true) {
          // 4. Insert into DB
          for (var item in jsonData) {
            // Remove 'id' so SQFlite generates new IDs and avoids conflicts
            Map<String, dynamic> row = Map<String, dynamic>.from(item);
            row.remove('id'); 
            await _dbHelper.insert(row);
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Import Successful!")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Import Failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Backup & Restore")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.upload_file, color: Colors.blue),
                title: const Text("Export Data"),
                subtitle: const Text("Save your vocabulary as a JSON file"),
                onTap: _exportData,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.download_file, color: Colors.green),
                title: const Text("Import Data"),
                subtitle: const Text("Load vocabulary from a JSON file"),
                onTap: _importData,
              ),
            ),
          ],
        ),
      ),
    );
  }
}