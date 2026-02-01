import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter_quill_extensions/src/common/utils/element_utils/element_utils.dart'
    show ElementSize, getElementAttributes;
import 'package:flutter_quill_extensions/src/common/utils/string.dart'
    show replaceStyleStringWithSize;
import 'package:flutter_quill_extensions/src/editor/image/image_menu.dart'
    show ImageOptionsMenu;
import 'package:flutter_quill_extensions/src/editor/image/widgets/image.dart'
    show getImageStyleString, getImageWidgetByImageSource, standardizeImageUrl;
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

    return _InlineResizableZoomableImageEmbed(
      controller: embedContext.controller,
      node: embedContext.node,
      readOnly: embedContext.readOnly,
      config: config,
      imageSource: imageSource,
      imageSize: imageSize,
      margin: margin,
      alignment: alignment,
      imageWidget: imageWidget,
    );
  }
}

class _InlineResizableZoomableImageEmbed extends StatefulWidget {
  const _InlineResizableZoomableImageEmbed({
    required this.controller,
    required this.node,
    required this.readOnly,
    required this.config,
    required this.imageSource,
    required this.imageSize,
    required this.margin,
    required this.alignment,
    required this.imageWidget,
  });

  final quill.QuillController controller;
  final quill.Node node;
  final bool readOnly;
  final QuillEditorImageEmbedConfig config;
  final String imageSource;
  final ElementSize imageSize;
  final double? margin;
  final Alignment alignment;
  final Image imageWidget;

  @override
  State<_InlineResizableZoomableImageEmbed> createState() =>
      _InlineResizableZoomableImageEmbedState();
}

class _InlineResizableZoomableImageEmbedState
    extends State<_InlineResizableZoomableImageEmbed> {
  bool _showHandles = false;
  double? _width;
  double? _height;

  bool _isResizing = false;

  Offset _moveDragTotal = Offset.zero;
  final ValueNotifier<Offset> _movePreviewOffset = ValueNotifier(Offset.zero);

  int? _lastEmbedOffset;

  double? _aspectRatio;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  final TransformationController _transformationController =
      TransformationController();
  double _currentScale = 1.0;

  double? _startWidth;
  double? _startHeight;

  int _safeLastIndexOf(String text, String pattern, int startIndex) {
    if (text.isEmpty) return -1;
    if (startIndex < 0) return -1;
    final capped = startIndex >= text.length ? text.length - 1 : startIndex;
    return text.lastIndexOf(pattern, capped);
  }

  int _resolveEmbedOffset(String docText) {
    // After we move an embed, `widget.node` can become stale (it refers to the
    // old node that was removed). The controller selection is updated in our
    // replaceText calls, so we can derive the current embed offset from it.
    final last = _lastEmbedOffset;
    if (last != null && last >= 0 && last < docText.length) return last;

    final sel = widget.controller.selection;
    final candidate = sel.baseOffset - 1;
    if (candidate >= 0 && candidate < docText.length) return candidate;
    final fallback = widget.node.documentOffset;
    if (fallback >= 0 && fallback < docText.length) return fallback;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _width = widget.imageSize.width;
    _height = widget.imageSize.height;
    _lastEmbedOffset = widget.node.documentOffset;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureAspectRatioResolved();
  }

  void _ensureAspectRatioResolved() {
    if (_aspectRatio != null) return;

    final provider = widget.imageWidget.image;
    final stream = provider.resolve(createLocalImageConfiguration(context));

    if (_imageStream?.key == stream.key) return;

    if (_imageStream != null && _imageStreamListener != null) {
      _imageStream!.removeListener(_imageStreamListener!);
    }

    _imageStream = stream;
    _imageStreamListener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (h <= 0) return;
      final ar = w / h;
      if (!ar.isFinite || ar <= 0) return;
      if (!mounted) return;
      setState(() => _aspectRatio = ar);
    });

    stream.addListener(_imageStreamListener!);
  }

  void _toggleHandles() {
    if (widget.readOnly) return;
    setState(() => _showHandles = !_showHandles);
  }

  void _openImageMenu() {
    showDialog(
      context: context,
      builder: (_) => ImageOptionsMenu(
        controller: widget.controller,
        config: widget.config,
        imageSource: widget.imageSource,
        imageSize: ElementSize(_width, _height),
        readOnly: widget.readOnly,
        imageProvider: widget.imageWidget.image,
      ),
    );
  }

  String _setCssProperty(String style, String key, String value) {
    final props = <String, String>{};
    final parts = style.split(';');
    for (final raw in parts) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      final idx = part.indexOf(':');
      if (idx <= 0) continue;
      final k = part.substring(0, idx).trim();
      final v = part.substring(idx + 1).trim();
      if (k.isEmpty) continue;
      props[k] = v;
    }
    props[key] = value;
    return props.entries.map((e) => '${e.key}: ${e.value}').join('; ');
  }

  void _applyAlignmentToDocument(String alignment) {
    final docText = widget.controller.document.toPlainText();
    final embedOffset = _resolveEmbedOffset(docText);
    final currentStyle =
        widget.node.style.attributes[quill.Attribute.style.key]?.value
            ?.toString() ??
        '';
    final baseStyle = currentStyle.isNotEmpty
        ? currentStyle
        : getImageStyleString(widget.controller);
    final nextStyle = _setCssProperty(baseStyle, 'alignment', alignment);

    final prevSkip = widget.controller.skipRequestKeyboard;
    widget.controller.skipRequestKeyboard = true;
    widget.controller.formatText(
      embedOffset,
      1,
      quill.StyleAttribute(nextStyle),
    );
    widget.controller.skipRequestKeyboard = prevSkip;
  }

  void _moveEmbedByOneLine({required bool down}) {
    final docText = widget.controller.document.toPlainText();
    final embedOffset = _resolveEmbedOffset(docText);

    final maxIndex = widget.controller.document.length - 1;
    if (embedOffset < 0 || embedOffset > maxIndex) return;

    if (embedOffset < 0 || embedOffset >= docText.length) return;

    // The EnsureEmbedLineRule usually keeps embeds on their own line.
    final lineStart = _safeLastIndexOf(docText, '\n', embedOffset - 1) + 1;
    final lineEnd = docText.indexOf('\n', embedOffset);
    if (lineEnd < 0) return;

    // Remove the embed and its trailing newline if present.
    final int removeLen =
        (embedOffset + 1 < docText.length &&
            docText.codeUnitAt(embedOffset + 1) == 10)
        ? 2
        : 1;

    int targetOffset;

    if (down) {
      final nextLineStart = lineEnd + 1;
      if (nextLineStart >= docText.length) return;
      final nextLineEnd = docText.indexOf('\n', nextLineStart);
      if (nextLineEnd < 0) return;
      targetOffset = nextLineEnd + 1;
    } else {
      if (lineStart <= 0) return;
      final prevLineEnd = _safeLastIndexOf(docText, '\n', lineStart - 2);
      if (prevLineEnd < 0) {
        targetOffset = 0;
      } else {
        final prevLineStart =
            _safeLastIndexOf(docText, '\n', prevLineEnd - 1) + 1;
        targetOffset = prevLineStart;
      }
    }

    if (targetOffset == embedOffset) return;

    // Preserve current style (width/height/alignment) while moving.
    final currentStyle =
        widget.node.style.attributes[quill.Attribute.style.key]?.value
            ?.toString() ??
        '';
    final styleToKeep = currentStyle.isNotEmpty
        ? currentStyle
        : getImageStyleString(widget.controller);

    var insertOffset = targetOffset;
    if (insertOffset > embedOffset) {
      insertOffset -= removeLen;
    }

    final prevSkip = widget.controller.skipRequestKeyboard;
    widget.controller.skipRequestKeyboard = true;

    try {
      widget.controller.replaceText(
        embedOffset,
        removeLen,
        '',
        TextSelection.collapsed(offset: embedOffset),
      );

      // IMPORTANT: after deletion, the document length changes.
      // Re-clamp the insertion offset to the *new* valid range.
      final newMaxInsert = (widget.controller.document.length - 1).clamp(
        0,
        1 << 30,
      );
      insertOffset = insertOffset.clamp(0, newMaxInsert).toInt();

      widget.controller.replaceText(
        insertOffset,
        0,
        quill.BlockEmbed.image(widget.imageSource),
        TextSelection.collapsed(
          offset: (insertOffset + 1).clamp(
            0,
            widget.controller.document.length,
          ),
        ),
      );

      widget.controller.formatText(
        insertOffset,
        1,
        quill.StyleAttribute(styleToKeep),
      );

      _lastEmbedOffset = insertOffset;
    } catch (_) {
      // Best-effort rollback: if insertion failed, try to put the image back
      // where it was so it never "disappears".
      try {
        final rollbackMax = (widget.controller.document.length - 1).clamp(
          0,
          1 << 30,
        );
        final rollbackOffset = embedOffset.clamp(0, rollbackMax).toInt();
        widget.controller.replaceText(
          rollbackOffset,
          0,
          quill.BlockEmbed.image(widget.imageSource),
          TextSelection.collapsed(
            offset: (rollbackOffset + 1).clamp(
              0,
              widget.controller.document.length,
            ),
          ),
        );
        widget.controller.formatText(
          rollbackOffset,
          1,
          quill.StyleAttribute(styleToKeep),
        );
        _lastEmbedOffset = rollbackOffset;
      } catch (_) {
        // Swallow: worst case, do nothing rather than crash.
      }
    } finally {
      widget.controller.skipRequestKeyboard = prevSkip;
    }
  }

  bool _ensureExtraEmptyLineAtEnd() {
    // Adds an extra newline right before the final document newline.
    // This creates an empty paragraph at the bottom so images can be moved down
    // even when they are currently on the last line.
    final len = widget.controller.document.length;
    if (len <= 1) return false;

    final insertAt = len - 1;
    final prevSkip = widget.controller.skipRequestKeyboard;
    widget.controller.skipRequestKeyboard = true;
    widget.controller.replaceText(
      insertAt,
      0,
      '\n',
      TextSelection.collapsed(offset: insertAt + 1),
    );
    widget.controller.skipRequestKeyboard = prevSkip;
    return true;
  }

  double _fallbackInitialWidth(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 320;
    final w = _width ?? 240;
    return w.clamp(80.0, maxWidth).toDouble();
  }

  double _fallbackInitialHeight(BoxConstraints constraints) {
    final maxHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : MediaQuery.sizeOf(context).height;
    final h = _height ?? 180;
    return h.clamp(80.0, maxHeight).toDouble();
  }

  ({double width, double height}) _effectiveSize(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 320;
    final maxHeight = MediaQuery.sizeOf(context).height;

    // Prefer the intrinsic aspect ratio when available. If not, fall back to the
    // stored size's ratio (if present).
    final ar =
        _aspectRatio ??
        ((widget.imageSize.width != null && widget.imageSize.height != null)
            ? (widget.imageSize.width! / widget.imageSize.height!)
            : null);

    final baseWidth = _fallbackInitialWidth(constraints);
    final baseHeight = _fallbackInitialHeight(constraints);

    var width = baseWidth;
    var height = baseHeight;

    if (ar != null && ar.isFinite && ar > 0) {
      // Keep the box matching the image ratio to avoid "empty" sides.
      width = width.clamp(80.0, maxWidth).toDouble();
      height = (width / ar).clamp(80.0, maxHeight).toDouble();

      // If height clamping forced a smaller/larger height, recompute width.
      width = (height * ar).clamp(80.0, maxWidth).toDouble();
      height = (width / ar).clamp(80.0, maxHeight).toDouble();
    } else {
      width = width.clamp(80.0, maxWidth).toDouble();
      height = height.clamp(80.0, maxHeight).toDouble();
    }

    return (width: width, height: height);
  }

  void _applySizeToDocument({required double width, required double height}) {
    final docText = widget.controller.document.toPlainText();
    final embedOffset = _resolveEmbedOffset(docText);

    // IMPORTANT: flutter_quill has a format rule for image embeds that expects
    // sizing to be stored in the 'style' attribute string (handled by
    // ResolveImageFormatRule). Using Attribute.width/height directly can throw:
    // "Apply delta rules failed. No matching rule found for type: RuleType.format".

    final currentStyle =
        widget.node.style.attributes[quill.Attribute.style.key]?.value
            ?.toString() ??
        '';
    final nextStyle = replaceStyleStringWithSize(
      currentStyle.isNotEmpty
          ? currentStyle
          : getImageStyleString(widget.controller),
      width: width,
      height: height,
    );

    final prevSkip = widget.controller.skipRequestKeyboard;
    widget.controller.skipRequestKeyboard = true;
    widget.controller.formatText(
      embedOffset,
      1,
      quill.StyleAttribute(nextStyle),
    );
    widget.controller.skipRequestKeyboard = prevSkip;
  }

  @override
  void didUpdateWidget(covariant _InlineResizableZoomableImageEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isResizing) return;
    // Keep in sync when size is changed by the menu or external edits.
    final newWidth = widget.imageSize.width;
    final newHeight = widget.imageSize.height;
    if (newWidth != _width || newHeight != _height) {
      _width = newWidth;
      _height = newHeight;
    }
    _lastEmbedOffset = widget.node.documentOffset;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _effectiveSize(constraints);
        final effectiveWidth = size.width;
        final effectiveHeight = size.height;

        // IMPORTANT:
        // `InteractiveViewer` will try to expand under loose constraints.
        // Wrapping it with a tight `SizedBox` ensures the border/handles match
        // the actual image box (no full-width "empty" area).
        final zoomable = SizedBox(
          width: effectiveWidth,
          height: effectiveHeight,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _transformationController,
              onInteractionUpdate: (_) {
                final next = _transformationController.value
                    .getMaxScaleOnAxis();
                if (!next.isFinite) return;
                // Only rebuild when crossing the "pannable" threshold.
                final wasPannable = _currentScale > 1.01;
                final isPannable = next > 1.01;
                _currentScale = next;
                if (wasPannable != isPannable && mounted) {
                  setState(() {});
                }
              },
              // Prevent the common "snaps back" feeling by allowing extra
              // movement beyond the tight viewport bounds when zoomed.
              boundaryMargin: const EdgeInsets.all(1000),
              panEnabled: _currentScale > 1.01,
              scaleEnabled: true,
              minScale: 1.0,
              maxScale: 5.0,
              child: RepaintBoundary(
                child: SizedBox.expand(
                  child: Image(
                    image: widget.imageWidget.image,
                    fit: BoxFit.contain,
                    alignment: widget.alignment,
                    errorBuilder: widget.imageWidget.errorBuilder,
                  ),
                ),
              ),
            ),
          ),
        );

        final edgePadding = widget.margin != null
            ? EdgeInsets.all(widget.margin!)
            : null;

        return Padding(
          padding: edgePadding ?? EdgeInsets.zero,
          child: GestureDetector(
            onTap: _toggleHandles,
            onLongPress: _openImageMenu,
            child: ValueListenableBuilder<Offset>(
              valueListenable: _movePreviewOffset,
              builder: (context, previewOffset, child) {
                return Transform.translate(offset: previewOffset, child: child);
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  zoomable,
                  if (_showHandles)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.indigo, width: 2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  if (_showHandles && !widget.readOnly) ...[
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: _ResizeHandle(
                        onPanStart: () {
                          FocusScope.of(context).unfocus();
                          _isResizing = true;
                          _startWidth = effectiveWidth;
                          _startHeight = effectiveHeight;

                          // Ensure we have a stable "current" size to accumulate
                          // deltas against during the drag.
                          _width ??= effectiveWidth;
                          _height ??= effectiveHeight;
                        },
                        onPanUpdate: (delta) {
                          final startW = _startWidth ?? effectiveWidth;
                          final startH = _startHeight ?? effectiveHeight;

                          // IMPORTANT: `delta` is per-frame. For smooth resizing we
                          // must accumulate against the latest size, not always
                          // against the start size.
                          final baseW = _width ?? startW;
                          final baseH = _height ?? startH;

                          final maxW = constraints.maxWidth.isFinite
                              ? constraints.maxWidth
                              : startW + 2000;
                          final maxH = MediaQuery.sizeOf(context).height;

                          final ar = _aspectRatio;

                          double nextW;
                          double nextH;
                          if (ar != null && ar.isFinite && ar > 0) {
                            final wFromDx = baseW + delta.dx;
                            final hFromDy = baseH + delta.dy;
                            final wFromDy = hFromDy * ar;

                            // If the user drags mostly vertically, still resize.
                            final useDx =
                                delta.dx.abs() >= (delta.dy.abs() * ar);
                            final proposedW = (useDx ? wFromDx : wFromDy)
                                .clamp(80.0, maxW)
                                .toDouble();

                            nextW = proposedW;
                            nextH = (nextW / ar).clamp(80.0, maxH).toDouble();

                            // If height was clamped, recompute width to keep ratio.
                            nextW = (nextH * ar).clamp(80.0, maxW).toDouble();
                            nextH = (nextW / ar).clamp(80.0, maxH).toDouble();
                          } else {
                            nextW = (baseW + delta.dx)
                                .clamp(80.0, maxW)
                                .toDouble();
                            nextH = (baseH + delta.dy)
                                .clamp(80.0, maxH)
                                .toDouble();
                          }

                          setState(() {
                            _width = nextW;
                            _height = nextH;
                          });
                        },
                        onPanEnd: () {
                          final w = _width ?? effectiveWidth;
                          final h = _height ?? effectiveHeight;
                          _applySizeToDocument(width: w, height: h);
                          // Keep the visual size stable until the document
                          // notifies listeners and rebuilds with the new attrs.
                          _isResizing = false;
                        },
                      ),
                    ),
                    Positioned(
                      left: -6,
                      bottom: -6,
                      child: _MoveHandle(
                        onPanStart: () {
                          FocusScope.of(context).unfocus();
                          _moveDragTotal = Offset.zero;
                          _movePreviewOffset.value = Offset.zero;
                        },
                        onPanUpdate: (delta) {
                          _moveDragTotal += delta;
                          // Provide immediate visual feedback without touching
                          // the document while dragging.
                          _movePreviewOffset.value = Offset(
                            _moveDragTotal.dx.clamp(-600.0, 600.0).toDouble(),
                            _moveDragTotal.dy.clamp(-600.0, 600.0).toDouble(),
                          );
                        },
                        onPanEnd: () {
                          final dx = _moveDragTotal.dx;
                          final dy = _moveDragTotal.dy;
                          _movePreviewOffset.value = Offset.zero;

                          // Horizontal drag: change alignment.
                          if (dx.abs() >= 30 && dx.abs() >= dy.abs()) {
                            _applyAlignmentToDocument(
                              dx < 0 ? 'centerLeft' : 'centerRight',
                            );
                            return;
                          }

                          // Vertical drag: reorder by multiple lines.
                          if (dy.abs() >= 12) {
                            final down = dy > 0;
                            final steps = (dy.abs() / 40)
                                .round()
                                .clamp(1, 25)
                                .toInt();

                            for (var i = 0; i < steps; i++) {
                              // If moving down near the end, create space first.
                              if (down) {
                                final before = widget.controller.document
                                    .toPlainText();
                                final embedOffset = _resolveEmbedOffset(before);
                                final lineEnd = before.indexOf(
                                  '\n',
                                  embedOffset,
                                );
                                final nextLineStart = lineEnd + 1;
                                if (lineEnd >= 0 &&
                                    nextLineStart >= before.length) {
                                  _ensureExtraEmptyLineAtEnd();
                                }
                              }
                              _moveEmbedByOneLine(down: down);
                            }
                          }
                        },
                      ),
                    ),
                    Positioned(
                      top: -10,
                      right: -10,
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          tooltip: 'Image menu',
                          onPressed: _openImageMenu,
                          icon: const Icon(Icons.more_vert, size: 20),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageStreamListener != null) {
      _imageStream!.removeListener(_imageStreamListener!);
    }
    _transformationController.dispose();
    _movePreviewOffset.dispose();
    super.dispose();
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final VoidCallback onPanStart;
  final void Function(Offset delta) onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    // Larger hit-target (one finger) + mouse cursor (desktop).
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpLeftDownRight,
      child: Tooltip(
        message: 'Drag to resize',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) => onPanStart(),
          onPanUpdate: (details) => onPanUpdate(details.delta),
          onPanEnd: (_) => onPanEnd(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.indigo, width: 2),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.open_in_full,
                  size: 14,
                  color: Colors.indigo,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoveHandle extends StatelessWidget {
  const _MoveHandle({
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final VoidCallback onPanStart;
  final void Function(Offset delta) onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: Tooltip(
        message: 'Drag to move (left/right align, up/down reorder)',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) => onPanStart(),
          onPanUpdate: (details) => onPanUpdate(details.delta),
          onPanEnd: (_) => onPanEnd(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.indigo, width: 2),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.open_with,
                  size: 14,
                  color: Colors.indigo,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
