import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import 'add_edit_page.dart';
import 'word_detail_page.dart';

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
  bool _isAscending = true; // sort order for list
  bool _showTenseByDefault = false;

  // Keep track of keys for each item to control them from here
  final Map<int, GlobalKey<SlidingTitleState>> _titleKeys = {};
  final Map<int, GlobalKey<SlidingTitleState>> _subtitleKeys = {};
  int? _activeItemId;

  // Controller for the search field
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refreshData();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showTenseByDefault = prefs.getBool('show_tenses_by_default') ?? false;
    });
  }

  Future<void> _updateTenseDefault(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_tenses_by_default', value);
    if (!mounted) return;
    setState(() {
      _showTenseByDefault = value;
    });
  }

  void _refreshData() async {
    setState(() => _isLoading = true);
    final data = await dbHelper.queryAll();
    setState(() {
      // Make a mutable copy of the read-only query result
      _allVocab = List<Map<String, dynamic>>.from(data);
      // Initialize filtered list with a separate mutable copy
      _filteredList = List<Map<String, dynamic>>.from(_allVocab);
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
      // Use a fresh mutable copy so sorting doesn't touch the original
      results = List<Map<String, dynamic>>.from(_allVocab);
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
    _applySort(results);
    setState(() {
      _filteredList = results;
    });
  }

  void _applySort(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final String aName = (a['word'] ?? '').toString().toLowerCase();
      final String bName = (b['word'] ?? '').toString().toLowerCase();

      final int cmp = aName.compareTo(bName);
      return _isAscending ? cmp : -cmp;
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _isAscending = !_isAscending;
      _runFilter(_searchController.text);
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () =>
                            _updateTenseDefault(!_showTenseByDefault),
                        icon: Icon(
                          _showTenseByDefault
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: _showTenseByDefault
                              ? Colors.indigo
                              : Colors.grey,
                        ),
                        label: Text(
                          _showTenseByDefault
                              ? 'Show Forms & Tenses: On'
                              : 'Show Forms & Tenses: Off',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _toggleSortOrder,
                        icon: Icon(
                          _isAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 18,
                        ),
                        label: Text(
                          _isAscending ? 'Ascending' : 'Descending',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
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
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    WordDetailPage(item: item),
                              ),
                            );
                          },
                          onLongPress: () {
                            final int itemId = item['id'];

                            // Retrieve or create a GlobalKey for this specific word ID
                            final titleKey = _titleKeys.putIfAbsent(
                              itemId,
                              () => GlobalKey<SlidingTitleState>(),
                            );
                            final subtitleKey = _subtitleKeys.putIfAbsent(
                              itemId,
                              () => GlobalKey<SlidingTitleState>(),
                            );

                            // 1. If another card is already scrolling, reset it first
                            if (_activeItemId != null &&
                                _activeItemId != itemId) {
                              final prevTitleKey = _titleKeys[_activeItemId!];
                              final prevSubtitleKey =
                                  _subtitleKeys[_activeItemId!];
                              prevTitleKey?.currentState?.resetScroll();
                              prevSubtitleKey?.currentState?.resetScroll();
                            }

                            // 2. Toggle scroll on the current card (handles "press again to reset")
                            titleKey.currentState?.toggleScroll();
                            subtitleKey.currentState?.toggleScroll();

                            // 3. Update the active item reference
                            _activeItemId = itemId;
                          },
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child:
                                item['image_path'] != null &&
                                    item['image_path'] != ""
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
                            key: _titleKeys.putIfAbsent(
                              item['id'],
                              () => GlobalKey<SlidingTitleState>(),
                            ),
                            text: item['word'] ?? "",
                          ),
                          subtitle: SlidingTitle(
                            key: _subtitleKeys.putIfAbsent(
                              item['id'],
                              () => GlobalKey<SlidingTitleState>(),
                            ),
                            text: item['word_type'] ?? "",
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.indigo,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _navigateToForm(item),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
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
                ),
              ],
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

class SlidingTitle extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const SlidingTitle({super.key, required this.text, this.style});

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
        style:
            widget.style ??
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
