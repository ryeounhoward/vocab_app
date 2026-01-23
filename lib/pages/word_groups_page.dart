import 'package:flutter/material.dart';

import '../database/db_helper.dart';

class WordGroupsPage extends StatefulWidget {
  const WordGroupsPage({super.key});

  @override
  State<WordGroupsPage> createState() => _WordGroupsPageState();
}

class _WordGroupsPageState extends State<WordGroupsPage> {
  final DBHelper _dbHelper = DBHelper();

  bool _isLoading = true;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _allVocab = [];
  List<Map<String, dynamic>> _filteredVocab = [];

  final TextEditingController _searchController = TextEditingController();

  int? _currentGroupId;
  final Set<int> _selectedWordIds = {};
  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllWordGroups();
    final List<Map<String, dynamic>> vocab = await _dbHelper.queryAll(
      DBHelper.tableVocab,
    );

    int? initialGroupId;
    if (groups.isNotEmpty) {
      initialGroupId = groups.first['id'] as int?;
    }

    Set<int> wordIdsForInitial = {};
    if (initialGroupId != null) {
      wordIdsForInitial = await _dbHelper.getWordIdsForGroup(initialGroupId);
    }

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
      _allVocab = List<Map<String, dynamic>>.from(vocab);
      _filteredVocab = List<Map<String, dynamic>>.from(_allVocab);
      _currentGroupId = initialGroupId;
      _selectedWordIds
        ..clear()
        ..addAll(wordIdsForInitial);
      _isLoading = false;
    });

    _applySort();
  }

  void _applySort() {
    _filteredVocab.sort((a, b) {
      final String aWord = (a['word'] ?? '').toString().toLowerCase();
      final String bWord = (b['word'] ?? '').toString().toLowerCase();
      final int cmp = aWord.compareTo(bWord);
      return _isAscending ? cmp : -cmp;
    });
    setState(() {});
  }

  void _toggleSortOrder() {
    setState(() {
      _isAscending = !_isAscending;
      _applySort();
    });
  }

  void _runFilter(String keyword) {
    final String query = keyword.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredVocab = List<Map<String, dynamic>>.from(_allVocab);
      } else {
        _filteredVocab = _allVocab
            .where(
              (item) =>
                  (item['word'] ?? '').toString().toLowerCase().contains(query),
            )
            .toList();
      }
      _applySort();
    });
  }

  Future<void> _onSelectGroup(int? groupId) async {
    if (groupId == null) {
      setState(() {
        _currentGroupId = null;
        _selectedWordIds.clear();
      });
      return;
    }

    final Set<int> wordIds = await _dbHelper.getWordIdsForGroup(groupId);

    setState(() {
      _currentGroupId = groupId;
      _selectedWordIds
        ..clear()
        ..addAll(wordIds);
    });
  }

  Future<void> _createNewGroup() async {
    final TextEditingController nameController = TextEditingController();

    final String? result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Word Group'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context, name);
              },
              child: const Text('CREATE'),
            ),
          ],
        );
      },
    );

    if (result == null || result.trim().isEmpty) return;

    final int newId = await _dbHelper.insertWordGroup(result.trim());
    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllWordGroups();

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
      _currentGroupId = newId;
      _selectedWordIds.clear();
    });
  }

  Future<void> _renameCurrentGroup() async {
    if (_currentGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a group to rename.')),
      );
      return;
    }

    final current = _groups.firstWhere(
      (g) => g['id'] == _currentGroupId,
      orElse: () => <String, dynamic>{},
    );

    final String currentName = (current['name'] ?? '').toString();
    final TextEditingController nameController = TextEditingController(
      text: currentName,
    );

    final String? result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Word Group'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context, name);
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );

    if (result == null || result.trim().isEmpty) return;

    await _dbHelper.updateWordGroup(_currentGroupId!, result.trim());

    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllWordGroups();

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Group renamed successfully.')),
    );
  }

  void _toggleWord(int id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedWordIds.add(id);
      } else {
        _selectedWordIds.remove(id);
      }
    });
  }

  Future<void> _saveGroup() async {
    if (_currentGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create or select a group first.')),
      );
      return;
    }

    await _dbHelper.setGroupWords(_currentGroupId!, _selectedWordIds);

    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllWordGroups();

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
      // Keep current group selection
    });

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _deleteCurrentGroup() async {
    if (_currentGroupId == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Group'),
          content: const Text(
            'Are you sure you want to delete this group and its word list?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _dbHelper.deleteWordGroup(_currentGroupId!);

    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllWordGroups();

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
      _currentGroupId = null;
      _selectedWordIds.clear();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Word Groups'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group selector and actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Rename current group',
                        onPressed: _renameCurrentGroup,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: 'Create new group',
                        onPressed: _createNewGroup,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete current group',
                        onPressed: _currentGroupId == null
                            ? null
                            : _deleteCurrentGroup,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownMenu<int?>(
                    width: MediaQuery.of(context).size.width - 32,
                    menuHeight: 250,
                    initialSelection: _currentGroupId,
                    label: const Text('Word group'),
                    onSelected: (int? value) {
                      _onSelectGroup(value);
                    },
                    dropdownMenuEntries: _groups
                        .map(
                          (g) => DropdownMenuEntry<int?>(
                            value: g['id'] as int?,
                            label: (g['name'] ?? '').toString(),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  // Search bar for words
                  TextField(
                    controller: _searchController,
                    onChanged: _runFilter,
                    decoration: InputDecoration(
                      hintText: 'Search words in vocabulary',
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
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
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
                  const SizedBox(height: 4),
                  Expanded(
                    child: _allVocab.isEmpty
                        ? const Center(
                            child: Text(
                              'No vocabulary found. Please add some words first.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredVocab.length,
                            itemBuilder: (context, index) {
                              final Map<String, dynamic> item =
                                  _filteredVocab[index];
                              final int? id = item['id'] as int?;
                              final String word = (item['word'] ?? '')
                                  .toString();
                              final String wordType = (item['word_type'] ?? '')
                                  .toString();

                              if (id == null) {
                                return const SizedBox.shrink();
                              }

                              final bool isSelected = _selectedWordIds.contains(
                                id,
                              );

                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (checked) =>
                                    _toggleWord(id, checked),
                                activeColor: Colors.indigo,
                                title: Text(word.isEmpty ? '(no word)' : word),
                                subtitle: wordType.isEmpty
                                    ? null
                                    : Text(
                                        wordType,
                                        style: const TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.indigo,
                                        ),
                                      ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _saveGroup,
                      child: const Text(
                        'SAVE GROUP',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 45),
                ],
              ),
            ),
    );
  }
}
