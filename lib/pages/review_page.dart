import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart'; // 1. Import TTS
import '../database/db_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final dbHelper = DBHelper();
  final FlutterTts flutterTts = FlutterTts(); // 2. Initialize TTS
  List<Map<String, dynamic>> _vocabList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initTts();
  }

  // 3. Optional: Configure TTS settings
  void _initTts() async {
    final prefs = await SharedPreferences.getInstance();
    String? voiceName = prefs.getString('selected_voice_name');
    String? voiceLocale = prefs.getString('selected_voice_locale');

    if (voiceName != null && voiceLocale != null) {
      // Apply the saved voice
      await flutterTts.setVoice({"name": voiceName, "locale": voiceLocale});
    } else {
      // Default fallback
      await flutterTts.setLanguage("en-US");
    }

    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    flutterTts.stop(); // Stop speaking if user leaves the page
    super.dispose();
  }

  void _loadData() async {
    final data = await dbHelper.queryAll();
    setState(() {
      _vocabList = data;
      _isLoading = false;
    });
  }

  Future<void> _speak(
    String word,
    String type,
    String desc,
    List<String> examples,
  ) async {
    // 1. Determine "a" or "an" based on the first letter of the type
    String article = "a";
    if (type.isNotEmpty) {
      String firstLetter = type.trim().substring(0, 1).toLowerCase();
      if ("aeiou".contains(firstLetter)) {
        article = "an";
      }
    }

    // 2. Build the main definition sentence
    // Example: "Adamant is an adjective that means..."
    String wordType = type.isNotEmpty ? type : "word";
    String meaningPart = desc.isNotEmpty
        ? "$word is $article $wordType that means $desc."
        : "$word is $article $wordType.";

    // 3. Handle Example vs Examples (Singular vs Plural)
    String exampleText = "";
    if (examples.isNotEmpty) {
      if (examples.length == 1) {
        exampleText = " The example is: ${examples.first}";
      } else {
        exampleText = " The examples are: ${examples.join(". ")}";
      }
    }

    // Combine and Speak
    String fullText = "$meaningPart$exampleText";
    await flutterTts.speak(fullText);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_vocabList.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text("No vocabulary found. Please add some first."),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Review"), centerTitle: true),
      body: SafeArea(
        child: PageView.builder(
          itemCount: _vocabList.length,
          controller: PageController(viewportFraction: 0.93),
          // --- ADD THIS LINE HERE ---
          onPageChanged: (index) {
            flutterTts.stop(); // This stops the audio immediately on swipe
          },
          // --------------------------
          itemBuilder: (context, index) {
            final item = _vocabList[index];
            return _buildVocabCard(item);
          },
        ),
      ),
    );
  }

  void _toggleFav(Map<String, dynamic> item) async {
    int newStatus = (item['is_favorite'] == 1) ? 0 : 1;
    await dbHelper.toggleFavorite(item['id'], newStatus == 1);
    _loadData(); // Refresh list to show updated state
  }

  Widget _buildVocabCard(Map<String, dynamic> item) {
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
              // IMAGE SECTION WITH STAR BUTTON
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
                  // THE STAR BUTTON
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
                        onPressed: () => _toggleFav(item),
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
