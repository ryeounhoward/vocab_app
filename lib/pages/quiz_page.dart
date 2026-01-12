import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../database/db_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final dbHelper = DBHelper();
  final FlutterTts flutterTts = FlutterTts();
  List<Map<String, dynamic>> _vocabList = [];
  bool _isLoading = true;
  int? _flippedIndex; // This will track the absolute PageView index
  bool _isIdiomMode = false; // practice mode: false = words, true = idioms

  // 1. Define a PageController
  PageController? _pageController;
  // A large number to simulate infinity
  final int _loopSeparator = 10000;

  // --- FLIP SOUND ---
  Future<void> _playFlipSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Separate practice swoosh preference; default ON
      final bool isSoundEnabled =
          prefs.getBool('practice_swoosh_sound_enabled') ?? true;
      if (!isSoundEnabled) return;

      final player = AudioPlayer();
      await player.play(AssetSource('sounds/swoosh2.mp3'));

      player.onPlayerComplete.listen((event) {
        player.dispose();
      });
    } catch (e) {
      debugPrint('Error playing flip sound: $e');
    }
  }

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
    final prefs = await SharedPreferences.getInstance();
    final practiceMode = prefs.getString('practice_mode') ?? 'vocab';
    final bool isIdiomMode = practiceMode == 'idiom';

    final data = await dbHelper.queryAll(
      isIdiomMode ? DBHelper.tableIdioms : DBHelper.tableVocab,
    );

    // For vocabulary and idiom modes, respect the selected subsets from
    // SortWordsDataPage and SortIdiomsDataPage, respectively.
    // If "use all" is OFF and nothing is selected, use an empty list.
    List<Map<String, dynamic>> filteredData;
    if (!isIdiomMode) {
      // Vocabulary subset
      final bool useAllWords = prefs.getBool('quiz_use_all_words') ?? true;
      final List<String> storedIds =
          prefs.getStringList('quiz_selected_word_ids') ?? <String>[];
      final Set<int> selectedIds = storedIds
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();

      if (useAllWords) {
        filteredData = List<Map<String, dynamic>>.from(data);
      } else if (selectedIds.isNotEmpty) {
        filteredData = data
            .where((item) => selectedIds.contains(item['id'] as int? ?? -1))
            .toList();
      } else {
        filteredData = <Map<String, dynamic>>[];
      }
    } else {
      // Idiom subset
      final bool useAllIdioms = prefs.getBool('quiz_use_all_idioms') ?? true;
      final List<String> storedIds =
          prefs.getStringList('quiz_selected_idiom_ids') ?? <String>[];
      final Set<int> selectedIds = storedIds
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();

      if (useAllIdioms) {
        filteredData = List<Map<String, dynamic>>.from(data);
      } else if (selectedIds.isNotEmpty) {
        filteredData = data
            .where((item) => selectedIds.contains(item['id'] as int? ?? -1))
            .toList();
      } else {
        filteredData = <Map<String, dynamic>>[];
      }
    }

    List<Map<String, dynamic>> shuffledList = List.from(filteredData);
    shuffledList.shuffle(); // 2. Shuffle the list

    setState(() {
      _isIdiomMode = isIdiomMode;
      _vocabList = shuffledList;

      // 3. Initialize controller at a high multiple of the list length
      // This allows swiping left immediately.
      if (_vocabList.isNotEmpty) {
        int initialPage = _vocabList.length * (_loopSeparator ~/ 2);
        _pageController = PageController(
          viewportFraction: 0.85,
          initialPage: initialPage,
        );
      }
      _isLoading = false;
    });
  }

  Future<void> _speak(String text) async {
    String textToRead = text;
    if (textToRead == "No description available.") {
      textToRead = "There is no meaning available for this word.";
    }
    await flutterTts.speak(textToRead);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_vocabList.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            _isIdiomMode
                ? "No idioms found. Please add some first."
                : "No vocabulary found. Please add some first.",
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Practice"), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "Tap the card to see the answer.\nSwipe to move to the next word.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            Expanded(
              child: PageView.builder(
                // 4. Set a very high item count for infinite looping
                itemCount: _vocabList.length * _loopSeparator,
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _flippedIndex = null; // Reset flip state on swipe
                    flutterTts.stop();
                  });
                },
                itemBuilder: (context, index) {
                  // 5. Use modulo to map the large index back to the list range
                  final actualIndex = index % _vocabList.length;
                  final item = _vocabList[actualIndex];
                  bool isThisCardFlipped = _flippedIndex == index;

                  return GestureDetector(
                    onTap: () {
                      final bool willShowAnswer = _flippedIndex != index;

                      setState(() {
                        flutterTts.stop();
                        if (_flippedIndex == index) {
                          _flippedIndex = null;
                        } else {
                          _flippedIndex = index;
                        }
                      });

                      // Play sound only when flipping to show the answer side
                      if (willShowAnswer) {
                        _playFlipSound();
                      }
                    },
                    child: _buildFlipCard(item, isThisCardFlipped),
                  );
                },
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  // --- KEEPING YOUR EXACT CARD DESIGN ---
  Widget _buildFlipCard(Map<String, dynamic> item, bool isFlipped) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final rotate = Tween(begin: 3.14, end: 0.0).animate(animation);
        return AnimatedBuilder(
          animation: rotate,
          child: child,
          builder: (context, child) {
            final isBack = (rotate.value > 3.14 / 2);
            return Transform(
              transform: Matrix4.rotationY(rotate.value),
              alignment: Alignment.center,
              child: isBack ? Container() : child,
            );
          },
        );
      },
      child: isFlipped
          ? _buildCardSide(
              key: const ValueKey(true),
              content: _isIdiomMode
                  ? (item['idiom'] ?? "No idiom")
                  : (item['word'] ?? "No word"),
              subContent:
                  !_isIdiomMode &&
                      item['word_type'] != null &&
                      item['word_type'] != ""
                  ? "(${item['word_type']})"
                  : null,
              color: Colors.indigo,
              textColor: Colors.white,
              isDescription: false,
            )
          : _buildCardSide(
              key: const ValueKey(false),
              content: item['description'] != null && item['description'] != ""
                  ? item['description']
                  : "No description available.",
              subContent: null,
              color: Colors.white,
              textColor: Colors.black87,
              isDescription: true,
            ),
    );
  }

  Widget _buildCardSide({
    required Key key,
    required String content,
    String? subContent,
    required Color color,
    required Color textColor,
    required bool isDescription,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 5),
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              // ignore: deprecated_member_use
              icon: Icon(Icons.volume_up, color: textColor.withOpacity(0.6)),
              onPressed: () => _speak(content),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    content,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isDescription ? 18 : 28,
                      height: 1.4,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  if (subContent != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subContent,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        // ignore: deprecated_member_use
                        color: textColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
