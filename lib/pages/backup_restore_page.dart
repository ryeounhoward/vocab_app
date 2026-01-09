import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart'; // Use archive.dart for better compatibility
import 'package:path/path.dart' as p;
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      List<Map<String, dynamic>> vocabData = await _dbHelper.queryAll(DBHelper.tableVocab);
      List<Map<String, dynamic>> idiomData = await _dbHelper.queryAll(DBHelper.tableIdioms);

      if (vocabData.isEmpty && idiomData.isEmpty) {
        _showSnackBar("No data found to export");
        return;
      }

      Map<String, dynamic> backupData = {
        "version": 1,
        "vocabulary": vocabData,
        "idioms": idiomData,
      };

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
    }
  }

  // ---------------------------------------------------------
  // 2. ORIGINAL JSON IMPORT (Your Old Code)
  // ---------------------------------------------------------
  Future<void> _importData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        dynamic jsonData = jsonDecode(content);

        List<dynamic> vocabToProcess = [];
        List<dynamic> idiomsToProcess = [];

        if (jsonData is Map && jsonData.containsKey('vocabulary')) {
          vocabToProcess = jsonData['vocabulary'] ?? [];
          idiomsToProcess = jsonData['idioms'] ?? [];
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
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Import")),
            ],
          ),
        );

        if (confirm == true) {
          int addedWords = await _processImport(vocabToProcess, DBHelper.tableVocab, 'word');
          int addedIdioms = await _processImport(idiomsToProcess, DBHelper.tableIdioms, 'idiom');
          _showSnackBar("Import Finished!\nAdded: $addedWords words, $addedIdioms idioms.");
        }
      }
    } catch (e) {
      _showSnackBar("Import Failed: $e");
    }
  }

  // ---------------------------------------------------------
  // 3. NEW ZIP EXPORT (JSON + Photos)
  // ---------------------------------------------------------
  Future<void> _exportToZip() async {
    try {
      List<Map<String, dynamic>> vocabData = await _dbHelper.queryAll(DBHelper.tableVocab);
      List<Map<String, dynamic>> idiomData = await _dbHelper.queryAll(DBHelper.tableIdioms);

      if (vocabData.isEmpty && idiomData.isEmpty) {
        _showSnackBar("No data found to export");
        return;
      }

      var archive = Archive();

      // Add Database JSON to ZIP
      String jsonString = jsonEncode({
        "version": 1,
        "vocabulary": vocabData,
        "idioms": idiomData,
      });
      List<int> jsonBytes = utf8.encode(jsonString);
      archive.addFile(ArchiveFile('data/backup.json', jsonBytes.length, jsonBytes));

      // Add Photos from app folder to ZIP
      String imagesPath = await _getLocalImagesPath();
      Directory imgDir = Directory(imagesPath);
      if (await imgDir.exists()) {
        List<FileSystemEntity> files = imgDir.listSync();
        for (var file in files) {
          if (file is File) {
            List<int> bytes = await file.readAsBytes();
            archive.addFile(ArchiveFile('images/${p.basename(file.path)}', bytes.length, bytes));
          }
        }
      }

      List<int>? zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) return;

      await FilePicker.platform.saveFile(
        dialogTitle: 'Save Full Backup Zip:',
        fileName: 'app_full_backup.zip',
        bytes: Uint8List.fromList(zipBytes),
      );

      _showSnackBar("ZIP Backup saved successfully!");
    } catch (e) {
      _showSnackBar("Export Error: $e");
    }
  }

  // ---------------------------------------------------------
  // 4. NEW ZIP IMPORT (JSON + Photos)
  // ---------------------------------------------------------
  Future<void> _importFromZip() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.single.path != null) {
        File zipFile = File(result.files.single.path!);
        Uint8List bytes = await zipFile.readAsBytes();
        Archive archive = ZipDecoder().decodeBytes(bytes);
        
        // Find and decode the JSON data
        ArchiveFile? jsonFile = archive.findFile('data/backup.json');
        if (jsonFile == null) {
          _showSnackBar("Invalid Zip: backup.json missing");
          return;
        }
        String content = utf8.decode(jsonFile.content as List<int>);
        dynamic jsonData = jsonDecode(content);

        // Extract Images to app storage
        String localImgPath = await _getLocalImagesPath();
        int photoCount = 0;
        for (var file in archive) {
          if (file.isFile && file.name.startsWith('images/')) {
            String filename = p.basename(file.name);
            if (filename.isNotEmpty) {
              File localFile = File(p.join(localImgPath, filename));
              await localFile.writeAsBytes(file.content as List<int>);
              photoCount++;
            }
          }
        }

        // Use the common import handler
        List<dynamic> vocabToProcess = jsonData['vocabulary'] ?? [];
        List<dynamic> idiomsToProcess = jsonData['idioms'] ?? [];

        bool? confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Import ZIP Backup"),
            content: Text("Found:\n- $photoCount photos\n- ${vocabToProcess.length} words\n- ${idiomsToProcess.length} idioms\n\nContinue?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Import")),
            ],
          ),
        );

        if (confirm == true) {
          int addedWords = await _processImport(vocabToProcess, DBHelper.tableVocab, 'word');
          int addedIdioms = await _processImport(idiomsToProcess, DBHelper.tableIdioms, 'idiom');
          _showSnackBar("Import Success!\nAdded $addedWords words, $addedIdioms idioms, and $photoCount photos.");
        }
      }
    } catch (e) {
      _showSnackBar("Import Error: $e");
    }
  }

  // Helper function shared by both Import methods
  Future<int> _processImport(List<dynamic> list, String tableName, String keyName) async {
    if (list.isEmpty) return 0;
    List<Map<String, dynamic>> existingData = await _dbHelper.queryAll(tableName);
    Set<String> existingKeys = existingData.map((e) => e[keyName].toString().toLowerCase().trim()).toSet();

    int addedCount = 0;
    for (var item in list) {
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
          const Text("Full Backup (Database + Photos)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 10),
          _buildCard("Export Full ZIP", "Save everything including images", Icons.all_inclusive, Colors.deepPurple, _exportToZip),
          _buildCard("Import Full ZIP", "Restore everything from ZIP", Icons.unarchive, Colors.orange, _importFromZip),
          
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider()),
          
          const Text("Legacy Backup (Data Only)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 10),
          _buildCard("Export JSON", "Save only words and idioms", Icons.file_upload, Colors.blue, _exportData),
          _buildCard("Import JSON", "Restore from a JSON file", Icons.file_download, Colors.green, _importData),
        ],
      ),
    );
  }

  Widget _buildCard(String title, String sub, IconData icon, Color col, VoidCallback tap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: col, child: Icon(icon, color: Colors.white)),
        title: Text(title),
        subtitle: Text(sub),
        onTap: tap,
      ),
    );
  }
}