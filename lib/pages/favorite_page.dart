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

class _FavoritesPageState extends State<FavoritesPage>
    with WidgetsBindingObserver {
  final dbHelper = DBHelper();
  List<Map<String, dynamic>> _favoriteList = [];
  List<Map<String, dynamic>> _filteredList = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(
      this,
    ); // Listen for app background/foreground
    _loadFavorites();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Stop listening
    _searchController.dispose();
    super.dispose();
  }

  // Refresh when returning from another screen
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadFavorites();
  }

  // Refresh when coming back from notification tray (App Resumed)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadFavorites();
    }
  }

  void _loadFavorites() async {
    // Only show spinner on first load to prevent flickering
    if (_favoriteList.isEmpty) setState(() => _isLoading = true);

    final vocabData = await dbHelper.queryAll(DBHelper.tableVocab);
    final favVocab = vocabData.where((item) => item['is_favorite'] == 1).map((
      item,
    ) {
      return {...item, 'origin_table': DBHelper.tableVocab};
    }).toList();

    final idiomData = await dbHelper.queryAll(DBHelper.tableIdioms);
    final favIdioms = idiomData.where((item) => item['is_favorite'] == 1).map((
      item,
    ) {
      return {...item, 'origin_table': DBHelper.tableIdioms};
    }).toList();

    if (mounted) {
      setState(() {
        _favoriteList = [...favVocab, ...favIdioms];
        _isLoading = false;
        _runFilter(_searchController.text);
      });
    }
  }

  void _runFilter(String enteredKeyword) {
    List<Map<String, dynamic>> results = [];
    if (enteredKeyword.isEmpty) {
      results = _favoriteList;
    } else {
      results = _favoriteList.where((item) {
        final bool isIdiom = item['origin_table'] == DBHelper.tableIdioms;
        final String textToSearch = isIdiom
            ? (item['idiom'] ?? "").toString().toLowerCase()
            : (item['word'] ?? "").toString().toLowerCase();
        return textToSearch.contains(enteredKeyword.toLowerCase());
      }).toList();
    }
    setState(() => _filteredList = results);
  }

  Future<void> _showRemoveModal(
    BuildContext context,
    int id,
    String displayName,
    String table,
  ) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove Favorite"),
        content: Text(
          "Are you sure you want to remove '$displayName' from favorites?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () async {
              await dbHelper.toggleFavorite(id, false, table);
              _loadFavorites();
              // ignore: use_build_context_synchronously
              if (mounted) Navigator.pop(context);
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Favorites"),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: _runFilter,
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
              // Add +1 to the count to make room for the SizedBox
              itemCount: _filteredList.length + 1,
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                // Check if this is the extra item at the end
                if (index == _filteredList.length) {
                  return const SizedBox(height: 40);
                }

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
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    onTap: () {
                      Widget page = isIdiom
                          ? IdiomDetailPage(item: item)
                          : WordDetailPage(item: item);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => page),
                      ).then((_) => _loadFavorites());
                    },
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
                      onPressed: () => _showRemoveModal(
                        context,
                        item['id'],
                        displayName,
                        item['origin_table'],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
