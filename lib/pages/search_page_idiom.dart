import 'dart:io';
import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'idiom_review_page.dart';

class SearchPageIdiom extends StatefulWidget {
  const SearchPageIdiom({super.key});

  @override
  State<SearchPageIdiom> createState() => _SearchPageIdiomState();
}

class _SearchPageIdiomState extends State<SearchPageIdiom> {
  final dbHelper = DBHelper();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _showAllResults = false;
  bool _filterActive = false;
  String? _groupName;
  bool _hasGroupFilter = false;
  String _sortOrder = 'az';
  int? _activeGroupId;

  @override
  void initState() {
    super.initState();
    _onSearch('');
  }

  void _onSearch(String query) async {
    setState(() => _isSearching = true);

    // Fetch from Idioms tabler
    final idioms = await dbHelper.queryAll(DBHelper.tableIdioms);

    final prefs = await SharedPreferences.getInstance();
    final bool useAllIdioms = prefs.getBool('quiz_use_all_idioms') ?? true;
    final List<String> storedIds =
        prefs.getStringList('quiz_selected_idiom_ids') ?? const <String>[];
    final Set<int> selectedIds = storedIds
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .toSet();
    final int? groupId = prefs.getInt('quiz_selected_idiom_group_id');

    Set<int>? allowedIds;
    bool filterActive = false;
    if (groupId != null) {
      allowedIds = await dbHelper.getIdiomIdsForGroup(groupId);
      filterActive = true;
      _hasGroupFilter = true;
      final groups = await dbHelper.getAllIdiomGroups();
      final group = groups.firstWhere(
        (g) => g['id'] == groupId,
        orElse: () => <String, dynamic>{},
      );
      final name = (group['name'] ?? '').toString().trim();
      _groupName = name.isEmpty ? null : name;
    } else if (!useAllIdioms) {
      allowedIds = selectedIds;
      filterActive = true;
      _groupName = null;
      _hasGroupFilter = false;
    } else {
      _hasGroupFilter = false;
    }

    final String normalized = query.trim().toLowerCase();
    final bool hasQuery = normalized.isNotEmpty;

    final filtered = idioms
        .where((item) {
          if (!hasQuery) return true;
          return item['idiom'].toString().toLowerCase().contains(normalized);
        })
        .map((e) {
          final int id = e['id'] as int? ?? -1;
          final bool isInGroup =
              !filterActive || (allowedIds?.contains(id) ?? false);
          return {...e, '_isInGroup': isInGroup};
        })
        .where(
          (item) =>
              _showAllResults || !filterActive || (item['_isInGroup'] as bool),
        )
        .toList();

    filtered.sort((a, b) {
      final String aIdiom = (a['idiom'] ?? '').toString().toLowerCase();
      final String bIdiom = (b['idiom'] ?? '').toString().toLowerCase();
      final int cmp = aIdiom.compareTo(bIdiom);
      return _sortOrder == 'az' ? cmp : -cmp;
    });

    final Set<int> resultIds = filtered
        .map((e) => e['id'])
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    final groupsByIdiomId = await dbHelper.getIdiomGroupsForIdiomIds(resultIds);

    final List<Map<String, dynamic>> withGroups = filtered.map((e) {
      final int id = e['id'] as int? ?? -1;
      return {
        ...e,
        '_groups': groupsByIdiomId[id] ?? const <Map<String, dynamic>>[],
      };
    }).toList();

    setState(() {
      _searchResults = withGroups;
      _isSearching = false;
      _filterActive = filterActive;
      _activeGroupId = groupId;
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Search"),
        centerTitle: true,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    focusNode: _searchFocus,
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
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _sortOrder == 'az' ? 'Ascending' : 'Descending',
                  icon: Icon(
                    _sortOrder == 'az'
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                  ),
                  onPressed: () {
                    setState(() {
                      _sortOrder = _sortOrder == 'az' ? 'za' : 'az';
                    });
                    _onSearch(_searchController.text);
                  },
                ),
              ],
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

    final bool showToggle = _filterActive;

    return Column(
      children: [
        if (showToggle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show all results'),
              subtitle: const Text('Shows results from the group.'),
              activeThumbColor: Colors.indigo,
              value: _showAllResults,
              onChanged: (val) {
                setState(() => _showAllResults = val);
                _onSearch(_searchController.text);
              },
            ),
          ),
        Expanded(
          child: _searchResults.isEmpty
              ? const Center(child: Text("No search found"))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _searchResults.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _searchResults.length) {
                      return const SizedBox(height: 80);
                    }

                    final item = _searchResults[index];
                    final String title = item['idiom'] ?? "";
                    final bool isInGroup =
                        (item['_isInGroup'] as bool?) ?? true;
                    final List<Map<String, dynamic>> groups =
                        (item['_groups'] as List?)
                            ?.whereType<Map>()
                            .map((g) {
                              final int? id = g['id'] as int?;
                              final String name = (g['name'] ?? '')
                                  .toString()
                                  .trim();
                              return <String, dynamic>{'id': id, 'name': name};
                            })
                            .where((g) {
                              final int? id = g['id'] as int?;
                              final String name = (g['name'] ?? '')
                                  .toString()
                                  .trim();
                              return id != null && name.isNotEmpty;
                            })
                            .toList() ??
                        const <Map<String, dynamic>>[];

                    final List<Map<String, dynamic>> orderedGroups =
                        List<Map<String, dynamic>>.from(groups);
                    orderedGroups.sort((a, b) {
                      final int? aId = a['id'] as int?;
                      final int? bId = b['id'] as int?;

                      if (_activeGroupId != null) {
                        final bool aSelected = aId == _activeGroupId;
                        final bool bSelected = bId == _activeGroupId;
                        if (aSelected != bSelected) {
                          return aSelected ? -1 : 1;
                        }
                      }

                      final String aName = (a['name'] ?? '')
                          .toString()
                          .toLowerCase();
                      final String bName = (b['name'] ?? '')
                          .toString()
                          .toLowerCase();
                      return aName.compareTo(bName);
                    });
                    final List<Map<String, dynamic>> visibleGroups =
                        orderedGroups.take(2).toList();
                    final bool hasMoreGroups = orderedGroups.length > 2;

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
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  IdiomReviewPage(selectedId: item['id']),
                            ),
                            (route) => route.isFirst,
                          );
                        },
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Idiom",
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.indigo,
                              ),
                            ),
                            if (visibleGroups.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      for (
                                        int i = 0;
                                        i < visibleGroups.length;
                                        i++
                                      ) ...[
                                        if (i > 0)
                                          const TextSpan(
                                            text: ', ',
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 12,
                                            ),
                                          ),
                                        TextSpan(
                                          text: (visibleGroups[i]['name'] ?? '')
                                              .toString(),
                                          style: TextStyle(
                                            color: _activeGroupId == null
                                                ? Colors.blue
                                                : ((visibleGroups[i]['id']
                                                              as int?) ==
                                                          _activeGroupId
                                                      ? Colors.blue
                                                      : Colors.redAccent),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                      if (hasMoreGroups)
                                        const TextSpan(
                                          text: ', …',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
