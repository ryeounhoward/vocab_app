import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../database/db_helper.dart';
import 'idiom_groups_page.dart';

class AddEditIdiomPage extends StatefulWidget {
  final Map<String, dynamic>? idiomItem;
  const AddEditIdiomPage({super.key, this.idiomItem});

  @override
  State<AddEditIdiomPage> createState() => _AddEditIdiomPageState();
}

class _AddEditIdiomPageState extends State<AddEditIdiomPage> {
  final _formKey = GlobalKey<FormState>();
  final dbHelper = DBHelper();

  final TextEditingController _idiomController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  List<TextEditingController> _exampleControllers = [TextEditingController()];
  String? _imagePath;
  bool _isDownloading = false;

  // Idiom group selection
  List<Map<String, dynamic>> _idiomGroups = [];
  int? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _loadIdiomGroups();
    if (widget.idiomItem != null) {
      _idiomController.text = widget.idiomItem!['idiom'] ?? "";
      _descController.text = widget.idiomItem!['description'] ?? "";
      _imagePath = widget.idiomItem!['image_path'];

      String savedExamples = widget.idiomItem!['examples'] as String? ?? "";
      if (savedExamples.isNotEmpty) {
        _exampleControllers = savedExamples
            .split('\n')
            .where((e) => e.trim().isNotEmpty)
            .map((e) => TextEditingController(text: e))
            .toList();
      }
    }
  }

  Future<void> _loadIdiomGroups() async {
    final groups = await dbHelper.getAllIdiomGroups();
    if (!mounted) return;
    setState(() {
      _idiomGroups = List<Map<String, dynamic>>.from(groups);
      // For now we don't pre-select groups for existing idioms; user can pick one.
      _selectedGroupId = null;
    });
  }

  String _toSentenceCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length == 1) {
      return trimmed.toUpperCase();
    }
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }

  String? _extractBetween(String source, String start, String? end) {
    final startIndex = source.indexOf(start);
    if (startIndex == -1) return null;
    final contentStart = startIndex + start.length;

    int endIndex;
    if (end != null) {
      endIndex = source.indexOf(end, contentStart);
      if (endIndex == -1) {
        endIndex = source.length;
      }
    } else {
      endIndex = source.length;
    }

    return source.substring(contentStart, endIndex).trim();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;

    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty or has no text.')),
      );
      return;
    }

    try {
      // Try to support both the word-style format and a simpler idiom format.
      final idiomFromWordFormat = _extractBetween(
        text,
        'Word:',
        'Type of Speech:',
      );
      final idiomFromIdiomLabel = _extractBetween(text, 'Idiom:', 'Meaning:');
      final idiom = idiomFromWordFormat ?? idiomFromIdiomLabel;

      final meaning =
          _extractBetween(text, 'Meaning:', 'Synonyms:') ??
          _extractBetween(text, 'Meaning:', 'Example 1:');
      final example1 = _extractBetween(text, 'Example 1:', 'Example 2:');
      final example2 = _extractBetween(text, 'Example 2:', 'Example 3:');
      final example3 = _extractBetween(text, 'Example 3:', null);

      if (idiom == null && (meaning == null && example1 == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard format not recognized.')),
        );
        return;
      }

      setState(() {
        if (idiom != null) {
          _idiomController.text = _toSentenceCase(idiom);
        }
        if (meaning != null) {
          _descController.text = _toSentenceCase(meaning);
        }

        _exampleControllers = [
          TextEditingController(text: example1 ?? ''),
          TextEditingController(text: example2 ?? ''),
          TextEditingController(text: example3 ?? ''),
        ];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text pasted into fields successfully.')),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to parse clipboard text.')),
      );
    }
  }

  Future<String?> _downloadImage(String url) async {
    try {
      setState(() => _isDownloading = true);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final documentDirectory = await getApplicationDocumentsDirectory();
        final imagesDir = Directory(
          path.join(documentDirectory.path, "images"),
        );
        if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

        String fileName = "idiom_${DateTime.now().millisecondsSinceEpoch}.png";
        File file = File(path.join(imagesDir.path, fileName));
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      debugPrint("Download error: $e");
    } finally {
      setState(() => _isDownloading = false);
    }
    return null;
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null) {
      final documentDirectory = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(documentDirectory.path, "images"));
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      String fileName =
          "idiom_gal_${DateTime.now().millisecondsSinceEpoch}${path.extension(pickedFile.path)}";
      String permanentPath = path.join(imagesDir.path, fileName);

      await File(pickedFile.path).copy(permanentPath);

      setState(() {
        _imagePath = permanentPath;
        _urlController.clear();
      });
    }
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      if (_urlController.text.isNotEmpty &&
          (_imagePath == null || _imagePath!.startsWith('http'))) {
        String? downloadedPath = await _downloadImage(_urlController.text);
        if (downloadedPath != null) {
          _imagePath = downloadedPath;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to download image.")),
          );
          return;
        }
      }

      String allExamples = _exampleControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .join('\n');

      final formattedIdiom = _toSentenceCase(_idiomController.text);
      final formattedDescription = _toSentenceCase(_descController.text);

      _idiomController.text = formattedIdiom;
      _descController.text = formattedDescription;

      final data = {
        'idiom': formattedIdiom,
        'description': formattedDescription,
        'examples': allExamples,
        'image_path': _imagePath,
        'is_favorite': widget.idiomItem?['is_favorite'] ?? 0,
      };

      int idiomId;
      if (widget.idiomItem == null) {
        idiomId = await dbHelper.insert(data, DBHelper.tableIdioms);
      } else {
        idiomId = widget.idiomItem!['id'] as int;
        await dbHelper.update({'id': idiomId, ...data}, DBHelper.tableIdioms);
      }

      // If a group is chosen, add this idiom to that group.
      if (_selectedGroupId != null) {
        await dbHelper.addIdiomToGroup(_selectedGroupId!, idiomId);
      }
      Navigator.pop(context);
    }
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.idiomItem == null ? "Add Idiom" : "Edit Idiom"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 40.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Image",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),
                // Image Preview (AspectRatio identical to original)
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _isDownloading
                        ? const Center(child: CircularProgressIndicator())
                        : (_imagePath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: Image.file(
                                    File(_imagePath!),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : const Icon(
                                  Icons.image,
                                  size: 50,
                                  color: Colors.grey,
                                )),
                  ),
                ),
                const SizedBox(height: 10),

                // Gallery Button (Matches your original request)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.photo_library),
                        label: const Text("Gallery"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                TextFormField(
                  controller: _urlController,
                  decoration: _inputStyle("Paste Image URL here"),
                  onChanged: (val) {
                    if (val.isNotEmpty) setState(() => _imagePath = null);
                  },
                ),
                const SizedBox(height: 20),

                const Text(
                  "Idiom Group",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                // Create / manage idiom groups button (same style as Gallery)
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const IdiomGroupsPage(),
                      ),
                    );
                    await _loadIdiomGroups();
                  },
                  icon: const Icon(Icons.group_add),
                  label: const Text('Create or manage idiom groups'),
                ),
                const SizedBox(height: 10),
                // Idiom group dropdown (same style as Word Type / Word Group)
                if (_idiomGroups.isNotEmpty) ...[
                  DropdownMenu<int?>(
                    width: MediaQuery.of(context).size.width - 32,
                    menuHeight: 250,
                    initialSelection: _selectedGroupId,
                    label: const Text('Idiom Group (optional)'),
                    onSelected: (value) {
                      setState(() {
                        _selectedGroupId = value;
                      });
                    },
                    dropdownMenuEntries: [
                      const DropdownMenuEntry<int?>(
                        value: null,
                        label: 'No group',
                      ),
                      ..._idiomGroups.map(
                        (g) => DropdownMenuEntry<int?>(
                          value: g['id'] as int?,
                          label: (g['name'] ?? '').toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                const Text(
                  "Idiom Details",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _idiomController,
                        decoration: _inputStyle("Idiom Phrase"),
                        validator: (v) => v!.isEmpty ? "Required" : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 56,
                      width: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _pasteFromClipboard,
                        child: Image.asset(
                          'assets/images/paste-button-1.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: _inputStyle("Definition"),
                ),
                const SizedBox(height: 20),

                const Text(
                  "Examples",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ..._exampleControllers.asMap().entries.map((entry) {
                  int idx = entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: entry.value,
                            decoration: _inputStyle("Example ${idx + 1}"),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle,
                            color: Colors.red,
                          ),
                          onPressed: () {
                            if (_exampleControllers.length > 1) {
                              setState(() => _exampleControllers.removeAt(idx));
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }),
                OutlinedButton.icon(
                  onPressed: () => setState(
                    () => _exampleControllers.add(TextEditingController()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text("Add Another Example"),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isDownloading ? null : _save,
                    child: _isDownloading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "SAVE IDIOM",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
