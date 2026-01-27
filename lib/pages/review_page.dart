import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vocab_app/services/refresh_signal.dart';
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

  Map<String, String>? _currentVoice;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadAndShuffle();
    // Start listening for the refresh signal
    DataRefreshSignal.refreshNotifier.addListener(_onGlobalRefresh);
  }

  // FIX: This was missing! This method runs when the Sort page saves data.
  void _onGlobalRefresh() {
    if (mounted) {
      _loadAndShuffle();
    }
  }

  @override
  void dispose() {
    // Stop listening to prevent memory leaks
    DataRefreshSignal.refreshNotifier.removeListener(_onGlobalRefresh);
    flutterTts.stop();
    _pageController?.dispose();
    super.dispose();
  }

  void _initTts() async {
    final prefs = await SharedPreferences.getInstance();
    String? voiceName = prefs.getString('selected_voice_name');
    String? voiceLocale = prefs.getString('selected_voice_locale');

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
    final data = await dbHelper.queryAll(DBHelper.tableVocab);

    final prefs = await SharedPreferences.getInstance();
    // IMPORTANT: Force the app to see the latest changes on the disk
    await prefs.reload();

    final bool useAllWords = prefs.getBool('quiz_use_all_words') ?? true;
    final List<String> storedIds =
        prefs.getStringList('quiz_selected_word_ids') ?? <String>[];
    final Set<int> selectedIds = storedIds
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .toSet();
    final int? groupId = prefs.getInt('quiz_selected_word_group_id');

    List<Map<String, dynamic>> filteredData;
    if (groupId != null) {
      final Set<int> groupIds = await dbHelper.getWordIdsForGroup(groupId);
      filteredData = data
          .where((item) => groupIds.contains(item['id'] as int? ?? -1))
          .toList();
    } else if (useAllWords) {
      filteredData = List<Map<String, dynamic>>.from(data);
    } else if (selectedIds.isNotEmpty) {
      filteredData = data
          .where((item) => selectedIds.contains(item['id'] as int? ?? -1))
          .toList();
    } else {
      filteredData = <Map<String, dynamic>>[];
    }

    final order = prefs.getString('practice_order') ?? 'shuffle';
    List<Map<String, dynamic>> orderedData = List.from(filteredData);

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
      orderedData.shuffle();
    }

    int targetIndex = 0;
    if (widget.selectedId != null) {
      targetIndex = orderedData.indexWhere(
        (item) => item['id'] == widget.selectedId,
      );

      if (targetIndex == -1) {
        final fallback = data.firstWhere(
          (item) => item['id'] == widget.selectedId,
          orElse: () => <String, dynamic>{},
        );
        if (fallback.isNotEmpty) {
          orderedData.insert(0, Map<String, dynamic>.from(fallback));
          targetIndex = 0;
        } else {
          targetIndex = 0;
        }
      }
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

  Future<void> _playFavoriteSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('favorite_sound_enabled') ?? true;
      if (!enabled) return;

      final player = AudioPlayer();
      await player.play(AssetSource('sounds/star2.mp3'));
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
    if (_currentVoice != null) {
      await flutterTts.setVoice(_currentVoice!);
    }

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

    String synonymsPart = synonyms.trim().isNotEmpty
        ? " Its synonyms are: $synonyms."
        : "";

    await flutterTts.speak("$meaningPart$synonymsPart$exampleText");
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
    if (newStatus == 1) _playFavoriteSound();
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
          ? const Center(
              child: Text("No vocabulary found for current selection."),
            )
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
    String synonyms = (item['synonyms'] as String? ?? '').trim();
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
                      item['description'] ?? "No description provided.",
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
                      Text(synonyms, style: const TextStyle(fontSize: 16)),
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
                      ...examplesList.map(
                        (example) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            "• $example",
                            style: const TextStyle(
                              fontSize: 16,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
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
