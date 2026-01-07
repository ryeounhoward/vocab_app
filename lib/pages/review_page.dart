import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../database/db_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final dbHelper = DBHelper();
  final FlutterTts flutterTts = FlutterTts();
  List<Map<String, dynamic>> _vocabList = [];
  bool _isLoading = true;
  
  // Controller for infinite loop
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initTts();
  }

  void _initTts() async {
    final prefs = await SharedPreferences.getInstance();
    String? voiceName = prefs.getString('selected_voice_name');
    String? voiceLocale = prefs.getString('selected_voice_locale');

    if (voiceName != null && voiceLocale != null) {
      await flutterTts.setVoice({"name": voiceName, "locale": voiceLocale});
    } else {
      await flutterTts.setLanguage("en-US");
    }
    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    flutterTts.stop();
    _pageController?.dispose(); // Dispose controller
    super.dispose();
  }

  void _loadData() async {
    final data = await dbHelper.queryAll();
    // Create a mutable copy and shuffle it
    List<Map<String, dynamic>> shuffledData = List.from(data);
    shuffledData.shuffle();

    setState(() {
      _vocabList = shuffledData;
      _isLoading = false;
      
      // Initialize controller at a "middle" index to allow swiping left immediately
      // We pick a large multiple of the list length
      if (_vocabList.isNotEmpty) {
        int initialPage = _vocabList.length * 100; 
        _pageController = PageController(
          viewportFraction: 0.93,
          initialPage: initialPage,
        );
      }
    });
  }

  Future<void> _speak(String word, String type, String desc, List<String> examples) async {
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

    await flutterTts.speak("$meaningPart$exampleText");
  }

  // Update favorite state locally to avoid re-shuffling the whole list on every click
  void _toggleFav(int indexInList, Map<String, dynamic> item) async {
    int newStatus = (item['is_favorite'] == 1) ? 0 : 1;
    await dbHelper.toggleFavorite(item['id'], newStatus == 1);
    
    setState(() {
      // Update the specific item in the local list
      Map<String, dynamic> updatedItem = Map.from(item);
      updatedItem['is_favorite'] = newStatus;
      _vocabList[indexInList] = updatedItem;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_vocabList.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("No vocabulary found. Please add some first.")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Review"), centerTitle: true),
      body: SafeArea(
        child: PageView.builder(
          // Using a very large number creates an "infinite" loop feel
          itemCount: 1000000, 
          controller: _pageController,
          onPageChanged: (index) {
            flutterTts.stop();
          },
          itemBuilder: (context, index) {
            // Use modulo to loop through the shuffled list
            final actualIndex = index % _vocabList.length;
            final item = _vocabList[actualIndex];
            return _buildVocabCard(item, actualIndex);
          },
        ),
      ),
    );
  }

  // Updated build card to accept the index for favorite updates
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
                    child: item['image_path'] != null && item['image_path'] != ""
                        ? Image.file(File(item['image_path']), fit: BoxFit.cover)
                        : Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.image, size: 80, color: Colors.grey),
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
                                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text: "(${item['word_type'] ?? ''})",
                                  style: const TextStyle(fontSize: 18, color: Colors.blueGrey, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.volume_up, color: Colors.indigo, size: 30),
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
                    const Text("Meaning", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                    const SizedBox(height: 8),
                    Text(item['description'] ?? "No description provided.", style: const TextStyle(fontSize: 18, height: 1.4)),
                    const SizedBox(height: 25),
                    if (examplesList.isNotEmpty) ...[
                      const Text("Examples", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                      const SizedBox(height: 10),
                      ...examplesList.map((example) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("• ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Expanded(child: Text(example, style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.black87))),
                          ],
                        ),
                      )),
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