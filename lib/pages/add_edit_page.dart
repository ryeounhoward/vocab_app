import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:google_generative_ai/google_generative_ai.dart';
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

  // --- Gemini API Setup ---
  // IMPORTANT: Never share your API Key publicly.
  String? _apiKey;
  String _modelName = 'gemini-2.5-flash';
  String _buttonImageAsset = 'assets/images/gemini-2.png';
  bool _isGenerating = false;

  final TextEditingController _wordController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _synonymsController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  List<TextEditingController> _exampleControllers = [TextEditingController()];

  String? _wordType = 'Noun';
  String? _imagePath;
  bool _isDownloading = false;

  List<String> _types = [
    'Noun',
    'Verb',
    'Pronoun',
    'Adverb',
    'Adjective',
    'Preposition',
    'Conjunction',
    'Interjection',
  ];

  final String _addNewTypeLabel = 'Add new type';

  @override
  void initState() {
    super.initState();
    _loadGeminiSettings();
    if (widget.vocabItem != null) {
      _wordController.text = widget.vocabItem!['word'] ?? "";
      _descController.text = widget.vocabItem!['description'] ?? "";
      _synonymsController.text = widget.vocabItem!['synonyms'] ?? "";
      _wordType = widget.vocabItem!['word_type'];
      _imagePath = widget.vocabItem!['image_path'];

      if (_wordType != null && !_types.contains(_wordType)) {
        _types.add(_wordType!);
      }

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

  Future<void> _loadGeminiSettings() async {
    // Fallback to the hardcoded key if no preference is stored yet
    const String fallbackKey = "AIzaSyBl_0tLrrwrGUCz8htLEi9l6rl0dqimw4I";

    final String? storedKey = await dbHelper.getPreference('gemini_api_key');
    final String? storedModel = await dbHelper.getPreference('gemini_model');
    final String? storedButton = await dbHelper.getPreference(
      'gemini_button_image',
    );

    if (!mounted) return;

    setState(() {
      _apiKey = (storedKey != null && storedKey.isNotEmpty)
          ? storedKey
          : fallbackKey;

      if (storedModel != null && storedModel.isNotEmpty) {
        _modelName = storedModel;
      }

      if (storedButton != null && storedButton.isNotEmpty) {
        _buttonImageAsset = storedButton;
      }
    });
  }

  Future<void> _generateWithAI() async {
    final inputWord = _wordController.text.trim();
    if (inputWord.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a word first")),
      );
      return;
    }

    if (_apiKey == null || _apiKey!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please set your Gemini API key in Settings > APIs."),
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // Use the configured Gemini model and API key
      final model = GenerativeModel(model: _modelName, apiKey: _apiKey!);

      // Your exact personal instructions for the prompt
      final prompt =
          '''
    Instructions:
    When I provide a vocabulary word, create a structured vocabulary card with the following sections: 
    - Word: use the root form of the word, for idioms, use the original idiom form.
    - Type of Speech: identify the word using one of the 8 standard parts of speech in English only: Noun, Pronoun, Verb, Adjective, Adverb, Preposition, Conjunction, Interjection.
    - Meaning: state the meaning directly and clearly, concise paragraph, no extra commentary.
    - Synonyms: present in comma-separated format, with each synonym starting with an uppercase letter.
    - Examples: provide at least three clear example sentences using the word naturally.

    Word to process: "$inputWord"

    Return the result ONLY as a valid raw JSON object with these keys:
    "word", "type", "meaning", "synonyms", "examples" (where examples is an array of strings).
    ''';

      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text;

      if (text != null) {
        // 1. Remove markdown formatting if the AI includes it
        String jsonString = text;
        if (jsonString.contains('```')) {
          jsonString = jsonString.split(
            '```',
          )[1]; // Get content between backticks
          if (jsonString.startsWith('json')) {
            jsonString = jsonString.substring(4); // Remove the word 'json'
          }
        }

        final Map<String, dynamic> data = jsonDecode(jsonString.trim());

        setState(() {
          _wordController.text = data['word'] ?? inputWord;
          _descController.text = data['meaning'] ?? "";
          _synonymsController.text = data['synonyms'] ?? "";

          // Normalize Type to match your Dropdown (e.g., 'verb' -> 'Verb')
          String rawType = data['type'] ?? 'Noun';
          String capitalizedType = rawType.trim().isNotEmpty
              ? "${rawType[0].toUpperCase()}${rawType.substring(1).toLowerCase()}"
              : "Noun";

          // Match against your 8 specific types
          if (_types.contains(capitalizedType)) {
            _wordType = capitalizedType;
          } else {
            // Fallback logic if AI provides something like "Phrasal Verb"
            if (!_types.contains(capitalizedType)) _types.add(capitalizedType);
            _wordType = capitalizedType;
          }

          // Handle Examples
          List<dynamic> aiExamples = data['examples'] ?? [];
          if (aiExamples.isNotEmpty) {
            _exampleControllers = aiExamples
                .map((e) => TextEditingController(text: e.toString()))
                .toList();
          }
        });
      }
    } catch (e) {
      debugPrint("AI error: $e");
      String userFriendlyError = "Failed to generate. ";
      if (e.toString().contains("429")) {
        userFriendlyError += "Too many requests. Please wait 30 seconds.";
      } else {
        userFriendlyError += "Make sure your internet is connected.";
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFriendlyError)));
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  // --- Helper methods (Saving, Picking Image, etc.) remain the same as your code ---
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
        String fileName = "vocab_${DateTime.now().millisecondsSinceEpoch}.png";
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
          "gallery_${DateTime.now().millisecondsSinceEpoch}${path.extension(pickedFile.path)}";
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
        if (downloadedPath != null) _imagePath = downloadedPath;
      }
      String allExamples = _exampleControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .join('\n');
      final data = {
        'word': _wordController.text,
        'description': _descController.text,
        'synonyms': _synonymsController.text.trim(),
        'examples': allExamples,
        'word_type': _wordType,
        'image_path': _imagePath,
      };
      if (widget.vocabItem == null) {
        await dbHelper.insert(data);
      } else {
        await dbHelper.update({'id': widget.vocabItem!['id'], ...data});
      }
      Navigator.pop(context);
    }
  }

  InputDecoration _inputStyle(String label) => InputDecoration(
    labelText: label,
    alignLabelWithHint: true,
    border: const OutlineInputBorder(),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );

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
                // ... Image UI remains the same ...
                const Text(
                  "Image",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),
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
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text("Gallery"),
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
                  "Word Details",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),

                // WORD + AI BUTTON
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _wordController,
                        decoration: _inputStyle("Word"),
                        validator: (v) => v!.isEmpty ? "Required" : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 56, // match TextFormField default height
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
                        onPressed: _isGenerating ? null : _generateWithAI,
                        child: _isGenerating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Image.asset(
                                _buttonImageAsset,
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // DROPDOWN
                DropdownMenu<String>(
                  width: MediaQuery.of(context).size.width - 32,
                  menuHeight: 250,
                  initialSelection: _wordType,
                  label: const Text("Word Type"),
                  onSelected: (value) async {
                    if (value == _addNewTypeLabel) {
                      final newType = await _showAddWordTypeDialog();
                      if (newType != null && newType.trim().isNotEmpty) {
                        setState(() {
                          if (!_types.contains(newType.trim()))
                            _types.add(newType.trim());
                          _wordType = newType.trim();
                        });
                      }
                    } else {
                      setState(() => _wordType = value);
                    }
                  },
                  dropdownMenuEntries: [
                    ..._types.map(
                      (t) => DropdownMenuEntry<String>(value: t, label: t),
                    ),
                    DropdownMenuEntry<String>(
                      value: _addNewTypeLabel,
                      label: _addNewTypeLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: _inputStyle("Description (Meaning)"),
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _synonymsController,
                  maxLines: 2,
                  decoration: _inputStyle("Synonyms"),
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
                            if (_exampleControllers.length > 1)
                              setState(() => _exampleControllers.removeAt(idx));
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
                    onPressed: _isDownloading || _isGenerating ? null : _save,
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

  Future<String?> _showAddWordTypeDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add new type of speech'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Type'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
