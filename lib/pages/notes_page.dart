import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter_quill_extensions/src/common/utils/element_utils/element_utils.dart'
    show ElementSize, getElementAttributes;
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

  double? _aspectRatio;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  double? _startWidth;
  double? _startHeight;

  @override
  void initState() {
    super.initState();
    _width = widget.imageSize.width;
    _height = widget.imageSize.height;
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
    final selectionBefore = widget.controller.selection;
    final embedOffset = widget.node.documentOffset;

    // Select the embed (length=1) so formatting applies to it.
    widget.controller.updateSelection(
      TextSelection(baseOffset: embedOffset, extentOffset: embedOffset + 1),
      quill.ChangeSource.local,
    );

    widget.controller.formatSelection(
      quill.Attribute.clone(quill.Attribute.width, width.toStringAsFixed(0)),
    );
    widget.controller.formatSelection(
      quill.Attribute.clone(quill.Attribute.height, height.toStringAsFixed(0)),
    );

    // Restore the user's selection.
    widget.controller.updateSelection(
      selectionBefore,
      quill.ChangeSource.local,
    );
  }

  @override
  void didUpdateWidget(covariant _InlineResizableZoomableImageEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep in sync when size is changed by the menu or external edits.
    final newWidth = widget.imageSize.width;
    final newHeight = widget.imageSize.height;
    if (newWidth != _width || newHeight != _height) {
      _width = newWidth;
      _height = newHeight;
    }
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
              panEnabled: true,
              scaleEnabled: true,
              minScale: 1.0,
              maxScale: 5.0,
              child: Align(
                alignment: widget.alignment,
                child: widget.imageWidget,
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
                        _startWidth = effectiveWidth;
                        _startHeight = effectiveHeight;
                      },
                      onPanUpdate: (delta) {
                        final startW = _startWidth ?? effectiveWidth;
                        final startH = _startHeight ?? effectiveHeight;

                        final maxW = constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : startW + 2000;
                        final maxH = MediaQuery.sizeOf(context).height;

                        final ar = _aspectRatio;

                        double nextW;
                        double nextH;
                        if (ar != null && ar.isFinite && ar > 0) {
                          nextW = (startW + delta.dx)
                              .clamp(80.0, maxW)
                              .toDouble();
                          nextH = (nextW / ar).clamp(80.0, maxH).toDouble();

                          // If height was clamped, recompute width to keep ratio.
                          nextW = (nextH * ar).clamp(80.0, maxW).toDouble();
                          nextH = (nextW / ar).clamp(80.0, maxH).toDouble();
                        } else {
                          nextW = (startW + delta.dx)
                              .clamp(80.0, maxW)
                              .toDouble();
                          nextH = (startH + delta.dy)
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
        );
      },
    );
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageStreamListener != null) {
      _imageStream!.removeListener(_imageStreamListener!);
    }
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
