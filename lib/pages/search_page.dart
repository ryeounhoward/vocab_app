import 'dart:io';
import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'review_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final dbHelper = DBHelper();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  void _onSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    // Fetch from Vocabulary table only
    final words = await dbHelper.queryAll(DBHelper.tableVocab);

    final filteredWords = words
        .where(
          (item) => item['word'].toString().toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .map((e) => {...e, 'table': DBHelper.tableVocab})
        .toList();

    setState(() {
      _searchResults = filteredWords;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Search"),
        centerTitle: true,
        elevation: 0,
        // Match the design of the Manage Page Search Bar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: "Search",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    // State 1: Empty input (No text entered)
    if (_searchController.text.trim().isEmpty) {
      return const Center(child: Text("Search a word to display results"));
    }

    // State 2: No results found for the query
    if (_searchResults.isEmpty) {
      return const Center(child: Text("No search found"));
    }

    // State 3: List of results
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      // Add +1 to the length for the bottom spacing
      itemCount: _searchResults.length + 1,
      itemBuilder: (context, index) {
        // Return the SizedBox at the very end of the list
        if (index == _searchResults.length) {
          return const SizedBox(height: 80);
        }

        final item = _searchResults[index];
        final String title = item['word'] ?? "";
        final String subtitle = item['word_type'] ?? "";

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
              // Use pushAndRemoveUntil to clear the "loop"
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => ReviewPage(
                    selectedId: item['id'],
                    originTable: DBHelper.tableVocab,
                  ),
                ),
                (route) => route
                    .isFirst, // This keeps only the Main Menu and removes everything else
              );
            },
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
            title: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.indigo,
              ),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
          ),
        );
      },
    );
  }
}
