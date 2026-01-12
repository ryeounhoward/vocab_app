import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/db_helper.dart';

class SortWordsDataPage extends StatefulWidget {
  const SortWordsDataPage({super.key});

  @override
  State<SortWordsDataPage> createState() => _SortWordsDataPageState();
}

class _SortWordsDataPageState extends State<SortWordsDataPage> {
  final DBHelper _dbHelper = DBHelper();

  bool _isLoading = true;
  bool _useAllWords = true;
  List<Map<String, dynamic>> _allVocab = [];
  List<Map<String, dynamic>> _filteredVocab = [];
  final Set<int> _selectedIds = {};
  bool _isAscending = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDataAndPrefs();
  }

  Future<void> _loadDataAndPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final bool useAll = prefs.getBool('quiz_use_all_words') ?? true;
    final List<String> storedIds =
        prefs.getStringList('quiz_selected_word_ids') ?? <String>[];
    final Set<int> selectedFromPrefs = storedIds
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .toSet();

    final data = await _dbHelper.queryAll(DBHelper.tableVocab);

    setState(() {
      _useAllWords = useAll;
      _allVocab = List<Map<String, dynamic>>.from(data);
      _filteredVocab = List<Map<String, dynamic>>.from(_allVocab);
      _selectedIds
        ..clear()
        ..addAll(
          _allVocab
              .map((e) => e['id'])
              .whereType<int>()
              .where((id) => selectedFromPrefs.contains(id)),
        );
      _isLoading = false;
    });

    _applySort();
  }

  bool get _isAllSelected =>
      _allVocab.isNotEmpty && _selectedIds.length == _allVocab.length;

  bool get _hasAnySelected => _selectedIds.isNotEmpty;

  void _applySort() {
    _filteredVocab.sort((a, b) {
      final String aWord = (a['word'] ?? '').toString().toLowerCase();
      final String bWord = (b['word'] ?? '').toString().toLowerCase();
      final int cmp = aWord.compareTo(bWord);
      return _isAscending ? cmp : -cmp;
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _isAscending = !_isAscending;
      _applySort();
    });
  }

  void _runFilter(String keyword) {
    final query = keyword.trim().toLowerCase();
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

  void _toggleUseAll(bool value) {
    setState(() {
      _useAllWords = value;
    });
  }

  void _toggleItem(int id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _toggleSelectAll(bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedIds
          ..clear()
          ..addAll(_allVocab.map((e) => e['id']).whereType<int>());
      } else {
        _selectedIds.clear();
      }
    });
  }

  Future<void> _saveSelections() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('quiz_use_all_words', _useAllWords);

    if (_useAllWords || _selectedIds.isEmpty) {
      await prefs.remove('quiz_selected_word_ids');
    } else {
      await prefs.setStringList(
        'quiz_selected_word_ids',
        _selectedIds.map((id) => id.toString()).toList(),
      );
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sort Words Data'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: _runFilter,
                    decoration: InputDecoration(
                      hintText: 'Search words',
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
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use all words'),
                    subtitle: const Text(
                      'Include all words in quizzes, practice, and review.',
                    ),
                    activeColor: Colors.indigo,
                    value: _useAllWords,
                    onChanged: _toggleUseAll,
                  ),
                  const SizedBox(height: 8),
                  if (!_useAllWords)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _isAllSelected
                                  ? true
                                  : (_hasAnySelected ? null : false),
                              tristate: true,
                              onChanged: _toggleSelectAll,
                            ),
                            const Text('Select all'),
                          ],
                        ),
                        Text(
                          '${_selectedIds.length} of ${_allVocab.length} selected',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
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
                    child: _useAllWords
                        ? const Center(
                            child: Text(
                              'All vocabulary words will be used in quizzes, practice, and review.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _allVocab.isEmpty
                        ? const Center(
                            child: Text(
                              'No vocabulary found. Please add some words first.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredVocab.length,
                            itemBuilder: (context, index) {
                              final item = _filteredVocab[index];
                              final int? id = item['id'] as int?;
                              final String word = (item['word'] ?? '')
                                  .toString();
                              final String wordType = (item['word_type'] ?? '')
                                  .toString();

                              if (id == null) {
                                return const SizedBox.shrink();
                              }

                              final bool isSelected = _selectedIds.contains(id);

                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (checked) =>
                                    _toggleItem(id, checked),
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
                      onPressed: _saveSelections,
                      child: const Text(
                        'SAVE SETTINGS',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
    );
  }
}
