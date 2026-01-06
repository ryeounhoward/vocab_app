import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http; // New for downloading
import 'package:path_provider/path_provider.dart'; // New for saving files
import 'package:path/path.dart' as path; // New for naming files
import '../database/db_helper.dart';

class AddEditPage extends StatefulWidget {
  final Map<String, dynamic>? vocabItem;
  const AddEditPage({super.key, this.vocabItem});

  @override
  State<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends State<AddEditPage> {
  final _formKey = GlobalKey<FormState>();
  final dbHelper = DBHelper();

  final TextEditingController _wordController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _urlController = TextEditingController(); // New

  List<TextEditingController> _exampleControllers = [TextEditingController()];

  String? _wordType = 'Noun';
  String? _imagePath;
  bool _isDownloading = false; // To show loading while downloading image

  final List<String> _types = [
    'Noun',
    'Verb',
    'Pronoun',
    'Adverb',
    'Adjective',
    'Prepositions',
    'Conjunctions',
    'Interjection',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.vocabItem != null) {
      _wordController.text = widget.vocabItem!['word'] ?? "";
      _descController.text = widget.vocabItem!['description'] ?? "";
      _wordType = widget.vocabItem!['word_type'];
      _imagePath = widget.vocabItem!['image_path'];

      String savedExamples = widget.vocabItem!['examples'] as String? ?? "";
      if (savedExamples.isNotEmpty) {
        _exampleControllers = savedExamples
            .split('\n')
            .where((String e) => e.trim().isNotEmpty)
            .map((String e) => TextEditingController(text: e))
            .toList();
      }
    }
  }

  // --- NEW: Function to download image from URL ---
  Future<String?> _downloadImage(String url) async {
    try {
      setState(() => _isDownloading = true);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        // Get directory to save the image
        final documentDirectory = await getApplicationDocumentsDirectory();
        // Create a unique filename
        String fileName =
            "downloaded_${DateTime.now().millisecondsSinceEpoch}.png";
        File file = File(path.join(documentDirectory.path, fileName));
        // Write the bytes to a local file
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
      setState(() {
        _imagePath = pickedFile.path;
        _urlController.clear(); // Clear URL if gallery is used
      });
    }
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      // Logic: If URL is provided and no gallery image was picked, download it first
      if (_urlController.text.isNotEmpty &&
          (_imagePath == null || _imagePath!.startsWith('http'))) {
        String? downloadedPath = await _downloadImage(_urlController.text);
        if (downloadedPath != null) {
          _imagePath = downloadedPath;
        } else {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Failed to download image. Check the link or internet.",
              ),
            ),
          );
          return;
        }
      }

      String allExamples = _exampleControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .join('\n');

      final data = {
        'word': _wordController.text,
        'description': _descController.text,
        'examples': allExamples,
        'word_type': _wordType,
        'image_path': _imagePath,
      };

      if (widget.vocabItem == null) {
        await dbHelper.insert(data);
      } else {
        await dbHelper.update({'id': widget.vocabItem!['id'], ...data});
      }
      // ignore: use_build_context_synchronously
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
        title: Text(widget.vocabItem == null ? "Add Word" : "Edit Word"),
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
                // Image Preview
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

                // Buttons for choosing image
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

                // NEW: Image URL Input
                TextFormField(
                  controller: _urlController,
                  decoration: _inputStyle("Paste Image URL here"),
                  onChanged: (val) {
                    if (val.isNotEmpty) setState(() => _imagePath = null);
                  },
                ),
                const SizedBox(height: 20),

                const Text(
                  "Word Details",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),

                TextFormField(
                  controller: _wordController,
                  decoration: _inputStyle("Word"),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 15),

                // Use this if you want the popup to look like a separate floating card
                DropdownMenu<String>(
                  width:
                      MediaQuery.of(context).size.width -
                      32, // Full width minus margins
                  initialSelection: _wordType,
                  label: const Text("Word Type"),
                  onSelected: (v) => setState(() => _wordType = v),
                  dropdownMenuEntries: _types.map((t) {
                    return DropdownMenuEntry<String>(value: t, label: t);
                  }).toList(),
                  // Styling the menu card
                  menuStyle: MenuStyle(
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: _inputStyle("Description"),
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
                  onPressed: _addExampleField,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Another Example"),
                ),

                const SizedBox(height: 10),

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
                            "SAVE VOCABULARY",
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

  void _addExampleField() {
    setState(() => _exampleControllers.add(TextEditingController()));
  }
}
