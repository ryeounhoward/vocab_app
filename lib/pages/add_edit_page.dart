import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../services/ai_defaults.dart';
import 'word_groups_page.dart';

class _RelatedFormFields {
  final TextEditingController formController;
  final TextEditingController typeController;
  final TextEditingController meaningController;
  final TextEditingController exampleController;

  _RelatedFormFields({
    String form = '',
    String type = '',
    String meaning = '',
    String example = '',
  }) : formController = TextEditingController(text: form),
       typeController = TextEditingController(text: type),
       meaningController = TextEditingController(text: meaning),
       exampleController = TextEditingController(text: example);

  void dispose() {
    formController.dispose();
    typeController.dispose();
    meaningController.dispose();
    exampleController.dispose();
  }
}

class AddEditPage extends StatefulWidget {
  final Map<String, dynamic>? vocabItem;
  const AddEditPage({super.key, this.vocabItem});

  @override
  State<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends State<AddEditPage> {
  static const String _defaultWordGroupPrefKey = 'default_word_group_id';

  final _formKey = GlobalKey<FormState>();
  final dbHelper = DBHelper();

  // --- Gemini API Setup ---
  // IMPORTANT: Never share your API Key publicly.
  String? _apiKey;
  String _modelName = 'gemini-2.5-flash';
  String _buttonImageAsset = 'assets/images/gemini-2.png';
  bool _isGenerating = false;
  // System-level instructions for Gemini (personalized context)
  String _aiSystemInstructions = defaultGeminiVocabInstructions;

  final TextEditingController _wordController = TextEditingController();
  final TextEditingController _pronunciationController =
      TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _synonymsController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  List<TextEditingController> _exampleControllers = [TextEditingController()];
  List<_RelatedFormFields> _relatedFormControllers = [_RelatedFormFields()];
  final List<String> _tenseOrder = const [
    'Present Tense',
    'Past Tense',
    'Present Participle',
    'Past Participle',
    'Present Perfect',
    'Past Perfect',
    'Future Perfect',
  ];
  late final Map<String, TextEditingController> _tenseConjugationControllers;
  late final Map<String, TextEditingController> _tenseExampleControllers;

  String? _wordType = 'Noun';
  String? _imagePath;
  bool _isDownloading = false;
  bool _showRelatedForms = false;
  bool _showTenseConjugationForm = false;

  // Word group selection
  List<Map<String, dynamic>> _wordGroups = [];
  int? _selectedGroupId;
  int? _defaultGroupId;

  final List<String> _types = [
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
    _loadTenseDefaultPreference();
    _tenseConjugationControllers = {
      for (final tense in _tenseOrder) tense: TextEditingController(),
    };
    _tenseExampleControllers = {
      for (final tense in _tenseOrder) tense: TextEditingController(),
    };
    _loadGeminiSettings();
    _loadWordGroups();
    if (widget.vocabItem != null) {
      _wordController.text = widget.vocabItem!['word'] ?? "";
      _pronunciationController.text = widget.vocabItem!['pronunciation'] ?? "";
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

      final String rawRelatedForms =
          widget.vocabItem!['related_forms'] as String? ?? '';
      if (rawRelatedForms.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawRelatedForms);
          if (decoded is List) {
            final parsed = decoded
                .whereType<Map>()
                .map(
                  (entry) => _RelatedFormFields(
                    form: (entry['form'] ?? '').toString(),
                    type: (entry['type'] ?? '').toString(),
                    meaning: (entry['meaning'] ?? '').toString(),
                    example: (entry['example'] ?? '').toString(),
                  ),
                )
                .where(
                  (entry) =>
                      entry.formController.text.trim().isNotEmpty ||
                      entry.typeController.text.trim().isNotEmpty ||
                      entry.meaningController.text.trim().isNotEmpty ||
                      entry.exampleController.text.trim().isNotEmpty,
                )
                .toList();
            if (parsed.isNotEmpty) {
              _disposeRelatedForms();
              _relatedFormControllers = parsed;
            }
          }
        } catch (_) {}
      }

      final String rawTenseData =
          widget.vocabItem!['tense_data'] as String? ?? '';
      if (rawTenseData.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawTenseData);
          if (decoded is Map<String, dynamic>) {
            for (final tense in _tenseOrder) {
              final value = decoded[tense];
              if (value is Map<String, dynamic>) {
                _tenseConjugationControllers[tense]?.text =
                    (value['conjugation'] ?? '').toString();
                _tenseExampleControllers[tense]?.text = (value['example'] ?? '')
                    .toString();
              }
            }
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _loadTenseDefaultPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final bool showByDefault = prefs.getBool('show_tenses_by_default') ?? false;
    if (!mounted) return;
    setState(() {
      _showRelatedForms = showByDefault;
      _showTenseConjugationForm = showByDefault;
    });
  }

  @override
  void dispose() {
    _wordController.dispose();
    _pronunciationController.dispose();
    _descController.dispose();
    _synonymsController.dispose();
    _urlController.dispose();
    _searchDisposeExamples();
    _disposeRelatedForms();
    for (final controller in _tenseConjugationControllers.values) {
      controller.dispose();
    }
    for (final controller in _tenseExampleControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _searchDisposeExamples() {
    for (final controller in _exampleControllers) {
      controller.dispose();
    }
  }

  void _disposeRelatedForms() {
    for (final item in _relatedFormControllers) {
      item.dispose();
    }
  }

  Future<void> _loadWordGroups() async {
    final groups = await dbHelper.getAllWordGroups();
    final String? defaultGroupRaw = await dbHelper.getPreference(
      _defaultWordGroupPrefKey,
    );
    final int? parsedDefaultGroupId = int.tryParse(defaultGroupRaw ?? '');

    final bool defaultGroupExists =
        parsedDefaultGroupId != null &&
        groups.any((g) => g['id'] == parsedDefaultGroupId);
    final int? resolvedDefaultGroupId = defaultGroupExists
        ? parsedDefaultGroupId
        : null;

    if (parsedDefaultGroupId != null && !defaultGroupExists) {
      await dbHelper.removePreference(_defaultWordGroupPrefKey);
    }

    if (!mounted) return;

    setState(() {
      _wordGroups = List<Map<String, dynamic>>.from(groups);
      _defaultGroupId = resolvedDefaultGroupId;

      if (widget.vocabItem == null) {
        _selectedGroupId = resolvedDefaultGroupId;
      }
    });
  }

  Future<void> _setSelectedAsDefaultGroup() async {
    if (_selectedGroupId == null) return;

    await dbHelper.setPreference(
      _defaultWordGroupPrefKey,
      _selectedGroupId!.toString(),
    );

    if (!mounted) return;
    setState(() {
      _defaultGroupId = _selectedGroupId;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Default word group updated.')),
    );
  }

  Future<void> _clearDefaultGroup() async {
    await dbHelper.removePreference(_defaultWordGroupPrefKey);

    if (!mounted) return;
    setState(() {
      _defaultGroupId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Default word group cleared.')),
    );
  }

  Future<void> _loadGeminiSettings() async {
    // Fallback to the hardcoded key if no preference is stored yet
    const String fallbackKey = "AIzaSyBl_0tLrrwrGUCz8htLEi9l6rl0dqimw4I";

    final String? storedKey = await dbHelper.getPreference('gemini_api_key');
    final String? storedModel = await dbHelper.getPreference('gemini_model');
    final String? storedButton = await dbHelper.getPreference(
      'gemini_button_image',
    );
    final String? storedInstructions = await dbHelper.getPreference(
      'gemini_system_instructions',
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

      if (storedInstructions != null && storedInstructions.isNotEmpty) {
        _aiSystemInstructions = storedInstructions;
      } else {
        _aiSystemInstructions = defaultGeminiVocabInstructions;
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
      final model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey!,
        systemInstruction: Content.text(_aiSystemInstructions),
      );

      // Runtime prompt only supplies the specific word
      final prompt = 'Word to process: "$inputWord"';

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
          _pronunciationController.text = data['pronunciation'] ?? "";
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
            _searchDisposeExamples();
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

  String? _extractByLabels(
    String source,
    String label,
    List<String> nextLabels,
  ) {
    final escapedLabel = RegExp.escape(label);
    final pattern = nextLabels.isEmpty
        ? RegExp(
            '^\\s*$escapedLabel\\s*:\\s*(.*?)\\s*\\z',
            multiLine: true,
            dotAll: true,
            caseSensitive: false,
          )
        : RegExp(
            '^\\s*$escapedLabel\\s*:\\s*(.*?)(?=^\\s*(?:${nextLabels.map(RegExp.escape).join('|')})\\s*:|\\z)',
            multiLine: true,
            dotAll: true,
            caseSensitive: false,
          );

    final match = pattern.firstMatch(source);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? _normalizeType(String? type) {
    if (type == null) return null;
    final raw = type.trim();
    if (raw.isEmpty) return null;
    return "${raw[0].toUpperCase()}${raw.substring(1).toLowerCase()}";
  }

  String? _trimAtSectionStart(String? value) {
    if (value == null) return null;
    final raw = value.trim();
    if (raw.isEmpty) return null;

    final sectionHeaderMatch = RegExp(
      r'^\s*(?:Form(?:\s*\d+)?|Example\s*\d+|Present Tense|Past Tense|Present Participle|Past Participle|Present Perfect|Past Perfect|Future Perfect)\s*:',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(raw);

    if (sectionHeaderMatch == null) return raw;

    final cleaned = raw.substring(0, sectionHeaderMatch.start).trimRight();
    if (cleaned.isEmpty) return null;
    return cleaned;
  }

  String _canonicalTense(String input) {
    final value = input.trim().toLowerCase();
    switch (value) {
      case 'present tense':
        return 'Present Tense';
      case 'past tense':
        return 'Past Tense';
      case 'present participle':
        return 'Present Participle';
      case 'past participle':
        return 'Past Participle';
      case 'present perfect':
        return 'Present Perfect';
      case 'past perfect':
        return 'Past Perfect';
      case 'future perfect':
        return 'Future Perfect';
      default:
        return input.trim();
    }
  }

  bool _isKnownTense(String line) {
    final normalized = _canonicalTense(line.replaceAll(':', '').trim());
    return _tenseOrder.contains(normalized);
  }

  Map<String, Map<String, String>> _parseTenseDataFromText(String source) {
    final Map<String, Map<String, String>> result = {
      for (final tense in _tenseOrder)
        tense: {'conjugation': '', 'example': ''},
    };

    final lines = source.split(RegExp(r'\r?\n'));
    final tenseHeadingRegex = RegExp(
      r'^(Present Tense|Past Tense|Present Participle|Past Participle|Present Perfect|Past Perfect|Future Perfect)\s*:?(.*)$',
      caseSensitive: false,
    );

    String? currentTense;
    bool appendingExample = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        appendingExample = false;
        continue;
      }

      final headingMatch = tenseHeadingRegex.firstMatch(line);
      if (headingMatch != null) {
        currentTense = _canonicalTense(headingMatch.group(1) ?? '');
        appendingExample = false;

        final trailing = (headingMatch.group(2) ?? '').trim();
        if (trailing.isNotEmpty &&
            !trailing.toLowerCase().startsWith('conjugation:') &&
            !trailing.toLowerCase().startsWith('example:')) {
          result[currentTense]?['conjugation'] = trailing;
        }
        continue;
      }

      final lower = line.toLowerCase();
      if (lower.startsWith('word:') ||
          lower.startsWith('pronunciation:') ||
          lower.startsWith('type of speech:') ||
          lower.startsWith('type:') ||
          lower.startsWith('meaning:') ||
          lower.startsWith('synonyms:') ||
          lower.startsWith('tense / form')) {
        currentTense = null;
        appendingExample = false;
        continue;
      }

      if (currentTense == null) continue;

      if (lower.startsWith('conjugation:')) {
        result[currentTense]?['conjugation'] = line
            .substring('conjugation:'.length)
            .trim();
        appendingExample = false;
        continue;
      }

      if (lower.startsWith('example:')) {
        result[currentTense]?['example'] = line
            .substring('example:'.length)
            .trim();
        appendingExample = true;
        continue;
      }

      if (appendingExample && !_isKnownTense(line)) {
        final currentExample = result[currentTense]?['example'] ?? '';
        result[currentTense]?['example'] = currentExample.isEmpty
            ? line
            : '$currentExample $line';
      }
    }

    return {
      for (final entry in result.entries)
        if (entry.value['conjugation']!.trim().isNotEmpty ||
            entry.value['example']!.trim().isNotEmpty)
          entry.key: {
            'conjugation': entry.value['conjugation']!.trim(),
            'example': entry.value['example']!.trim(),
          },
    };
  }

  List<Map<String, String>> _parseRelatedFormsFromText(String source) {
    final lines = source.split(RegExp(r'\r?\n'));
    final formHeadingRegex = RegExp(
      r'^Form(?:\s*\d+)?\s*:\s*(.*)$',
      caseSensitive: false,
    );

    final List<Map<String, String>> result = [];
    Map<String, String>? current;
    bool appendingExample = false;

    void pushCurrent() {
      if (current == null) return;
      final form = (current!['form'] ?? '').trim();
      final type = (current!['type'] ?? '').trim();
      final meaning = (current!['meaning'] ?? '').trim();
      final example = (current!['example'] ?? '').trim();
      if (form.isEmpty && type.isEmpty && meaning.isEmpty && example.isEmpty) {
        current = null;
        return;
      }
      result.add({
        'form': form,
        'type': type,
        'meaning': meaning,
        'example': example,
      });
      current = null;
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        appendingExample = false;
        continue;
      }

      final headingMatch = formHeadingRegex.firstMatch(line);
      if (headingMatch != null) {
        pushCurrent();
        current = {
          'form': (headingMatch.group(1) ?? '').trim(),
          'type': '',
          'meaning': '',
          'example': '',
        };
        appendingExample = false;
        continue;
      }

      if (current == null) continue;

      final lower = line.toLowerCase();
      if (_isKnownTense(line) || lower.startsWith('present tense:')) {
        pushCurrent();
        appendingExample = false;
        continue;
      }

      if (lower.startsWith('type of speech:')) {
        current!['type'] = line.substring('type of speech:'.length).trim();
        appendingExample = false;
        continue;
      }

      if (lower.startsWith('type:')) {
        current!['type'] = line.substring('type:'.length).trim();
        appendingExample = false;
        continue;
      }

      if (lower.startsWith('meaning:')) {
        current!['meaning'] = line.substring('meaning:'.length).trim();
        appendingExample = false;
        continue;
      }

      if (lower.startsWith('example:')) {
        current!['example'] = line.substring('example:'.length).trim();
        appendingExample = true;
        continue;
      }

      if (appendingExample) {
        final currentExample = (current!['example'] ?? '').trim();
        current!['example'] = currentExample.isEmpty
            ? line
            : '$currentExample $line';
      }
    }

    pushCurrent();
    return result;
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
      bool pastedTenseWhileHidden = false;
      bool pastedRelatedFormsWhileHidden = false;

      final word = _extractByLabels(text, 'Word', [
        'Pronunciation',
        'Type of Speech',
        'Type',
        'Meaning',
        'Synonyms',
      ]);
      final pronunciation = _extractByLabels(text, 'Pronunciation', [
        'Type of Speech',
        'Type',
        'Meaning',
        'Synonyms',
        'Present Tense',
      ]);
      final type =
          _extractByLabels(text, 'Type of Speech', ['Meaning', 'Synonyms']) ??
          _extractByLabels(text, 'Type', ['Meaning', 'Synonyms']);
      final meaning = _trimAtSectionStart(
        _extractByLabels(text, 'Meaning', [
          'Synonyms',
          'Example 1',
          'Present Tense',
        ]),
      );
      final synonyms = _trimAtSectionStart(
        _extractByLabels(text, 'Synonyms', ['Example 1', 'Present Tense']),
      );

      final numberedExamples =
          RegExp(
                r'^\s*Example\s*\d+\s*:\s*(.+)$',
                multiLine: true,
                caseSensitive: false,
              )
              .allMatches(text)
              .map((m) => (m.group(1) ?? '').trim())
              .where((e) => e.isNotEmpty)
              .toList();

      final tenseData = _parseTenseDataFromText(text);
      final relatedForms = _parseRelatedFormsFromText(text);

      if (word == null &&
          pronunciation == null &&
          type == null &&
          tenseData.isEmpty &&
          relatedForms.isEmpty &&
          numberedExamples.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard format not recognized.')),
        );
        return;
      }

      final normalizedType = _normalizeType(type);

      setState(() {
        if (word != null) {
          _wordController.text = word;
        }
        if (pronunciation != null) {
          _pronunciationController.text = pronunciation;
        }
        if (meaning != null) {
          _descController.text = meaning;
        }
        if (synonyms != null) {
          _synonymsController.text = synonyms;
        }

        if (normalizedType != null) {
          if (!_types.contains(normalizedType)) {
            _types.add(normalizedType);
          }
          _wordType = normalizedType;
        }

        if (numberedExamples.isNotEmpty) {
          _searchDisposeExamples();
          _exampleControllers = numberedExamples
              .map((e) => TextEditingController(text: e))
              .toList();
        }

        if (tenseData.isNotEmpty) {
          pastedTenseWhileHidden = !_showTenseConjugationForm;
          for (final tense in _tenseOrder) {
            final parsed = tenseData[tense];
            if (parsed == null) continue;
            final conjugation = (parsed['conjugation'] ?? '').trim();
            final example = (parsed['example'] ?? '').trim();

            if (conjugation.isNotEmpty) {
              _tenseConjugationControllers[tense]?.text = conjugation;
            }
            if (example.isNotEmpty) {
              _tenseExampleControllers[tense]?.text = example;
            }
          }
        }

        if (relatedForms.isNotEmpty) {
          pastedRelatedFormsWhileHidden = !_showRelatedForms;
          _disposeRelatedForms();
          _relatedFormControllers = relatedForms
              .map(
                (item) => _RelatedFormFields(
                  form: item['form'] ?? '',
                  type: item['type'] ?? '',
                  meaning: item['meaning'] ?? '',
                  example: item['example'] ?? '',
                ),
              )
              .toList();
        }
      });

      final String pasteMessage;
      if (tenseData.isNotEmpty || relatedForms.isNotEmpty) {
        final List<String> detected = [];
        if (tenseData.isNotEmpty) {
          detected.add('${tenseData.length} tense form(s)');
        }
        if (relatedForms.isNotEmpty) {
          detected.add('${relatedForms.length} related form(s)');
        }
        pasteMessage = 'Text pasted. Detected ${detected.join(' and ')}.';
      } else {
        pasteMessage = 'Text pasted into fields successfully.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pasteMessage),
          action: (pastedTenseWhileHidden || pastedRelatedFormsWhileHidden)
              ? SnackBarAction(
                  label: 'SHOW',
                  onPressed: () {
                    if (!mounted) return;
                    setState(() {
                      if (tenseData.isNotEmpty) {
                        _showTenseConjugationForm = true;
                      }
                      if (relatedForms.isNotEmpty) {
                        _showRelatedForms = true;
                      }
                    });
                  },
                )
              : null,
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to parse clipboard text.')),
      );
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

  String _buildTenseDataForSave() {
    final Map<String, Map<String, String>> payload = {};
    for (final tense in _tenseOrder) {
      final conjugation =
          _tenseConjugationControllers[tense]?.text.trim() ?? '';
      final example = _tenseExampleControllers[tense]?.text.trim() ?? '';
      if (conjugation.isEmpty && example.isEmpty) continue;
      payload[tense] = {'conjugation': conjugation, 'example': example};
    }

    if (payload.isEmpty) return '';
    return jsonEncode(payload);
  }

  String _buildRelatedFormsForSave() {
    final List<Map<String, String>> payload = _relatedFormControllers
        .map(
          (item) => {
            'form': item.formController.text.trim(),
            'type': item.typeController.text.trim(),
            'meaning': item.meaningController.text.trim(),
            'example': item.exampleController.text.trim(),
          },
        )
        .where(
          (item) =>
              item['form']!.isNotEmpty ||
              item['type']!.isNotEmpty ||
              item['meaning']!.isNotEmpty ||
              item['example']!.isNotEmpty,
        )
        .toList();

    if (payload.isEmpty) return '';
    return jsonEncode(payload);
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
      final tenseData = _buildTenseDataForSave();
      final relatedForms = _buildRelatedFormsForSave();
      final data = {
        'word': _wordController.text,
        'pronunciation': _pronunciationController.text.trim(),
        'description': _descController.text,
        'synonyms': _synonymsController.text.trim(),
        'examples': allExamples,
        'tense_data': tenseData,
        'related_forms': relatedForms,
        'word_type': _wordType,
        'image_path': _imagePath,
      };
      int wordId;
      if (widget.vocabItem == null) {
        wordId = await dbHelper.insert(data);
      } else {
        wordId = widget.vocabItem!['id'] as int;
        await dbHelper.update({'id': wordId, ...data});
      }

      // If a group is chosen, add this word to that group.
      if (_selectedGroupId != null) {
        await dbHelper.addWordToGroup(_selectedGroupId!, wordId);
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
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 55,
              width: double.infinity,
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
            const SizedBox(height: 20),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
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
                  "Word Group",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                // Create / manage word groups button (same style as Gallery)
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WordGroupsPage(),
                      ),
                    );
                    await _loadWordGroups();
                  },
                  icon: const Icon(Icons.group_add),
                  label: const Text('Create or manage word groups'),
                ),
                const SizedBox(height: 10),
                // Word group dropdown (same style as Word Type)
                if (_wordGroups.isNotEmpty) ...[
                  DropdownMenu<int?>(
                    width: MediaQuery.of(context).size.width - 32,
                    menuHeight: 250,
                    initialSelection: _selectedGroupId,
                    label: const Text('Word Group (optional)'),
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
                      ..._wordGroups.map(
                        (g) => DropdownMenuEntry<int?>(
                          value: g['id'] as int?,
                          label: (g['name'] ?? '').toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _defaultGroupId == null
                              ? 'Default group: None'
                              : 'Default group: ${_wordGroups.firstWhere((g) => g['id'] == _defaultGroupId, orElse: () => <String, dynamic>{'name': 'None'})['name']}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _selectedGroupId == null
                            ? null
                            : _setSelectedAsDefaultGroup,
                        icon: const Icon(Icons.push_pin_outlined, size: 16),
                        label: const Text('Set Default'),
                      ),
                      TextButton(
                        onPressed: _defaultGroupId == null
                            ? null
                            : _clearDefaultGroup,
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                const Text(
                  "Word Details",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),

                // WORD + PASTE + AI BUTTONS
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
                        onPressed: _pasteFromClipboard,
                        child: Image.asset(
                          'assets/images/paste-button-1.png',
                          fit: BoxFit.contain,
                        ),
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
                  label: const Text("Type of Speech"),
                  onSelected: (value) async {
                    if (value == _addNewTypeLabel) {
                      final newType = await _showAddWordTypeDialog();
                      if (newType != null && newType.trim().isNotEmpty) {
                        setState(() {
                          if (!_types.contains(newType.trim())) {
                            _types.add(newType.trim());
                          }
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
                  controller: _pronunciationController,
                  decoration: _inputStyle("Pronunciation"),
                ),
                const SizedBox(height: 15),

                TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: _inputStyle("Definition"),
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
                            if (_exampleControllers.length > 1) {
                              setState(() {
                                final removed = _exampleControllers.removeAt(
                                  idx,
                                );
                                removed.dispose();
                              });
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

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Related Forms",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showRelatedForms = !_showRelatedForms;
                        });
                      },
                      icon: Icon(
                        _showRelatedForms
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                      ),
                      label: Text(_showRelatedForms ? 'Hide' : 'Show'),
                    ),
                  ],
                ),
                if (_showRelatedForms) ...[
                  const SizedBox(height: 8),
                  ..._relatedFormControllers.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Form ${idx + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  if (_relatedFormControllers.length > 1) {
                                    setState(() {
                                      final removed = _relatedFormControllers
                                          .removeAt(idx);
                                      removed.dispose();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          TextFormField(
                            controller: item.formController,
                            decoration: _inputStyle('Word'),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: item.typeController,
                            decoration: _inputStyle('Type of Speech'),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: item.meaningController,
                            decoration: _inputStyle('Definition'),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: item.exampleController,
                            decoration: _inputStyle('Example'),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _relatedFormControllers.add(_RelatedFormFields()),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text("Add Related Form"),
                  ),
                ],
                const SizedBox(height: 20),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Tense / Form Conjugation",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showTenseConjugationForm =
                              !_showTenseConjugationForm;
                        });
                      },
                      icon: Icon(
                        _showTenseConjugationForm
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                      ),
                      label: Text(_showTenseConjugationForm ? 'Hide' : 'Show'),
                    ),
                  ],
                ),
                if (_showTenseConjugationForm) ...[
                  const SizedBox(height: 10),
                  ..._tenseOrder.map((tense) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tense,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.indigo,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _tenseConjugationControllers[tense],
                            decoration: _inputStyle('$tense Conjugation'),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _tenseExampleControllers[tense],
                            maxLines: 2,
                            decoration: _inputStyle('$tense Example'),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
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
