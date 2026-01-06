import 'dart:io';
import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'word_detail_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final dbHelper = DBHelper();
  List<Map<String, dynamic>> _favoriteList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  void _loadFavorites() async {
    final data = await dbHelper.queryAll();
    setState(() {
      _favoriteList = data.where((item) => item['is_favorite'] == 1).toList();
      _isLoading = false;
    });
  }

  // --- THE MODAL DIALOG FOR REMOVAL ---
  Future<void> _showRemoveModal(
    BuildContext context,
    int id,
    String word,
  ) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Remove Favorite"),
          content: Text(
            "Are you sure you want to remove '$word' from your favorites?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("CANCEL"),
            ),
            TextButton(
              onPressed: () async {
                // Update database to unstar
                await dbHelper.toggleFavorite(id, false);
                _loadFavorites(); // Refresh the list
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text(
                "REMOVE",
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Favorites"), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favoriteList.isEmpty
          ? const Center(child: Text("No favorite words yet."))
          : ListView.builder(
              itemCount: _favoriteList.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final item = _favoriteList[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ListTile(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WordDetailPage(item: item),
                        ),
                      ).then((_) => _loadFavorites());
                    },
                    contentPadding: const EdgeInsets.all(10),
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
                              child: const Icon(Icons.image),
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
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.star,
                        color: Colors.orange,
                        size: 28,
                      ),
                      onPressed: () {
                        // Open the modal instead of immediate removal
                        _showRemoveModal(
                          context,
                          item['id'],
                          item['word'] ?? "",
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
