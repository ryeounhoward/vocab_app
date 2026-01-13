import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/db_helper.dart';

class SortIdiomsDataPage extends StatefulWidget {
  const SortIdiomsDataPage({super.key});

  @override
  State<SortIdiomsDataPage> createState() => _SortIdiomsDataPageState();
}

class _SortIdiomsDataPageState extends State<SortIdiomsDataPage> {
  final DBHelper _dbHelper = DBHelper();

  bool _isLoading = true;
  bool _useAllIdioms = true;
  List<Map<String, dynamic>> _allIdioms = [];
  List<Map<String, dynamic>> _filteredIdioms = [];
  final Set<int> _selectedIds = {};
  bool _isAscending = true;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _idiomGroups = [];
  int? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _loadDataAndPrefs();
  }

  Future<void> _loadDataAndPrefs() async {
    // Load preferences from the database (app_preferences table)
    final String? useAllStr = await _dbHelper.getPreference(
      'quiz_use_all_idioms',
    );
    final bool useAll = useAllStr == null ? true : useAllStr == 'true';

    final String? idsStr = await _dbHelper.getPreference(
      'quiz_selected_idiom_ids',
    );
    final Set<int> selectedFromPrefs = (idsStr == null || idsStr.isEmpty)
        ? <int>{}
        : idsStr
              .split(',')
              .map((s) => int.tryParse(s.trim()))
              .whereType<int>()
              .toSet();

    final String? groupIdStr = await _dbHelper.getPreference(
      'quiz_selected_idiom_group_id',
    );
    final int? storedGroupId = int.tryParse(groupIdStr ?? '');

    final data = await _dbHelper.queryAll(DBHelper.tableIdioms);
    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllIdiomGroups();

    List<Map<String, dynamic>> visibleIdioms = List<Map<String, dynamic>>.from(
      data,
    );

    int? effectiveGroupId;
    if (!useAll && storedGroupId != null) {
      final bool groupExists = groups.any(
        (g) => (g['id'] as int?) != null && g['id'] == storedGroupId,
      );
      if (groupExists) {
        final Set<int> idiomIds = await _dbHelper.getIdiomIdsForGroup(
          storedGroupId,
        );
        visibleIdioms = visibleIdioms
            .where((item) => idiomIds.contains(item['id'] as int? ?? -1))
            .toList();
        effectiveGroupId = storedGroupId;
      }
    }

    // Determine selected IDs: if a group is active, treat all idioms
    // in that group as selected; otherwise fall back to stored IDs.
    final Set<int> computedSelectedIds = <int>{};
    if (!useAll && effectiveGroupId != null) {
      computedSelectedIds.addAll(
        visibleIdioms.map((e) => e['id']).whereType<int>(),
      );
    } else {
      computedSelectedIds.addAll(
        visibleIdioms
            .map((e) => e['id'])
            .whereType<int>()
            .where((id) => selectedFromPrefs.contains(id)),
      );
    }

    setState(() {
      _useAllIdioms = useAll;
      _allIdioms = visibleIdioms;
      _filteredIdioms = List<Map<String, dynamic>>.from(_allIdioms);
      _selectedIds
        ..clear()
        ..addAll(computedSelectedIds);
      _idiomGroups = List<Map<String, dynamic>>.from(groups);
      _selectedGroupId = effectiveGroupId;
      _isLoading = false;
    });

    _applySort();
  }

  bool get _isAllSelected =>
      _allIdioms.isNotEmpty && _selectedIds.length == _allIdioms.length;

  bool get _hasAnySelected => _selectedIds.isNotEmpty;

  void _applySort() {
    _filteredIdioms.sort((a, b) {
      final String aText = (a['idiom'] ?? '').toString().toLowerCase();
      final String bText = (b['idiom'] ?? '').toString().toLowerCase();
      final int cmp = aText.compareTo(bText);
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
        _filteredIdioms = List<Map<String, dynamic>>.from(_allIdioms);
      } else {
        _filteredIdioms = _allIdioms
            .where(
              (item) => (item['idiom'] ?? '').toString().toLowerCase().contains(
                query,
              ),
            )
            .toList();
      }
      _applySort();
    });
  }

  void _toggleUseAll(bool value) {
    setState(() {
      _useAllIdioms = value;
    });
  }

  Future<void> _onGroupChanged(int? groupId) async {
    if (groupId == _selectedGroupId) return;

    final data = await _dbHelper.queryAll(DBHelper.tableIdioms);
    List<Map<String, dynamic>> visibleIdioms = List<Map<String, dynamic>>.from(
      data,
    );

    if (groupId != null) {
      final Set<int> idiomIds = await _dbHelper.getIdiomIdsForGroup(groupId);
      visibleIdioms = visibleIdioms
          .where((item) => idiomIds.contains(item['id'] as int? ?? -1))
          .toList();

      _useAllIdioms = false;
    }

    final Set<int> allowedIds = visibleIdioms
        .map((e) => e['id'])
        .whereType<int>()
        .toSet();

    setState(() {
      _selectedGroupId = groupId;
      _allIdioms = visibleIdioms;
      _filteredIdioms = List<Map<String, dynamic>>.from(_allIdioms);
      _selectedIds
        ..clear()
        ..addAll(allowedIds);
    });

    _applySort();
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
          ..addAll(_allIdioms.map((e) => e['id']).whereType<int>());
      } else {
        _selectedIds.clear();
      }
    });
  }

  Future<void> _saveSelections() async {
    final prefs = await SharedPreferences.getInstance();

    if (_useAllIdioms || (_selectedGroupId == null && _selectedIds.isEmpty)) {
      await _dbHelper.removePreference('quiz_use_all_idioms');
      await _dbHelper.removePreference('quiz_selected_idiom_ids');
      await _dbHelper.removePreference('quiz_selected_idiom_group_id');

      await prefs.remove('quiz_use_all_idioms');
      await prefs.remove('quiz_selected_idiom_ids');
      await prefs.remove('quiz_selected_idiom_group_id');
    } else {
      // If a group is selected, always use that group's idioms as the
      // selection for displaying data.
      Set<int> finalIds = _selectedIds;
      if (_selectedGroupId != null) {
        finalIds = await _dbHelper.getIdiomIdsForGroup(_selectedGroupId!);
      }

      await _dbHelper.setPreference(
        'quiz_selected_idiom_ids',
        finalIds.map((id) => id.toString()).join(','),
      );

      await prefs.setStringList(
        'quiz_selected_idiom_ids',
        finalIds.map((id) => id.toString()).toList(),
      );

      if (_selectedGroupId != null) {
        await _dbHelper.setPreference(
          'quiz_selected_idiom_group_id',
          _selectedGroupId!.toString(),
        );

        await prefs.setInt('quiz_selected_idiom_group_id', _selectedGroupId!);
      } else {
        await _dbHelper.removePreference('quiz_selected_idiom_group_id');

        await prefs.remove('quiz_selected_idiom_group_id');
      }

      await _dbHelper.setPreference(
        'quiz_use_all_idioms',
        _useAllIdioms ? 'true' : 'false',
      );

      await prefs.setBool('quiz_use_all_idioms', _useAllIdioms);
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
      appBar: AppBar(title: const Text('Sort Idioms Data'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  if (!_useAllIdioms && _idiomGroups.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Filter by idiom group (optional)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<int?>(
                          value: _selectedGroupId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('All idioms (no group filter)'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('All idioms (no group filter)'),
                            ),
                            ..._idiomGroups.map(
                              (g) => DropdownMenuItem<int?>(
                                value: g['id'] as int?,
                                child: Text((g['name'] ?? '').toString()),
                              ),
                            ),
                          ],
                          onChanged: _onGroupChanged,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  TextField(
                    controller: _searchController,
                    onChanged: _runFilter,
                    decoration: InputDecoration(
                      hintText: 'Search idioms',
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
                    title: const Text('Use all idioms'),
                    subtitle: const Text(
                      'Include all idioms in quizzes, practice, and review.',
                    ),
                    activeColor: Colors.indigo,
                    value: _useAllIdioms,
                    onChanged: _toggleUseAll,
                  ),
                  const SizedBox(height: 8),
                  if (!_useAllIdioms)
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
                              onChanged: _selectedGroupId != null
                                  ? null
                                  : _toggleSelectAll,
                            ),
                            const Text('Select all'),
                          ],
                        ),
                        Text(
                          '${_selectedIds.length} of ${_allIdioms.length} selected',
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
                    child: _useAllIdioms
                        ? const Center(
                            child: Text(
                              'All idioms will be used in quizzes, practice, and review.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _allIdioms.isEmpty
                        ? const Center(
                            child: Text(
                              'No idioms found. Please add some idioms first.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredIdioms.length,
                            itemBuilder: (context, index) {
                              final item = _filteredIdioms[index];
                              final int? id = item['id'] as int?;
                              final String idiom = (item['idiom'] ?? '')
                                  .toString();
                              final String description =
                                  (item['description'] ?? '').toString();

                              if (id == null) {
                                return const SizedBox.shrink();
                              }

                              final bool isSelected = _selectedIds.contains(id);

                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: _selectedGroupId != null
                                    ? null
                                    : (checked) => _toggleItem(id, checked),
                                activeColor: Colors.indigo,
                                title: Text(
                                  idiom.isEmpty ? '(no idiom)' : idiom,
                                ),
                                subtitle: description.isEmpty
                                    ? null
                                    : Text(
                                        description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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
