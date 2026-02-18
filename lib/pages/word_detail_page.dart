import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';

class WordDetailPage extends StatefulWidget {
  final Map<String, dynamic> item;
  const WordDetailPage({super.key, required this.item});

  @override
  State<WordDetailPage> createState() => _WordDetailPageState();
}

class _WordDetailPageState extends State<WordDetailPage> {
  final dbHelper = DBHelper();
  final FlutterTts flutterTts = FlutterTts();
  late Map<String, dynamic> currentItem;
  final List<String> _tenseOrder = const [
    'Present Tense',
    'Past Tense',
    'Present Participle',
    'Past Participle',
    'Present Perfect',
    'Past Perfect',
    'Future Perfect',
  ];
  static const Color _tenseAccentColor = Colors.indigo;
  bool _isTenseExpanded = false;

  // FIX 1: Add a variable to store the preferred voice
  Map<String, String>? _currentVoice;

  @override
  void initState() {
    super.initState();
    currentItem = widget.item;
    _loadTenseDefaultPreference();
    _initTts();
  }

  Future<void> _loadTenseDefaultPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final bool showByDefault = prefs.getBool('show_tenses_by_default') ?? false;
    if (!mounted) return;
    setState(() {
      _isTenseExpanded = showByDefault;
    });
  }

  void _initTts() async {
    final prefs = await SharedPreferences.getInstance();
    String? voiceName = prefs.getString('selected_voice_name');
    String? voiceLocale = prefs.getString('selected_voice_locale');

    // FIX 2: Store the voice in the variable and set it initially
    if (voiceName != null && voiceLocale != null) {
      _currentVoice = {"name": voiceName, "locale": voiceLocale};
      await flutterTts.setVoice(_currentVoice!);
    } else {
      await flutterTts.setLanguage("en-US");
    }
    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _playFavoriteSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('favorite_sound_enabled') ?? true;
      if (!enabled) return;

      final player = AudioPlayer();
      await player.play(AssetSource('sounds/star.mp3'));
      player.onPlayerComplete.listen((event) {
        player.dispose();
      });
    } catch (e) {
      debugPrint('Error playing favorite sound: $e');
    }
  }

  Future<void> _speak(
    String word,
    String type,
    String desc,
    List<String> examples,
    String synonyms,
  ) async {
    String article = "a";
    if (type.isNotEmpty) {
      String firstLetter = type.trim().substring(0, 1).toLowerCase();
      if ("aeiou".contains(firstLetter)) article = "an";
    }

    String wordType = type.isNotEmpty ? type : "word";
    String meaningPart = desc.isNotEmpty
        ? "$word is $article $wordType that means $desc."
        : "$word is $article $wordType.";

    String exampleText = "";
    if (examples.isNotEmpty) {
      exampleText = examples.length == 1
          ? " The example is: ${examples.first}"
          : " The examples are: ${examples.join(". ")}";
    }

    String synonymsPart = "";
    if (synonyms.trim().isNotEmpty) {
      synonymsPart = " Its synonyms are: $synonyms.";
    }

    // FIX 3: Force set the voice again right before speaking
    if (_currentVoice != null) {
      await flutterTts.setVoice(_currentVoice!);
    }

    await flutterTts.speak("$meaningPart$synonymsPart$exampleText");
  }

  void _toggleFav() async {
    int newStatus = (currentItem['is_favorite'] == 1) ? 0 : 1;

    await dbHelper.toggleFavorite(
      currentItem['id'],
      newStatus == 1,
      DBHelper.tableVocab,
    );

    setState(() {
      currentItem = {...currentItem, 'is_favorite': newStatus};
    });

    if (newStatus == 1) {
      _playFavoriteSound();
    }
  }

  Map<String, Map<String, String>> _parseTenseData() {
    final raw = (currentItem['tense_data'] as String? ?? '').trim();
    if (raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};

      final Map<String, Map<String, String>> result = {};
      for (final tense in _tenseOrder) {
        final value = decoded[tense];
        if (value is! Map<String, dynamic>) continue;

        final conjugation = (value['conjugation'] ?? '').toString().trim();
        final example = (value['example'] ?? '').toString().trim();
        if (conjugation.isEmpty && example.isEmpty) continue;

        result[tense] = {'conjugation': conjugation, 'example': example};
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isFav = currentItem['is_favorite'] == 1;
    List<String> examplesList = (currentItem['examples'] as String? ?? "")
        .split('\n')
        .where((String e) => e.trim().isNotEmpty)
        .toList();
    final pronunciation = (currentItem['pronunciation'] as String? ?? '')
        .trim();
    String synonyms = (currentItem['synonyms'] as String? ?? '').trim();
    final tenseData = _parseTenseData();

    return Scaffold(
      appBar: AppBar(
        title: Text(currentItem['word'] ?? "Detail"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // --- THE CARD ---
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child:
                              currentItem['image_path'] != null &&
                                  currentItem['image_path'] != ""
                              ? Image.file(
                                  File(currentItem['image_path']),
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: Colors.grey[200],
                                  child: const Icon(
                                    Icons.image,
                                    size: 80,
                                    color: Colors.grey,
                                  ),
                                ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                isFav ? Icons.star : Icons.star_border,
                                color: isFav ? Colors.yellow : Colors.white,
                                size: 30,
                              ),
                              onPressed: _toggleFav,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Word and Type
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text:
                                                "${currentItem['word'] ?? ''} ",
                                            style: const TextStyle(
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          TextSpan(
                                            text:
                                                "(${currentItem['word_type'] ?? ''})",
                                            style: const TextStyle(
                                              fontSize: 18,
                                              color: Colors.blueGrey,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Pronunciation (Fixed Syntax)
                                    if (pronunciation.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        pronunciation,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.volume_up,
                                  color: Colors.indigo,
                                  size: 30,
                                ),
                                onPressed: () => _speak(
                                  currentItem['word'] ?? "",
                                  currentItem['word_type'] ?? "",
                                  currentItem['description'] ?? "",
                                  examplesList,
                                  synonyms,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 30),
                          const Text(
                            "Meaning",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentItem['description'] ??
                                "No description provided.",
                            style: const TextStyle(fontSize: 18, height: 1.4),
                          ),
                          const SizedBox(height: 20),

                          if (synonyms.isNotEmpty) ...[
                            const Text(
                              "Synonyms",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              synonyms,
                              style: const TextStyle(fontSize: 16, height: 1.3),
                            ),
                            const SizedBox(height: 20),
                          ],

                          if (examplesList.isNotEmpty) ...[
                            const Text(
                              "Examples",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...examplesList.asMap().entries.map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 10.0),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    8,
                                    10,
                                    8,
                                  ),
                                  decoration: BoxDecoration(
                                    border: const Border(
                                      left: BorderSide(
                                        color: Colors.green,
                                        width: 4,
                                      ),
                                    ),
                                    color: Colors.green.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    entry.value,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          if (tenseData.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Tense / Form Conjugation",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _isTenseExpanded = !_isTenseExpanded;
                                    });
                                  },
                                  icon: Icon(
                                    _isTenseExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    size: 20,
                                  ),
                                  label: Text(
                                    _isTenseExpanded ? 'Hide' : 'Show',
                                  ),
                                ),
                              ],
                            ),
                            if (_isTenseExpanded) ...[
                              const SizedBox(height: 10),
                              ..._tenseOrder
                                  .where((t) => tenseData.containsKey(t))
                                  .map(
                                    (tense) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$tense:',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          if ((tenseData[tense]?['conjugation'] ??
                                                  '')
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _tenseAccentColor,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                tenseData[tense]?['conjugation'] ??
                                                    '',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if ((tenseData[tense]?['example'] ??
                                                  '')
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    10,
                                                    8,
                                                    10,
                                                    8,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: const Border(
                                                  left: BorderSide(
                                                    color: _tenseAccentColor,
                                                    width: 4,
                                                  ),
                                                ),
                                                color: _tenseAccentColor
                                                    .withOpacity(0.06),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                tenseData[tense]?['example'] ??
                                                    '',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontStyle: FontStyle.italic,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}
