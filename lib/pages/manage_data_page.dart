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
  // Original data from DB
  List<Map<String, dynamic>> _allVocab = [];
  // Data displayed in the list (filtered)
  List<Map<String, dynamic>> _filteredList = [];

  final dbHelper = DBHelper();
  bool _isLoading = true;

  // Controller for the search field
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() async {
    setState(() => _isLoading = true);
    final data = await dbHelper.queryAll();
    setState(() {
      _allVocab = data;
      // Initialize filtered list with all data
      _filteredList = data;
      _isLoading = false;
    });
    // If there was text in search bar, re-apply filter after refresh
    _runFilter(_searchController.text);
  }

  // This function is called whenever the text field changes
  void _runFilter(String enteredKeyword) {
    List<Map<String, dynamic>> results = [];
    if (enteredKeyword.isEmpty) {
      // If the search field is empty, show all items
      results = _allVocab;
    } else {
      // Filter based on the 'word' field
      results = _allVocab
          .where(
            (item) => item["word"].toString().toLowerCase().contains(
              enteredKeyword.toLowerCase(),
            ),
          )
          .toList();
    }

    setState(() {
      _filteredList = results;
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
                // ignore: use_build_context_synchronously
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Vocabulary"),
        elevation: 0,
        centerTitle: true,
        // SEARCH BAR ADDED HERE
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _runFilter(value),
              decoration: InputDecoration(
                hintText: "Search",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _runFilter('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _allVocab.isEmpty
          ? const Center(
              child: Text("No vocabulary found. Please add some first."),
            )
          : _filteredList.isEmpty
          ? const Center(child: Text("No results found."))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              // 1. Add +1 to the length
              itemCount: _filteredList.length + 1,
              itemBuilder: (context, index) {
                // 2. Check if this is the very last item in the count
                if (index == _filteredList.length) {
                  return const SizedBox(
                    height: 80,
                  ); // This appears AFTER the last card
                }

                final item = _filteredList[index];

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
                      child:
                          item['image_path'] != null && item['image_path'] != ""
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
                              child: const Icon(
                                Icons.image,
                                color: Colors.grey,
                              ),
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
