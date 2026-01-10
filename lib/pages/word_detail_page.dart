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

  // FIX 1: Add a variable to store the preferred voice
  Map<String, String>? _currentVoice;

  @override
  void initState() {
    super.initState();
    currentItem = widget.item;
    _initTts();
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

    // FIX 3: Force set the voice again right before speaking
    // This ensures the voice is correct even if the app was in background
    if (_currentVoice != null) {
      await flutterTts.setVoice(_currentVoice!);
    }

    await flutterTts.speak("$meaningPart$exampleText");
  }

  void _toggleFav() async {
    int newStatus = (currentItem['is_favorite'] == 1) ? 0 : 1;

    // Updated to include table name for consistency with your other pages
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

  @override
  Widget build(BuildContext context) {
    bool isFav = currentItem['is_favorite'] == 1;
    List<String> examplesList = (currentItem['examples'] as String? ?? "")
        .split('\n')
        .where((String e) => e.trim().isNotEmpty)
        .toList();

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
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: "${currentItem['word'] ?? ''} ",
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
                          const SizedBox(height: 25),
                          if (examplesList.isNotEmpty) ...[
                            const Text(
                              "Examples",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...examplesList.map(
                              (example) => Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "• ",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        example,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
