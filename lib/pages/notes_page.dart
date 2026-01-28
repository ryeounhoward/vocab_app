import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../database/db_helper.dart';

// ---------------------------------------------------------
// 1. NOTES LIST PAGE (KEPT EXACTLY AS YOURS)
// ---------------------------------------------------------
class NotesPage extends StatefulWidget {
  const NotesPage({Key? key}) : super(key: key);

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final DBHelper _dbHelper = DBHelper();
  List<Map<String, dynamic>> _notes = [];
  bool _isLoading = true;

  // Selection Mode State
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  bool _importHandled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['imported'] == true && !_importHandled) {
      _importHandled = true;
      _refreshNotes().then((_) {
        final int added = args['addedNotes'] ?? 0;
        if (added > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported $added notes!')),
          );
        }
      });
    } else if (!_importHandled) {
      _refreshNotes();
    }
  }

  Future<void> _refreshNotes() async {
    final data = await _dbHelper.queryAll('notes');
    if (mounted) {
      setState(() {
        _notes = data;
        _isLoading = false;
      });
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "";
    try {
      DateTime dt = DateTime.parse(dateStr);
      List<String> months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      String hour = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(2, '0');
      String minute = dt.minute.toString().padLeft(2, '0');
      String ampm = dt.hour < 12 ? 'AM' : 'PM';
      return "${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$minute $ampm";
    } catch (e) {
      return "";
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _notes.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        for (var note in _notes) {
          _selectedIds.add(note['id'] as int);
        }
      }
    });
  }

  void _deleteSelected() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete ${_selectedIds.length} notes?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              for (int id in _selectedIds) {
                await _dbHelper.delete(id, 'notes');
              }
              Navigator.pop(ctx);
              _exitSelectionMode();
              _refreshNotes();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openEditor({Map<String, dynamic>? note}) async {
    if (_isSelectionMode) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NoteEditor(note: note)),
    );

    if (result != null) {
      if (result['id'] == null) {
        await _dbHelper.insert(result, 'notes');
      } else {
        await _dbHelper.update(result, 'notes');
      }
      _refreshNotes();
    }
  }

  String _getPlainText(String jsonSource) {
    try {
      final doc = quill.Document.fromJson(jsonDecode(jsonSource));
      String text = doc.toPlainText().trim();
      // If the note has no text but contains an image, show placeholder
      if (text.isEmpty && jsonSource.contains('image')) return "[Image]";
      return text;
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isSelectionMode) {
          _exitSelectionMode();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(_isSelectionMode ? '${_selectedIds.length} Selected' : 'My Notes', style: const TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: _isSelectionMode ? IconButton(icon: const Icon(Icons.close, color: Colors.black), onPressed: _exitSelectionMode) : null,
          actions: _isSelectionMode ? [
            IconButton(icon: Icon(_selectedIds.length == _notes.length ? Icons.deselect : Icons.select_all, color: Colors.black), onPressed: _selectAll),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _deleteSelected),
          ] : [],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _notes.isEmpty
                ? const Center(child: Text("No notes yet. Tap + to start!"))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
                    ),
                    itemCount: _notes.length,
                    itemBuilder: (context, index) {
                      final note = _notes[index];
                      final int noteId = note['id'] as int;
                      final bool isSelected = _selectedIds.contains(noteId);

                      return GestureDetector(
                        onTap: () => _isSelectionMode ? _toggleSelection(noteId) : _openEditor(note: note),
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            setState(() { _isSelectionMode = true; _selectedIds.add(noteId); });
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected ? Border.all(color: Colors.indigo, width: 3) : Border.all(color: Colors.transparent),
                          ),
                          child: Card(
                            margin: EdgeInsets.zero,
                            color: Color(note['color'] ?? Colors.white.value),
                            elevation: isSelected ? 8 : 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(note['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(note['category'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                  const Divider(),
                                  Expanded(child: Text(_getPlainText(note['content']), style: const TextStyle(fontSize: 13), overflow: TextOverflow.fade)),
                                  Align(alignment: Alignment.bottomRight, child: Text(_formatDate(note['date']), style: TextStyle(fontSize: 10, color: Colors.black.withOpacity(0.4), fontStyle: FontStyle.italic))),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
        floatingActionButton: _isSelectionMode ? null : FloatingActionButton(
          backgroundColor: Colors.indigo,
          onPressed: () => _openEditor(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 2. NOTE EDITOR PAGE (FIXED FOR VERSION 11.5.0)
// ---------------------------------------------------------
class NoteEditor extends StatefulWidget {
  final Map<String, dynamic>? note;
  const NoteEditor({Key? key, this.note}) : super(key: key);

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _titleController;
  late TextEditingController _categoryController;
  late quill.QuillController _quillController;
  Color _selectedColor = Colors.white;
  bool _showToolbar = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?['title'] ?? '');
    _categoryController = TextEditingController(text: widget.note?['category'] ?? '');
    _selectedColor = Color(widget.note?['color'] ?? Colors.white.value);

    if (widget.note != null && widget.note!['content'] != null) {
      _quillController = quill.QuillController(
        document: quill.Document.fromJson(jsonDecode(widget.note!['content'])),
        selection: const TextSelection.collapsed(offset: 0),
      );
    } else {
      _quillController = quill.QuillController.basic();
    }
  }

  // Helper to check for unsaved changes
  bool _hasUnsavedChanges() {
    final currentContent = jsonEncode(_quillController.document.toDelta().toJson());
    final originalContent = widget.note?['content'] ?? jsonEncode(quill.Document().toDelta().toJson());
    return _titleController.text != (widget.note?['title'] ?? '') ||
        _categoryController.text != (widget.note?['category'] ?? '') ||
        currentContent != originalContent ||
        _selectedColor.value != (widget.note?['color'] ?? Colors.white.value);
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges()) return true;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Exit anyway?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Discard')),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  void _save() {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Title is required")));
      return;
    }
    final contentJson = jsonEncode(_quillController.document.toDelta().toJson());
    Navigator.pop(context, {
      'id': widget.note?['id'],
      'title': _titleController.text,
      'category': _categoryController.text,
      'content': contentJson,
      'color': _selectedColor.value,
      'date': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        resizeToAvoidBottomInset: true, // Prevents keyboard from hiding link dialogs
        backgroundColor: _selectedColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          actions: [
            IconButton(icon: const Icon(Icons.image_outlined), onPressed: _pickImage), // Image support
            IconButton(
              icon: Icon(_showToolbar ? Icons.text_format : Icons.text_fields, color: _showToolbar ? Colors.indigo : Colors.black),
              onPressed: () => setState(() => _showToolbar = !_showToolbar),
            ),
            IconButton(icon: const Icon(Icons.palette_outlined), onPressed: _pickColor),
            IconButton(icon: const Icon(Icons.check), onPressed: _save),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: "Title",
                      border: InputBorder.none,
                    ),
                  ),
                  TextField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      hintText: "Category",
                      border: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: quill.QuillEditor.basic(
                  controller: _quillController,
                  config: const quill.QuillEditorConfig(
                    placeholder: "Write something...",
                  ),
                ),
              ),
            ),

            // TOOLBAR FIX: Wrapped in SafeArea to prevent overlap with Android Bottom Bar
            if (_showToolbar)
              SafeArea(
                child: Container(
                  key: const ValueKey('quill_toolbar'),
                  padding: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 1100,
                      child: quill.QuillSimpleToolbar(
                        controller: _quillController,
                        config: quill.QuillSimpleToolbarConfig(
                          multiRowsDisplay: false,
                          showUndo: false,
                          showRedo: false,
                          showSearchButton: false,
                          showSubscript: false,
                          showSuperscript: false,
                          showInlineCode: false,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _quillController.dispose();
    super.dispose();
  }
}