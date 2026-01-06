import 'dart:io';
import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'add_edit_page.dart';

class ManageDataPage extends StatefulWidget {
  const ManageDataPage({super.key});

  @override
  State<ManageDataPage> createState() => _ManageDataPageState();
}

class _ManageDataPageState extends State<ManageDataPage> {
  List<Map<String, dynamic>> _vocabList = [];
  final dbHelper = DBHelper();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() async {
    setState(() => _isLoading = true);
    final data = await dbHelper.queryAll();
    setState(() {
      _vocabList = data;
      _isLoading = false;
    });
  }

  Future<void> _confirmDelete(BuildContext context, int id, String word) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Delete"),
          content: Text("Are you sure you want to delete '$word'?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("CANCEL"),
            ),
            TextButton(
              onPressed: () async {
                await dbHelper.delete(id);
                _refreshData();
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text("DELETE", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Loading State Consistency
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 2. Empty State Consistency (No AppBar, Perfect Center)
    if (_vocabList.isEmpty) {
      return Scaffold(
        body: const Center(
          child: Text("No vocabulary found. Please add some first."),
        ),
        // We keep the FAB here so the user can actually add their first word
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
          onPressed: () => _navigateToForm(null),
        ),
      );
    }

    // 3. Data Loaded State (Consistent tiles with Favorites Page)
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Vocabulary"),
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _vocabList.length,
        itemBuilder: (context, index) {
          final item = _vocabList[index];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: item['image_path'] != null && item['image_path'] != ""
                    ? Image.file(
                        File(item['image_path']),
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey[200],
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
              ),
              title: Text(
                item['word'] ?? "",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              subtitle: Text(
                item['word_type'] ?? "",
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.indigo,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _navigateToForm(item),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      _confirmDelete(
                        context,
                        item['id'],
                        item['word'] ?? "this word",
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
        onPressed: () => _navigateToForm(null),
      ),
    );
  }

  void _navigateToForm(Map<String, dynamic>? item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddEditPage(vocabItem: item)),
    );
    _refreshData();
  }
}
