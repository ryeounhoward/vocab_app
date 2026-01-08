import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../database/db_helper.dart';

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

  @override
  void initState() {
    super.initState();
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

  Future<String?> _downloadImage(String url) async {
    try {
      setState(() => _isDownloading = true);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final documentDirectory = await getApplicationDocumentsDirectory();
        String fileName = "idiom_${DateTime.now().millisecondsSinceEpoch}.png";
        File file = File(path.join(documentDirectory.path, fileName));
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

      final data = {
        'idiom': _idiomController.text,
        'description': _descController.text,
        'examples': allExamples,
        'image_path': _imagePath,
        'is_favorite': widget.idiomItem?['is_favorite'] ?? 0,
      };

      if (widget.idiomItem == null) {
        await dbHelper.insert(data, DBHelper.tableIdioms);
      } else {
        await dbHelper.update({
          'id': widget.idiomItem!['id'],
          ...data,
        }, DBHelper.tableIdioms);
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
                  "Idiom Details",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),

                TextFormField(
                  controller: _idiomController,
                  decoration: _inputStyle("Idiom Phrase"),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 15),

                TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: _inputStyle("Meaning / Description"),
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
