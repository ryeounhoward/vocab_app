import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import 'search_page_idiom.dart';

class IdiomReviewPage extends StatefulWidget {
  final int? selectedId;

  const IdiomReviewPage({super.key, this.selectedId});

  @override
  State<IdiomReviewPage> createState() => _IdiomReviewPageState();
}

class _IdiomReviewPageState extends State<IdiomReviewPage> {
  final dbHelper = DBHelper();
  final FlutterTts flutterTts = FlutterTts();
  List<Map<String, dynamic>> _idiomList = [];
  bool _isLoading = true;
  PageController? _pageController;

  // FIX 1: Add a variable to store the preferred voice
  Map<String, String>? _currentVoice;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initTts();
  }

  // --- TTS INITIALIZATION ---
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

  // --- LOAD DATA & SHUFFLE ---
  void _loadData() async {
    setState(() => _isLoading = true);

    final data = await dbHelper.queryAll(DBHelper.tableIdioms);
    List<Map<String, dynamic>> shuffledData = List.from(data);
    shuffledData.shuffle();

    int targetIndex = 0;

    if (widget.selectedId != null) {
      targetIndex = shuffledData.indexWhere(
        (item) => item['id'] == widget.selectedId,
      );
      if (targetIndex == -1) targetIndex = 0;
    }

    setState(() {
      _idiomList = shuffledData;
      _isLoading = false;
      if (_idiomList.isNotEmpty) {
        int initialPage = (_idiomList.length * 100) + targetIndex;
        _pageController = PageController(
          viewportFraction: 0.93,
          initialPage: initialPage,
        );
      }
    });
  }

  // --- DIRECT SPEECH LOGIC ---
  Future<void> _speak(String idiom, String desc, List<String> examples) async {
    await flutterTts.stop();

    // 1. Start directly with the idiom
    String speechText = "$idiom. ";

    // 2. Meaning starts with "It means"
    if (desc.isNotEmpty) {
      speechText += "It means $desc. ";
    }

    // 3. Examples phrasing
    if (examples.isNotEmpty) {
      speechText += examples.length == 1
          ? "The example is: ${examples.first}"
          : "The examples are: ${examples.join(". ")}";
    }

    // FIX 3: Force set the voice again right before speaking
    // This ensures the voice is correct even if the app was in background
    if (_currentVoice != null) {
      await flutterTts.setVoice(_currentVoice!);
    }

    await flutterTts.speak(speechText);
  }

  // --- FAVORITE TOGGLE ---
  void _toggleFav(int indexInList, Map<String, dynamic> item) async {
    int newStatus = (item['is_favorite'] == 1) ? 0 : 1;
    await dbHelper.toggleFavorite(
      item['id'],
      newStatus == 1,
      DBHelper.tableIdioms,
    );
    setState(() {
      Map<String, dynamic> updatedItem = Map.from(item);
      updatedItem['is_favorite'] = newStatus;
      _idiomList[indexInList] = updatedItem;
    });

    if (newStatus == 1) {
      _playFavoriteSound();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text("Idioms"),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_idiomList.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text("Idioms"),
          centerTitle: true,
        ),
        body: const Center(
          child: Text("No idioms found. Please add some first."),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text("Idioms"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SearchPageIdiom()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: PageView.builder(
          itemCount: 1000000,
          controller: _pageController,
          onPageChanged: (index) {
            flutterTts.stop();
          },
          itemBuilder: (context, index) {
            final actualIndex = index % _idiomList.length;
            final item = _idiomList[actualIndex];
            return _buildIdiomCard(item, actualIndex);
          },
        ),
      ),
    );
  }

  // --- IDIOM CARD DESIGN ---
  Widget _buildIdiomCard(Map<String, dynamic> item, int indexInList) {
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
              // Image Section
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

              // Content Section
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['idiom'] ?? '',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
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
                            item['idiom'] ?? "",
                            item['description'] ?? "",
                            examplesList,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 30),

                    // Meaning
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

                    const SizedBox(height: 25),

                    // Examples
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
