import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_app/pages/vocabulary_test_settings_page.dart';
import '../database/db_helper.dart';

class VocabularyTestPage extends StatefulWidget {
  const VocabularyTestPage({super.key});

  @override
  State<VocabularyTestPage> createState() => _VocabularyTestPageState();
}

class _VocabularyTestPageState extends State<VocabularyTestPage> {
  // State variables
  bool _isLoading = true;
  List<Map<String, dynamic>> _quizData = [];
  List<Map<String, dynamic>> _allWordsPool = [];
  int _currentIndex = 0;
  int _score = 0;

  // Logic for the current question
  bool _isAnswered = false;
  String? _selectedAnswer;
  List<String> _currentOptions = [];

  String _getFeedbackMessage() {
    if (_quizData.isEmpty) return "";

    double percentage = _score / _quizData.length;

    if (percentage == 1.0) {
      return "GOOD JOB!"; // 100%
    } else if (percentage >= 0.9) {
      return "AMAZING!"; // 90%
    } else if (percentage >= 0.8) {
      return "VERY GOOD!"; // 80%
    } else if (percentage >= 0.7) {
      return "GOOD EFFORT!"; // 70%
    } else {
      return "TRY AGAIN"; // Below 70%
    }
  }

  // REMOVED: final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _generateQuiz();
  }

  @override
  void dispose() {
    // REMOVED: _audioPlayer.dispose();
    // We don't need to dispose a global player anymore
    super.dispose();
  }

  // --- UPDATED SOUND FUNCTION ---
  Future<void> _playSound(bool isCorrect) async {
    try {
      // 1. Check settings
      final prefs = await SharedPreferences.getInstance();
      bool isSoundEnabled = prefs.getBool('quiz_sound_enabled') ?? true;
      if (!isSoundEnabled) return;

      // 2. Create a TEMPORARY player for this specific click
      // This allows sounds to overlap (play at the same time)
      final player = AudioPlayer();

      String soundPath = isCorrect ? 'sounds/correct.mp3' : 'sounds/wrong.mp3';

      // 3. Play the sound
      await player.play(AssetSource(soundPath));

      // 4. Automatically dispose of this temporary player when sound finishes
      player.onPlayerComplete.listen((event) {
        player.dispose();
      });
    } catch (e) {
      debugPrint("Error playing sound: $e");
    }
  }

  Future<void> _generateQuiz() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    int targetCount = prefs.getInt('quiz_total_items') ?? 10;

    final dbHelper = DBHelper();
    final rawData = await dbHelper.queryAll(DBHelper.tableVocab);

    List<Map<String, dynamic>> allWords = List.from(rawData);
    _allWordsPool = allWords;

    if (allWords.length < 4) {
      setState(() {
        _quizData = [];
        _isLoading = false;
      });
      return;
    }

    List<Map<String, dynamic>> finalQuestions = [];

    if (allWords.length >= targetCount) {
      allWords.shuffle();
      finalQuestions = allWords.take(targetCount).toList();
    } else {
      finalQuestions.addAll(allWords);
      final random = Random();
      while (finalQuestions.length < targetCount) {
        finalQuestions.add(allWords[random.nextInt(allWords.length)]);
      }
      finalQuestions.shuffle();
    }

    _quizData = finalQuestions;
    _generateOptionsForCurrentQuestion(_allWordsPool);

    setState(() {
      _currentIndex = 0;
      _score = 0;
      _isAnswered = false;
      _selectedAnswer = null;
      _isLoading = false;
    });
  }

  void _generateOptionsForCurrentQuestion(List<Map<String, dynamic>> pool) {
    if (_quizData.isEmpty) return;

    final currentQuestion = _quizData[_currentIndex];
    final correctWord = currentQuestion['word'] as String;

    List<String> distractors = pool
        .where((w) => w['word'] != correctWord)
        .map((w) => w['word'] as String)
        .toList();

    distractors.shuffle();
    List<String> options = distractors.take(3).toList();

    options.add(correctWord);
    options.shuffle();

    _currentOptions = options;
  }

  void _submitAnswer(String answer) {
    if (_isAnswered) return;

    String correctWord = _quizData[_currentIndex]['word'];
    bool isCorrect = (answer == correctWord);

    // Play sound immediately (it will run in parallel now)
    _playSound(isCorrect);

    setState(() {
      _isAnswered = true;
      _selectedAnswer = answer;

      if (isCorrect) {
        _score++;
      }
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _quizData.length - 1) {
      setState(() {
        _currentIndex++;
        _isAnswered = false;
        _selectedAnswer = null;
        _generateOptionsForCurrentQuestion(_allWordsPool);
      });
    } else {
      _showResultDialog();
    }
  }

  void _showResultDialog() {
    // Get the specific message based on score
    String feedback = _getFeedbackMessage();

    // Determine color based on pass/fail (Optional visual touch)
    Color feedbackColor = (_score / _quizData.length) >= 0.7
        ? Colors.green
        : Colors.red;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 40, 24, 10),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon changes based on score
            Icon(
              (_score / _quizData.length) >= 0.7
                  ? Icons.emoji_events
                  : Icons.sentiment_dissatisfied,
              size: 70,
              color: (_score / _quizData.length) >= 0.7
                  ? Colors.amber
                  : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              "You scored $_score / ${_quizData.length}",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              feedback,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: feedbackColor, // Dynamic color
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 24),
        actions: [
          // --- QUIZ AGAIN BUTTON ---
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx); // Close Dialog
              _generateQuiz(); // Restart
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "QUIZ AGAIN",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vocabulary Quiz"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const QuizSettingsPage(),
                ),
              ).then((_) {
                _generateQuiz();
              });
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_quizData.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.library_books, size: 60, color: Colors.grey),
              const SizedBox(height: 20),
              const Text(
                "Not enough words.",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "You need at least 4 words in your vocabulary list to start a quiz.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Go Back"),
              ),
            ],
          ),
        ),
      );
    }

    final currentQuestion = _quizData[_currentIndex];
    final String questionText =
        currentQuestion['description'] ?? "No Description";
    final String correctWord = currentQuestion['word'];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: (_currentIndex + 1) / _quizData.length,
            backgroundColor: Colors.grey[300],
            color: Colors.indigo,
            minHeight: 8,
          ),
          const SizedBox(height: 10),
          Text(
            "Question ${_currentIndex + 1} of ${_quizData.length}",
            style: const TextStyle(color: Colors.grey, fontSize: 16),
            textAlign: TextAlign.right,
          ),

          const SizedBox(height: 20),

          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Text(
                    "WHAT WORD MATCHES THIS MEANING?",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    questionText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          Expanded(
            child: ListView.separated(
              itemCount: _currentOptions.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) {
                final option = _currentOptions[i];
                return _buildOptionButton(option, correctWord);
              },
            ),
          ),

          if (_isAnswered)
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _nextQuestion,
                child: Text(
                  _currentIndex == _quizData.length - 1
                      ? "FINISH"
                      : "NEXT QUESTION",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionButton(String option, String correctWord) {
    Color backgroundColor = Colors.white;
    Color borderColor = Colors.grey.shade300;
    Color textColor = Colors.black87;
    IconData? icon;

    if (_isAnswered) {
      if (option == correctWord) {
        backgroundColor = Colors.green.shade50;
        borderColor = Colors.green;
        textColor = Colors.green.shade900;
        icon = Icons.check_circle;
      } else if (option == _selectedAnswer) {
        backgroundColor = Colors.red.shade50;
        borderColor = Colors.red;
        textColor = Colors.red.shade900;
        icon = Icons.cancel;
      } else {
        textColor = Colors.grey;
      }
    }

    return InkWell(
      onTap: () => _submitAnswer(option),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            if (icon != null) Icon(icon, color: borderColor),
          ],
        ),
      ),
    );
  }
}
