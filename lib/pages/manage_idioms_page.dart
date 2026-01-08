import 'dart:io';
import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'add_edit_idiom_page.dart';

class ManageIdiomsPage extends StatefulWidget {
  const ManageIdiomsPage({super.key});

  @override
  State<ManageIdiomsPage> createState() => _ManageIdiomsPageState();
}

class _ManageIdiomsPageState extends State<ManageIdiomsPage> {
  List<Map<String, dynamic>> _allIdioms = [];
  List<Map<String, dynamic>> _filteredList = [];

  final dbHelper = DBHelper();
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  // Keep track of keys for each item to control them from here
  final Map<int, GlobalKey<SlidingTitleState>> _titleKeys = {};
  GlobalKey<SlidingTitleState>? _activeKey;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() async {
    setState(() => _isLoading = true);
    try {
      final data = await dbHelper.queryAll(DBHelper.tableIdioms);
      setState(() {
        _allIdioms = data;
        _filteredList = data;
      });
    } catch (e) {
      debugPrint("DATABASE ERROR: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _runFilter(String enteredKeyword) {
    List<Map<String, dynamic>> results = [];
    if (enteredKeyword.isEmpty) {
      results = _allIdioms;
    } else {
      results = _allIdioms
          .where(
            (item) => item["idiom"].toString().toLowerCase().contains(
              enteredKeyword.toLowerCase(),
            ),
          )
          .toList();
    }
    setState(() => _filteredList = results);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    int id,
    String idiom,
  ) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Delete"),
          content: Text("Are you sure you want to delete '$idiom'?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            TextButton(
              onPressed: () async {
                await dbHelper.delete(id, DBHelper.tableIdioms);
                _refreshData();
                if (mounted) Navigator.pop(context);
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
        title: const Text("Manage Idioms"),
        elevation: 0,
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
      body: _allIdioms.isEmpty
          ? const Center(child: Text("No idioms found. Please add some first."))
          : _filteredList.isEmpty
          ? const Center(child: Text("No results found."))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _filteredList.length + 1,
              itemBuilder: (context, index) {
                if (index == _filteredList.length) {
                  return const SizedBox(height: 80); // Space after last card
                }

                final item = _filteredList[index];
                final int itemId = item['id'];

                // Retrieve or create a GlobalKey for this specific idiom ID
                final titleKey = _titleKeys.putIfAbsent(
                  itemId,
                  () => GlobalKey<SlidingTitleState>(),
                );

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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    onTap: () {
                      // 1. If another card is already scrolling, reset it first
                      if (_activeKey != null && _activeKey != titleKey) {
                        _activeKey?.currentState?.resetScroll();
                      }

                      // 2. Toggle scroll on the current card (handles "click again to reset")
                      titleKey.currentState?.toggleScroll();

                      // 3. Update the active key reference
                      _activeKey = titleKey;
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
                              child: const Icon(
                                Icons.image,
                                color: Colors.grey,
                              ),
                            ),
                    ),
                    title: SlidingTitle(
                      key: titleKey,
                      text: item['idiom'] ?? "",
                    ),
                    subtitle: const Text(
                      "Idiom",
                      style: TextStyle(
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
                          onPressed: () => _confirmDelete(
                            context,
                            itemId,
                            item['idiom'] ?? "this idiom",
                          ),
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
      MaterialPageRoute(
        builder: (context) => AddEditIdiomPage(idiomItem: item),
      ),
    );
    _refreshData();
  }
}

class SlidingTitle extends StatefulWidget {
  final String text;
  const SlidingTitle({super.key, required this.text});

  @override
  State<SlidingTitle> createState() => SlidingTitleState();
}

class SlidingTitleState extends State<SlidingTitle> {
  final ScrollController _scrollController = ScrollController();
  bool _isScrolling = false;

  /// Resets the scroll position immediately to normal
  void resetScroll() {
    if (!mounted) return;
    _scrollController.jumpTo(0);
    setState(() => _isScrolling = false);
  }

  /// Starts scrolling or resets if already scrolling
  void toggleScroll() {
    if (_isScrolling) {
      resetScroll();
    } else {
      _startScrolling();
    }
  }

  void _startScrolling() async {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent <= 0) return;

    setState(() => _isScrolling = true);

    // Faster speed: 60ms per character
    int durationMs = (widget.text.length * 60).toInt();
    if (durationMs < 600) durationMs = 600;

    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.linear,
    );

    await Future.delayed(const Duration(milliseconds: 600));

    // Return to start
    if (_isScrolling && mounted) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
      if (mounted) setState(() => _isScrolling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        overflow: _isScrolling ? TextOverflow.visible : TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
