import 'dart:io';
import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'word_detail_page.dart';
import 'idiom_detail_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final dbHelper = DBHelper();

  // Data lists
  List<Map<String, dynamic>> _favoriteList = []; // Master list
  List<Map<String, dynamic>> _filteredList = []; // List shown in UI

  bool _isLoading = true;

  // Search Controller
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  void _loadFavorites() async {
    setState(() => _isLoading = true);

    // 1. Fetch Vocabulary Favorites
    final vocabData = await dbHelper.queryAll(DBHelper.tableVocab);
    final favVocab = vocabData.where((item) => item['is_favorite'] == 1).map((
      item,
    ) {
      return {...item, 'origin_table': DBHelper.tableVocab};
    }).toList();

    // 2. Fetch Idiom Favorites
    final idiomData = await dbHelper.queryAll(DBHelper.tableIdioms);
    final favIdioms = idiomData.where((item) => item['is_favorite'] == 1).map((
      item,
    ) {
      return {...item, 'origin_table': DBHelper.tableIdioms};
    }).toList();

    setState(() {
      _favoriteList = [...favVocab, ...favIdioms];
      _isLoading = false;
      // Initialize filtered list
      _runFilter(_searchController.text);
    });
  }

  // Search Logic
  void _runFilter(String enteredKeyword) {
    List<Map<String, dynamic>> results = [];
    if (enteredKeyword.isEmpty) {
      results = _favoriteList;
    } else {
      results = _favoriteList.where((item) {
        final bool isIdiom = item['origin_table'] == DBHelper.tableIdioms;
        // Check 'idiom' field for idioms, and 'word' field for vocabulary
        final String textToSearch = isIdiom
            ? (item['idiom'] ?? "").toString().toLowerCase()
            : (item['word'] ?? "").toString().toLowerCase();

        return textToSearch.contains(enteredKeyword.toLowerCase());
      }).toList();
    }

    setState(() {
      _filteredList = results;
    });
  }

  Future<void> _showRemoveModal(
    BuildContext context,
    int id,
    String displayName,
    String table,
  ) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Remove Favorite"),
          content: Text(
            "Are you sure you want to remove '$displayName' from your favorites?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("CANCEL"),
            ),
            TextButton(
              onPressed: () async {
                await dbHelper.toggleFavorite(id, false, table);
                _loadFavorites();
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
      appBar: AppBar(
        title: const Text("My Favorites"),
        centerTitle: true,
        // SEARCH BAR APPLIED HERE
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favoriteList.isEmpty
          ? const Center(child: Text("No favorites yet."))
          : _filteredList.isEmpty
          ? const Center(child: Text("No matches found."))
          : ListView.builder(
              itemCount: _filteredList.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final item = _filteredList[index];
                final bool isIdiom =
                    item['origin_table'] == DBHelper.tableIdioms;

                final String displayName = isIdiom
                    ? (item['idiom'] ?? "")
                    : (item['word'] ?? "");
                final String displaySub = isIdiom
                    ? "Idiom"
                    : (item['word_type'] ?? "");

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ListTile(
                    onTap: () {
                      if (isIdiom) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => IdiomDetailPage(item: item),
                          ),
                        ).then((_) => _loadFavorites());
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => WordDetailPage(item: item),
                          ),
                        ).then((_) => _loadFavorites());
                      }
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
                              child: Icon(isIdiom ? Icons.style : Icons.image),
                            ),
                    ),
                    title: Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    subtitle: Text(
                      displaySub,
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
                        _showRemoveModal(
                          context,
                          item['id'],
                          displayName,
                          item['origin_table'],
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
