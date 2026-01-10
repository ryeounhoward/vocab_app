import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../database/db_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'search_page.dart';

class ReviewPage extends StatefulWidget {
  final int? selectedId;
  final String? originTable;

  const ReviewPage({super.key, this.selectedId, this.originTable});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final dbHelper = DBHelper();
  final FlutterTts flutterTts = FlutterTts();
  List<Map<String, dynamic>> _vocabList = [];
  bool _isLoading = true;
  PageController? _pageController;

  // FIX 1: Add a variable to store the preferred voice in memory
  Map<String, String>? _currentVoice;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadAndShuffle();
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

  void _loadAndShuffle() async {
    // ONLY vocabulary words
    final data = await dbHelper.queryAll(DBHelper.tableVocab);

    // Read preferred order from settings
    final prefs = await SharedPreferences.getInstance();
    final order = prefs.getString('practice_order') ?? 'shuffle';

    // Start from a mutable copy
    List<Map<String, dynamic>> orderedData = List.from(data);

    if (order == 'az') {
      orderedData.sort((a, b) {
        final String aWord = (a['word'] ?? '').toString().toLowerCase();
        final String bWord = (b['word'] ?? '').toString().toLowerCase();
        return aWord.compareTo(bWord);
      });
    } else if (order == 'za') {
      orderedData.sort((a, b) {
        final String aWord = (a['word'] ?? '').toString().toLowerCase();
        final String bWord = (b['word'] ?? '').toString().toLowerCase();
        return bWord.compareTo(aWord);
      });
    } else {
      // Default: shuffle randomly
      orderedData.shuffle();
    }

    int targetIndex = 0;
    if (widget.selectedId != null) {
      targetIndex = orderedData.indexWhere(
        (item) => item['id'] == widget.selectedId,
      );
      if (targetIndex == -1) targetIndex = 0;
    }

    setState(() {
      _vocabList = orderedData;
      _isLoading = false;
      if (_vocabList.isNotEmpty) {
        int initialPage = (_vocabList.length * 100) + targetIndex;
        _pageController = PageController(
          viewportFraction: 0.93,
          initialPage: initialPage,
        );
      }
    });
  }

  @override
  void dispose() {
    flutterTts.stop();
    _pageController?.dispose();
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
    // This prevents the OS from resetting to the default voice after inactivity
    if (_currentVoice != null) {
      await flutterTts.setVoice(_currentVoice!);
    }

    await flutterTts.speak("$meaningPart$exampleText");
  }

  void _toggleFav(int indexInList, Map<String, dynamic> item) async {
    int newStatus = (item['is_favorite'] == 1) ? 0 : 1;
    await dbHelper.toggleFavorite(
      item['id'],
      newStatus == 1,
      DBHelper.tableVocab,
    );
    setState(() {
      Map<String, dynamic> updatedItem = Map.from(item);
      updatedItem['is_favorite'] = newStatus;
      _vocabList[indexInList] = updatedItem;
    });

    // Play sound only when marking as favorite
    if (newStatus == 1) {
      _playFavoriteSound();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Words"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SearchPage()),
            ),
          ),
        ],
      ),
      body: _vocabList.isEmpty
          ? const Center(child: Text("No vocabulary found."))
          : SafeArea(
              child: PageView.builder(
                itemCount: 1000000,
                controller: _pageController,
                onPageChanged: (index) => flutterTts.stop(),
                itemBuilder: (context, index) {
                  final actualIndex = index % _vocabList.length;
                  final item = _vocabList[actualIndex];
                  return _buildVocabCard(item, actualIndex);
                },
              ),
            ),
    );
  }

  Widget _buildVocabCard(Map<String, dynamic> item, int indexInList) {
    bool isFav = item['is_favorite'] == 1;
    List<String> examplesList = (item['examples'] as String? ?? "")
        .split('\n')
        .where((String e) => e.trim().isNotEmpty)
        .toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child:
                        item['image_path'] != null && item['image_path'] != ""
                        ? Image.file(
                            File(item['image_path']),
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
                        onPressed: () => _toggleFav(indexInList, item),
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
                                  text: "${item['word'] ?? ''} ",
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: "(${item['word_type'] ?? ''})",
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
                            item['word'] ?? "",
                            item['word_type'] ?? "",
                            item['description'] ?? "",
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
                      item['description'] ?? "No description provided.",
                      style: const TextStyle(fontSize: 18, height: 1.4),
                    ),
                    const SizedBox(height: 25), // Spacing restored
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
                    const SizedBox(height: 20), // Bottom spacing restored
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
