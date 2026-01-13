import 'package:flutter/material.dart';

import '../database/db_helper.dart';

class IdiomGroupsPage extends StatefulWidget {
  const IdiomGroupsPage({super.key});

  @override
  State<IdiomGroupsPage> createState() => _IdiomGroupsPageState();
}

class _IdiomGroupsPageState extends State<IdiomGroupsPage> {
  final DBHelper _dbHelper = DBHelper();

  bool _isLoading = true;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _allIdioms = [];
  List<Map<String, dynamic>> _filteredIdioms = [];

  final TextEditingController _searchController = TextEditingController();

  int? _currentGroupId;
  final Set<int> _selectedIdiomIds = {};
  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllIdiomGroups();
    final List<Map<String, dynamic>> idioms = await _dbHelper.queryAll(
      DBHelper.tableIdioms,
    );

    int? initialGroupId;
    if (groups.isNotEmpty) {
      initialGroupId = groups.first['id'] as int?;
    }

    Set<int> idiomIdsForInitial = {};
    if (initialGroupId != null) {
      idiomIdsForInitial = await _dbHelper.getIdiomIdsForGroup(initialGroupId);
    }

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
      _allIdioms = List<Map<String, dynamic>>.from(idioms);
      _filteredIdioms = List<Map<String, dynamic>>.from(_allIdioms);
      _currentGroupId = initialGroupId;
      _selectedIdiomIds
        ..clear()
        ..addAll(idiomIdsForInitial);
      _isLoading = false;
    });

    _applySort();
  }

  void _applySort() {
    _filteredIdioms.sort((a, b) {
      final String aText = (a['idiom'] ?? '').toString().toLowerCase();
      final String bText = (b['idiom'] ?? '').toString().toLowerCase();
      final int cmp = aText.compareTo(bText);
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

  Future<void> _onSelectGroup(int? groupId) async {
    if (groupId == null) {
      setState(() {
        _currentGroupId = null;
        _selectedIdiomIds.clear();
      });
      return;
    }

    final Set<int> idiomIds = await _dbHelper.getIdiomIdsForGroup(groupId);

    setState(() {
      _currentGroupId = groupId;
      _selectedIdiomIds
        ..clear()
        ..addAll(idiomIds);
    });
  }

  Future<void> _createNewGroup() async {
    final TextEditingController nameController = TextEditingController();

    final String? result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Idiom Group'),
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

    final int newId = await _dbHelper.insertIdiomGroup(result.trim());
    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllIdiomGroups();

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
      _currentGroupId = newId;
      _selectedIdiomIds.clear();
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
          title: const Text('Rename Idiom Group'),
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

    await _dbHelper.updateIdiomGroup(_currentGroupId!, result.trim());

    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllIdiomGroups();

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Group renamed successfully.')),
    );
  }

  void _toggleIdiom(int id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedIdiomIds.add(id);
      } else {
        _selectedIdiomIds.remove(id);
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

    await _dbHelper.setGroupIdioms(_currentGroupId!, _selectedIdiomIds);

    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllIdiomGroups();

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
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
            'Are you sure you want to delete this idiom group and its list?',
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

    await _dbHelper.deleteIdiomGroup(_currentGroupId!);

    final List<Map<String, dynamic>> groups = await _dbHelper
        .getAllIdiomGroups();

    setState(() {
      _groups = List<Map<String, dynamic>>.from(groups);
      _currentGroupId = null;
      _selectedIdiomIds.clear();
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
      appBar: AppBar(title: const Text('Idiom Groups'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<int?>(
                          isExpanded: true,
                          value: _currentGroupId,
                          hint: const Text('Select group'),
                          items: [
                            ..._groups.map(
                              (g) => DropdownMenuItem<int?>(
                                value: g['id'] as int?,
                                child: Text((g['name'] ?? '').toString()),
                              ),
                            ),
                          ],
                          onChanged: _onSelectGroup,
                        ),
                      ),
                      const SizedBox(width: 8),
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
                  const SizedBox(height: 16),
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
                    child: _allIdioms.isEmpty
                        ? const Center(
                            child: Text(
                              'No idioms found. Please add some idioms first.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredIdioms.length,
                            itemBuilder: (context, index) {
                              final Map<String, dynamic> item =
                                  _filteredIdioms[index];
                              final int? id = item['id'] as int?;
                              final String idiom = (item['idiom'] ?? '')
                                  .toString();
                              final String description =
                                  (item['description'] ?? '').toString();

                              if (id == null) {
                                return const SizedBox.shrink();
                              }

                              final bool isSelected = _selectedIdiomIds
                                  .contains(id);

                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (checked) =>
                                    _toggleIdiom(id, checked),
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
