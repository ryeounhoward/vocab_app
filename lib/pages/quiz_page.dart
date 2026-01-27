import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../database/db_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_app/services/refresh_signal.dart'; // IMPORT THE SIGNAL SERVICE

// Ensure this import points to your sort page
import 'sort_words_data_page.dart';

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
  int? _flippedIndex;
  bool _isIdiomMode = false;

  PageController? _pageController;
  final int _loopSeparator = 10000;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadData();

    // 1. START LISTENING for the global refresh signal
    DataRefreshSignal.refreshNotifier.addListener(_onGlobalRefresh);
  }

  // 2. DEFINE the refresh callback
  void _onGlobalRefresh() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void dispose() {
    // 3. STOP LISTENING to prevent memory leaks
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
      await flutterTts.setVoice({"name": voiceName, "locale": voiceLocale});
    } else {
      await flutterTts.setLanguage("en-US");
    }

    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);
  }

  /// Opens Sort page and refreshes data immediately upon return
  Future<void> _openFilterSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SortWordsDataPage()),
    );

    // Note: Since SortWordsDataPage now sends a refresh signal on save,
    // _onGlobalRefresh will likely trigger automatically.
    // But calling it here manually ensures a refresh even if user just backed out.
    _loadData();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    // Forces SharedPreferences to read latest changes from disk
    await prefs.reload();

    final practiceMode = prefs.getString('practice_mode') ?? 'vocab';
    final bool isIdiomMode = practiceMode == 'idiom';

    final data = await dbHelper.queryAll(
      isIdiomMode ? DBHelper.tableIdioms : DBHelper.tableVocab,
    );

    List<Map<String, dynamic>> filteredData = [];

    if (!isIdiomMode) {
      // --- VOCABULARY FILTERING ---
      final bool useAllWords = prefs.getBool('quiz_use_all_words') ?? true;
      final int? groupId = prefs.getInt('quiz_selected_word_group_id');
      final List<String> storedIds =
          prefs.getStringList('quiz_selected_word_ids') ?? [];
      final Set<int> selectedIds = storedIds
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();

      if (!useAllWords && groupId != null) {
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
      }
    } else {
      // --- IDIOM FILTERING ---
      final bool useAllIdioms = prefs.getBool('quiz_use_all_idioms') ?? true;
      final int? groupId = prefs.getInt('quiz_selected_idiom_group_id');
      final List<String> storedIds =
          prefs.getStringList('quiz_selected_idiom_ids') ?? [];
      final Set<int> selectedIds = storedIds
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();

      if (!useAllIdioms && groupId != null) {
        final Set<int> groupIds = await dbHelper.getIdiomIdsForGroup(groupId);
        filteredData = data
            .where((item) => groupIds.contains(item['id'] as int? ?? -1))
            .toList();
      } else if (useAllIdioms) {
        filteredData = List<Map<String, dynamic>>.from(data);
      } else if (selectedIds.isNotEmpty) {
        filteredData = data
            .where((item) => selectedIds.contains(item['id'] as int? ?? -1))
            .toList();
      }
    }

    List<Map<String, dynamic>> shuffledList = List.from(filteredData);
    shuffledList.shuffle();

    if (mounted) {
      setState(() {
        _isIdiomMode = isIdiomMode;
        _vocabList = shuffledList;
        _flippedIndex =
            null; // Reset flipped state because the word list changed

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
  }

  Future<void> _playFlipSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isSoundEnabled =
          prefs.getBool('practice_swoosh_sound_enabled') ?? true;
      if (!isSoundEnabled) return;

      final player = AudioPlayer();
      await player.play(AssetSource('sounds/swoosh2.mp3'));
      player.onPlayerComplete.listen((event) => player.dispose());
    } catch (e) {
      debugPrint('Error playing flip sound: $e');
    }
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

    return Scaffold(
      // The IconButton has been removed from here
      appBar: AppBar(title: const Text("Practice"), centerTitle: true),
      body: _vocabList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _isIdiomMode
                          ? "No idioms found for the current filter."
                          : "No vocabulary found for the current filter.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Note: You might want to keep this button
                  // or remove it too if you want NO way to filter from here.
                  ElevatedButton.icon(
                    onPressed: _openFilterSettings,
                    icon: const Icon(Icons.filter_list),
                    label: const Text("Adjust Filter Settings"),
                  ),
                ],
              ),
            )
          : SafeArea(
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
                      itemCount: _vocabList.length * _loopSeparator,
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          _flippedIndex = null;
                          flutterTts.stop();
                        });
                      },
                      itemBuilder: (context, index) {
                        final actualIndex = index % _vocabList.length;
                        final item = _vocabList[actualIndex];
                        bool isThisCardFlipped = _flippedIndex == index;

                        return GestureDetector(
                          onTap: () {
                            final bool willShowAnswer = _flippedIndex != index;
                            setState(() {
                              flutterTts.stop();
                              _flippedIndex = (willShowAnswer) ? index : null;
                            });
                            if (willShowAnswer) _playFlipSound();
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
      margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
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
