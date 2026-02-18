import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'cheat_sheet_html_preview_page.dart';
import 'cheat_sheet_pdf_preview_page.dart';
import 'cheat_sheet_doc.dart';

class CheatSheetPage extends StatefulWidget {
  const CheatSheetPage({super.key});

  @override
  State<CheatSheetPage> createState() => _CheatSheetPageState();
}

class _CheatSheetPageState extends State<CheatSheetPage> {
  static const _prefsKey = 'cheat_sheet_docs_v1';

  bool _loading = true;
  List<CheatSheetDoc> _docs = const [];

  @override
  void initState() {
    super.initState();
    _load();
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
      appBar: AppBar(title: const Text('Cheat Sheet')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _docs.isEmpty
            ? const Center(child: Text('No files yet'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      title: Text(doc.title),
                      subtitle: doc.subtitle.trim().isEmpty
                          ? null
                          : Text(doc.subtitle),
                      onTap: () => _openDoc(doc),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
