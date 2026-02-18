import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cheat_sheet_doc.dart';
import 'cheat_sheet_html_preview_page.dart';
import 'cheat_sheet_pdf_preview_page.dart';

class ManageCheatSheetPage extends StatefulWidget {
  const ManageCheatSheetPage({super.key});

  @override
  State<ManageCheatSheetPage> createState() => _ManageCheatSheetPageState();
}

class _ManageCheatSheetPageState extends State<ManageCheatSheetPage>
    with SingleTickerProviderStateMixin {
  static const _prefsKey = 'cheat_sheet_docs_v1';
  late final AnimationController _fabAnimationController;
  late final Animation<double> _fabScaleAnimation;
  late final Animation<double> _fabRotationAnimation;

  bool _loading = true;
  List<CheatSheetDoc> _docs = const [];

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fabScaleAnimation = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _fabAnimationController,
        curve: Curves.easeOutBack,
      ),
    );
    _fabRotationAnimation = Tween<double>(begin: 0.08, end: 0.0).animate(
      CurvedAnimation(
        parent: _fabAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _fabAnimationController.forward();
    _load();
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    List<CheatSheetDoc> items = [];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          items = decoded
              .whereType<Map<String, dynamic>>()
              .map(CheatSheetDoc.fromJson)
              .toList();
        }
      } catch (_) {
        items = [];
      }
    }

    if (!mounted) return;
    setState(() {
      _docs = items;
      _loading = false;
    });
  }

  Future<void> _save(List<CheatSheetDoc> docs) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(docs.map((d) => d.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  Future<Directory> _cheatSheetDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'cheat_sheets'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _addFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'html', 'htm'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final pickedPath = picked.path;
    if (pickedPath == null || pickedPath.trim().isEmpty) return;

    final fileName = picked.name;
    final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
    if (ext != 'pdf' && ext != 'html' && ext != 'htm') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only PDF and HTML files are supported')),
      );
      return;
    }

    final defaultTitle = p.basenameWithoutExtension(fileName);

    final titleController = TextEditingController(text: defaultTitle);
    final subtitleController = TextEditingController(text: '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${ext.toUpperCase()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Text name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: subtitleController,
              decoration: const InputDecoration(labelText: 'Subtext'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final title = titleController.text.trim();
    final subtitle = subtitleController.text.trim();
    if (title.isEmpty) return;

    final dir = await _cheatSheetDir();
    final unique = DateTime.now().millisecondsSinceEpoch;
    final safeFileName =
        '${p.basenameWithoutExtension(fileName)}_$unique.${ext == 'htm' ? 'html' : ext}';
    final destPath = p.join(dir.path, safeFileName);

    await File(pickedPath).copy(destPath);

    final doc = CheatSheetDoc(
      id: '$unique-${destPath.hashCode}',
      title: title,
      subtitle: subtitle,
      filePath: destPath,
      fileType: ext,
      createdAtMs: unique,
    );

    final updated = [doc, ..._docs];
    await _save(updated);

    if (!mounted) return;
    setState(() {
      _docs = updated;
    });
  }

  Future<void> _editDoc(CheatSheetDoc doc) async {
    final titleController = TextEditingController(text: doc.title);
    final subtitleController = TextEditingController(text: doc.subtitle);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Text name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: subtitleController,
              decoration: const InputDecoration(labelText: 'Subtext'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final title = titleController.text.trim();
    final subtitle = subtitleController.text.trim();
    if (title.isEmpty) return;

    final updated = _docs
        .map(
          (d) => d.id == doc.id
              ? CheatSheetDoc(
                  id: d.id,
                  title: title,
                  subtitle: subtitle,
                  filePath: d.filePath,
                  fileType: d.fileType,
                  createdAtMs: d.createdAtMs,
                )
              : d,
        )
        .toList();

    await _save(updated);

    if (!mounted) return;
    setState(() {
      _docs = updated;
    });
  }

  Future<void> _deleteDoc(CheatSheetDoc doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Delete "${doc.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final updated = _docs.where((d) => d.id != doc.id).toList();
    await _save(updated);

    try {
      final f = File(doc.filePath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _docs = updated;
    });
  }

  void _openDoc(CheatSheetDoc doc) {
    final type = doc.fileType.toLowerCase();
    if (type == 'html' || type == 'htm') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheatSheetHtmlPreviewPage(
            title: doc.title,
            filePath: doc.filePath,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CheatSheetPdfPreviewPage(title: doc.title, filePath: doc.filePath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Cheat Sheet')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _docs.isEmpty
            ? const Center(child: Text('No files yet'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: _docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final doc = _docs[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      contentPadding: const EdgeInsets.only(left: 16, right: 8),
                      title: Text(doc.title),
                      subtitle: doc.subtitle.trim().isEmpty
                          ? null
                          : Text(doc.subtitle),
                      onTap: () => _openDoc(doc),
                      trailing: SizedBox(
                        width: 40,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                _editDoc(doc);
                                break;
                              case 'delete':
                                _deleteDoc(doc);
                                break;
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnimation,
        child: RotationTransition(
          turns: _fabRotationAnimation,
          child: FloatingActionButton(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            onPressed: _addFile,
            child: const Icon(Icons.add),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButtonAnimator: FloatingActionButtonAnimator.scaling,
    );
  }
}
