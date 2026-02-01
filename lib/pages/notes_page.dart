import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter_quill_extensions/src/common/utils/element_utils/element_utils.dart'
    show getElementAttributes;
import 'package:flutter_quill_extensions/src/editor/image/image_menu.dart'
    show ImageOptionsMenu;
import 'package:flutter_quill_extensions/src/editor/image/widgets/image.dart'
    show getImageWidgetByImageSource, standardizeImageUrl;
import 'package:image_picker/image_picker.dart';
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
      List<String> months = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ];
      String hour = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(
        2,
        '0',
      );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
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
      if (text.isEmpty && jsonSource.contains('image')) return "[Image]";
      return text;
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            _isSelectionMode ? '${_selectedIds.length} Selected' : 'My Notes',
            style: const TextStyle(color: Colors.black),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.black),
                  onPressed: _exitSelectionMode,
                )
              : null,
          actions: _isSelectionMode
              ? [
                  IconButton(
                    icon: Icon(
                      _selectedIds.length == _notes.length
                          ? Icons.deselect
                          : Icons.select_all,
                      color: Colors.black,
                    ),
                    onPressed: _selectAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: _deleteSelected,
                  ),
                ]
              : [],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _notes.isEmpty
            ? const Center(child: Text("No notes yet. Tap + to start!"))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _notes.length,
                itemBuilder: (context, index) {
                  final note = _notes[index];
                  final int noteId = note['id'] as int;
                  final bool isSelected = _selectedIds.contains(noteId);

                  return GestureDetector(
                    onTap: () => _isSelectionMode
                        ? _toggleSelection(noteId)
                        : _openEditor(note: note),
                    onLongPress: () {
                      if (!_isSelectionMode) {
                        setState(() {
                          _isSelectionMode = true;
                          _selectedIds.add(noteId);
                        });
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(color: Colors.indigo, width: 3)
                            : Border.all(color: Colors.transparent),
                      ),
                      child: Card(
                        margin: EdgeInsets.zero,
                        color: Color(note['color'] ?? Colors.white.value),
                        elevation: isSelected ? 8 : 3,
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
                              Expanded(
                                child: Text(
                                  _getPlainText(note['content']),
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.fade,
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Text(
                                  _formatDate(note['date']),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.black.withOpacity(0.4),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
        floatingActionButton: _isSelectionMode
            ? null
            : FloatingActionButton(
                backgroundColor: Colors.indigo,
                onPressed: () => _openEditor(),
                child: const Icon(Icons.add, color: Colors.white),
              ),
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

  Widget _safeContextMenuBuilder(
    BuildContext context,
    quill.QuillRawEditorState rawEditorState,
  ) {
    try {
      return quill.QuillRawEditorConfig.defaultContextMenuBuilder(
        context,
        rawEditorState,
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?['title'] ?? '');
    _categoryController = TextEditingController(
      text: widget.note?['category'] ?? '',
    );
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

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final index = _quillController.selection.baseOffset;
      final length = _quillController.selection.extentOffset - index;
      _quillController.replaceText(
        index,
        length,
        quill.BlockEmbed.image(image.path),
        null,
      );
    }
  }

  bool _hasUnsavedChanges() {
    final currentContent = jsonEncode(
      _quillController.document.toDelta().toJson(),
    );
    final originalContent =
        widget.note?['content'] ??
        jsonEncode(quill.Document().toDelta().toJson());
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
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
                            border: Border.all(color: Colors.grey.shade300),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool shouldExit = await _onWillPop();
        if (shouldExit && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _selectedColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          actions: [
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              onPressed: _pickColor,
              tooltip: "Change Color",
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
              tooltip: "Save",
            ),
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
                  config: quill.QuillEditorConfig(
                    placeholder: "Write something...",
                    contextMenuBuilder: _safeContextMenuBuilder,
                    embedBuilders: [
                      ...FlutterQuillEmbeds.editorBuilders(
                        imageEmbedConfig: const QuillEditorImageEmbedConfig(),
                      ).where((b) => b.key != quill.BlockEmbed.imageType),
                      ZoomableQuillEditorImageEmbedBuilder(
                        config: const QuillEditorImageEmbedConfig(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Toolbar Section
            SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                child: Row(
                  children: [
                    // FIX IS HERE: Used Expanded around QuillSimpleToolbar directly
                    // REMOVED SingleChildScrollView wrapper
                    Expanded(
                      child: quill.QuillSimpleToolbar(
                        controller: _quillController,
                        config: quill.QuillSimpleToolbarConfig(
                          multiRowsDisplay: false,
                          showUndo: true,
                          showRedo: true,
                          showBoldButton: true,
                          showItalicButton: true,
                          showUnderLineButton: true,
                          showStrikeThrough: true,
                          showColorButton: true,
                          showBackgroundColorButton: true,
                          showClearFormat: true,
                          showListNumbers: true,
                          showListBullets: true,
                          showListCheck: true,
                          showCodeBlock: true,
                          showQuote: true,
                          showIndent: true,
                          showLink: true,
                          embedButtons: FlutterQuillEmbeds.toolbarButtons(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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

class ZoomableQuillEditorImageEmbedBuilder extends quill.EmbedBuilder {
  ZoomableQuillEditorImageEmbedBuilder({required this.config});

  final QuillEditorImageEmbedConfig config;

  @override
  String get key => quill.BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final imageSource = standardizeImageUrl(embedContext.node.value.data);
    final ((imageSize), margin, alignment) = getElementAttributes(
      embedContext.node,
      context,
    );

    final imageWidget = getImageWidgetByImageSource(
      context: context,
      imageSource,
      imageProviderBuilder: config.imageProviderBuilder,
      imageErrorWidgetBuilder: config.imageErrorWidgetBuilder,
      alignment: alignment,
      height: imageSize.height,
      width: imageSize.width,
    );

    final zoomable = ClipRect(
      child: InteractiveViewer(
        panEnabled: true,
        scaleEnabled: true,
        minScale: 1.0,
        maxScale: 5.0,
        child: imageWidget,
      ),
    );

    Widget content = zoomable;
    if (margin != null) {
      content = Padding(padding: EdgeInsets.all(margin), child: content);
    }

    return GestureDetector(
      onTap: () {
        final onImageClicked = config.onImageClicked;
        if (onImageClicked != null) {
          onImageClicked(imageSource);
          return;
        }

        showDialog(
          context: context,
          builder: (_) => ImageOptionsMenu(
            controller: embedContext.controller,
            config: config,
            imageSource: imageSource,
            imageSize: imageSize,
            readOnly: embedContext.readOnly,
            imageProvider: imageWidget.image,
          ),
        );
      },
      child: content,
    );
  }
}
