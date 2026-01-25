import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../database/db_helper.dart';

// ---------------------------------------------------------
// 1. NOTES LIST PAGE
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Imported $added notes!')));
        }
      });
    } else if (!_importHandled) {
      _refreshNotes();
    }
  }

  Future<void> _refreshNotes() async {
    final data = await _dbHelper.queryAll('notes');
    setState(() {
      _notes = data;
      _isLoading = false;
    });
  }

  void _showDeleteDialog(int id) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text("Delete Note?"),
          content: const Text(
            "Are you sure you want to delete this note? This action cannot be undone.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                await _dbHelper.delete(id, 'notes');
                if (mounted) {
                  Navigator.pop(context);
                  _refreshNotes();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text("Note deleted")));
                }
              },
              child: const Text(
                "Delete",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openEditor({Map<String, dynamic>? note}) async {
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
      return doc.toPlainText().trim();
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Notes', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
          ? const Center(child: Text("No notes yet. Tap + to start!"))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _notes.length,
              itemBuilder: (context, index) {
                final note = _notes[index];
                return GestureDetector(
                  onTap: () => _openEditor(note: note),
                  child: Card(
                    color: Color(note['color'] ?? Colors.white.value),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note['title'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            note['category'] ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const Divider(),
                          Expanded(child: Text(_getPlainText(note['content']))),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () =>
                                  _showDeleteDialog(note['id'] as int),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ---------------------------------------------------------
// 2. NOTE EDITOR PAGE
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
    _categoryController = TextEditingController(
      text: widget.note?['category'] ?? '',
    );

    if (widget.note?['color'] != null) {
      _selectedColor = Color(widget.note!['color']);
    }

    if (widget.note != null && widget.note!['content'] != null) {
      _quillController = quill.QuillController(
        document: quill.Document.fromJson(jsonDecode(widget.note!['content'])),
        selection: const TextSelection.collapsed(offset: 0),
      );
    } else {
      _quillController = quill.QuillController.basic();
    }
  }

  void _save() {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Title is required")));
      return;
    }
    final contentJson = jsonEncode(
      _quillController.document.toDelta().toJson(),
    );
    Navigator.pop(context, {
      'id': widget.note?['id'],
      'title': _titleController.text,
      'category': _categoryController.text,
      'content': contentJson,
      'color': _selectedColor.value,
      'date': DateTime.now().toIso8601String(),
    });
  }

  void _pickColor() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Select Color"),
        content: Wrap(
          spacing: 15,
          runSpacing: 15,
          children:
              [
                    Colors.white,
                    Colors.red[100]!,
                    Colors.green[100]!,
                    Colors.blue[100]!,
                    Colors.yellow[100]!,
                    Colors.orange[100]!,
                    Colors.purple[100]!,
                  ]
                  .map(
                    (c) => GestureDetector(
                      onTap: () {
                        setState(() => _selectedColor = c);
                        Navigator.pop(ctx);
                      },
                      child: CircleAvatar(
                        backgroundColor: c,
                        radius: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true, // Crucial for toolbar placement
      backgroundColor: _selectedColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: Icon(
              _showToolbar ? Icons.text_format : Icons.text_fields,
              color: _showToolbar ? Colors.indigo : Colors.black,
            ),
            onPressed: () => setState(() => _showToolbar = !_showToolbar),
          ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            onPressed: _pickColor,
          ),
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

          if (_showToolbar)
            Container(
              key: const ValueKey('quill_toolbar'),
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
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
                  // FIXED: Removed IntrinsicWidth. Used a large fixed width
                  // to prevent internal "Arrow" logic from crashing.
                  width: 1300,
                  child: quill.QuillSimpleToolbar(
                    controller: _quillController,
                    config: const quill.QuillSimpleToolbarConfig(
                      multiRowsDisplay: false,
                      showFontSize: true,
                      showFontFamily: true,
                      showBoldButton: true,
                      showItalicButton: true,
                      showUnderLineButton: true,
                      showStrikeThrough: true,
                      showListBullets: true,
                      showListNumbers: true,
                      showColorButton: true,
                      showBackgroundColorButton: true,
                      showLink: true,
                      showAlignmentButtons: true,
                      // Disabled to avoid crashes and save space
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
