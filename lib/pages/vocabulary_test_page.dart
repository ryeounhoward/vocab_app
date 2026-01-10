import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Note: Settings import removed since the button was removed
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

  // Quiz mode state (aligned with settings page)
  String _quizMode =
      'desc_to_word'; // desc_to_word, word_to_desc, mixed, pic_to_word, mixed_with_pic
  List<String> _questionModes = []; // per-question mode (for mixed)

  // Logic for the current question
  bool _isAnswered = false;
  String? _selectedAnswer;
  List<String> _currentOptions = [];
  final TextEditingController _answerController = TextEditingController();

  // Text-to-Speech (for meanings in picture mode)
  final FlutterTts flutterTts = FlutterTts();
  Map<String, String>? _currentVoice;

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

  @override
  void initState() {
    super.initState();
    _initTts();
    _generateQuiz();
  }

  @override
  void dispose() {
    flutterTts.stop();
    _answerController.dispose();
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

  // --- SOUND FUNCTION ---
  Future<void> _playSound(bool isCorrect) async {
    try {
      // 1. Check settings
      final prefs = await SharedPreferences.getInstance();
      bool isSoundEnabled = prefs.getBool('quiz_sound_enabled') ?? true;
      if (!isSoundEnabled) return;

      // 2. Create a TEMPORARY player for this specific click
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

  // --- RESULT SOUND FUNCTION ---
  Future<void> _playResultSound() async {
    try {
      // 1. Check settings for game result sound
      final prefs = await SharedPreferences.getInstance();
      bool isResultSoundEnabled =
          prefs.getBool('quiz_result_sound_enabled') ?? true;
      if (!isResultSoundEnabled) return;

      if (_quizData.isEmpty) return;

      // 2. Decide which sound to play based on final score percentage
      final double percentage = _score / _quizData.length;

      String soundPath;
      if (percentage == 1.0) {
        // GOOD JOB
        soundPath = 'sounds/won.mp3';
      } else if (percentage >= 0.9) {
        // AMAZING
        soundPath = 'sounds/won.mp3';
      } else if (percentage >= 0.8) {
        // VERY GOOD
        soundPath = 'sounds/won.mp3';
      } else if (percentage >= 0.7) {
        // GOOD EFFORT
        soundPath = 'sounds/loss.mp3';
      } else {
        // Below 70%: LOSS sound
        soundPath = 'sounds/loss.mp3';
      }

      // 3. Use a temporary player for the result sound
      final player = AudioPlayer();
      await player.play(AssetSource(soundPath));

      // 4. Dispose player after completion
      player.onPlayerComplete.listen((event) {
        player.dispose();
      });
    } catch (e) {
      debugPrint("Error playing result sound: $e");
    }
  }

  Future<void> _generateQuiz() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    int targetCount = prefs.getInt('quiz_total_items') ?? 10;
    // Load quiz mode from settings
    _quizMode = prefs.getString('quiz_mode') ?? 'desc_to_word';

    final dbHelper = DBHelper();
    final rawData = await dbHelper.queryAll(DBHelper.tableVocab);

    List<Map<String, dynamic>> allWords = List.from(rawData);

    if (_quizMode == 'pic_to_word') {
      allWords = allWords
          .where(
            (w) =>
                w['image_path'] != null &&
                w['image_path'].toString().trim().isNotEmpty,
          )
          .toList();
      _allWordsPool = allWords;

      if (allWords.isEmpty) {
        setState(() {
          _quizData = [];
          _isLoading = false;
        });
        return;
      }
    } else {
      _allWordsPool = allWords;

      if (allWords.length < 4) {
        setState(() {
          _quizData = [];
          _isLoading = false;
        });
        return;
      }
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
    // Build per-question modes (for mixed / fixed modes)
    _questionModes = List<String>.generate(_quizData.length, (index) {
      final question = _quizData[index];

      // Mixed (Random): word & definition only
      if (_quizMode == 'mixed') {
        return Random().nextBool() ? 'desc_to_word' : 'word_to_desc';
      }

      // Mixed with picture: picture, word & definition
      if (_quizMode == 'mixed_with_pic') {
        final hasImage =
            question['image_path'] != null &&
            question['image_path'].toString().trim().isNotEmpty;

        if (hasImage) {
          final modes = ['desc_to_word', 'word_to_desc', 'pic_to_word'];
          return modes[Random().nextInt(modes.length)];
        } else {
          // No image for this word: fall back to text-only modes
          return Random().nextBool() ? 'desc_to_word' : 'word_to_desc';
        }
      }

      // All other fixed modes
      return _quizMode;
    });
    _generateOptionsForCurrentQuestion(_allWordsPool);

    setState(() {
      _currentIndex = 0;
      _score = 0;
      _isAnswered = false;
      _selectedAnswer = null;
      _answerController.clear();
      _isLoading = false;
    });
  }

  void _generateOptionsForCurrentQuestion(List<Map<String, dynamic>> pool) {
    if (_quizData.isEmpty) return;

    final currentQuestion = _quizData[_currentIndex];
    final String currentMode = _questionModes.isNotEmpty
        ? _questionModes[_currentIndex]
        : _quizMode;

    // Picture mode uses typed input only, no options.
    if (currentMode == 'pic_to_word') {
      _currentOptions = [];
      return;
    }

    // For desc_to_word: question = description, options = words
    // For word_to_desc: question = word, options = descriptions
    if (currentMode == 'word_to_desc') {
      final String correctDescription =
          (currentQuestion['description'] ?? 'No Description').toString();

      List<String> distractors = pool
          .where(
            (w) =>
                (w['description'] ?? '') !=
                (currentQuestion['description'] ?? ''),
          )
          .map((w) => (w['description'] ?? '').toString())
          .where((d) => d.trim().isNotEmpty)
          .toSet()
          .toList();

      distractors.shuffle();
      List<String> options = distractors.take(3).toList();

      options.add(correctDescription);
      options.shuffle();

      _currentOptions = options;
    } else {
      final String correctWord = (currentQuestion['word'] ?? '').toString();

      List<String> distractors = pool
          .where((w) => (w['word'] ?? '') != currentQuestion['word'])
          .map((w) => (w['word'] ?? '').toString())
          .where((w) => w.trim().isNotEmpty)
          .toSet()
          .toList();

      distractors.shuffle();
      List<String> options = distractors.take(3).toList();

      options.add(correctWord);
      options.shuffle();

      _currentOptions = options;
    }
  }

  String _getCorrectAnswerForCurrentQuestion() {
    if (_quizData.isEmpty) return '';

    final currentQuestion = _quizData[_currentIndex];
    final String currentMode = _questionModes.isNotEmpty
        ? _questionModes[_currentIndex]
        : _quizMode;

    if (currentMode == 'word_to_desc') {
      return (currentQuestion['description'] ?? 'No Description').toString();
    } else {
      return (currentQuestion['word'] ?? '').toString();
    }
  }

  void _submitPictureAnswer() {
    if (_isAnswered) return;

    final userAnswer = _answerController.text.trim();
    if (userAnswer.isEmpty) {
      return;
    }

    final correctAnswer = _getCorrectAnswerForCurrentQuestion();
    final bool isCorrect =
        userAnswer.toLowerCase() == correctAnswer.toLowerCase().trim();

    _playSound(isCorrect);

    setState(() {
      _isAnswered = true;
      _selectedAnswer = userAnswer;
      if (isCorrect) {
        _score++;
      }
    });
  }

  void _submitAnswer(String answer) {
    if (_isAnswered) return;

    String correctAnswer = _getCorrectAnswerForCurrentQuestion();
    bool isCorrect = (answer == correctAnswer);

    // Play sound immediately
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
    // Stop any ongoing TTS when moving to the next question
    flutterTts.stop();

    if (_currentIndex < _quizData.length - 1) {
      setState(() {
        _currentIndex++;
        _isAnswered = false;
        _selectedAnswer = null;
        _generateOptionsForCurrentQuestion(_allWordsPool);
        _answerController.clear();
      });
    } else {
      _showResultDialog();
    }
  }

  Future<void> _speakCurrentMeaning() async {
    if (_quizData.isEmpty) return;

    final currentQuestion = _quizData[_currentIndex];
    final String word = (currentQuestion['word'] ?? '').toString();
    final String desc = (currentQuestion['description'] ?? '').toString();

    if (_currentVoice != null) {
      await flutterTts.setVoice(_currentVoice!);
    }

    if (desc.isNotEmpty) {
      await flutterTts.speak('$word means $desc.');
    } else {
      await flutterTts.speak(word);
    }
  }

  void _showResultDialog() {
    String feedback = _getFeedbackMessage();

    Color feedbackColor = (_score / _quizData.length) >= 0.7
        ? Colors.green
        : Colors.red;

    // Play game result sound based on final score
    _playResultSound();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 40, 24, 10),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                color: feedbackColor,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 24),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _generateQuiz();
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
        // SETTINGS BUTTON REMOVED HERE
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
              Text(
                _quizMode == 'pic_to_word'
                    ? "No words with pictures."
                    : "Not enough words.",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _quizMode == 'pic_to_word'
                    ? "Add images to your vocabulary words to play this mode."
                    : "You need at least 4 words in your vocabulary list to start a quiz.",
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
    final String currentMode = _questionModes.isNotEmpty
        ? _questionModes[_currentIndex]
        : _quizMode;

    final String questionText = currentMode == 'word_to_desc'
        ? (currentQuestion['word'] ?? 'No Word').toString()
        : (currentQuestion['description'] ?? 'No Description').toString();

    final String correctAnswer = _getCorrectAnswerForCurrentQuestion();

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

          if (currentMode == 'pic_to_word') ...[
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: _isAnswered
                                ? const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    topRight: Radius.circular(12),
                                  )
                                : BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child:
                                  (currentQuestion['image_path'] != null &&
                                      currentQuestion['image_path'] != '')
                                  ? Image.file(
                                      File(currentQuestion['image_path']),
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
                          ),
                          if (_isAnswered) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Builder(
                                builder: (context) {
                                  final bool isCorrect =
                                      _selectedAnswer != null &&
                                      _selectedAnswer!.toLowerCase().trim() ==
                                          correctAnswer.toLowerCase().trim();

                                  final Color wordColor = isCorrect
                                      ? Colors.green
                                      : Colors.red;

                                  final String displayText = isCorrect
                                      ? correctAnswer
                                      : 'Correct word: $correctAnswer';

                                  return Text(
                                    displayText,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: wordColor,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Meaning',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.volume_up,
                                          color: Colors.indigo,
                                        ),
                                        onPressed: _speakCurrentMeaning,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    (currentQuestion['description'] ??
                                            'No description provided.')
                                        .toString(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _answerController,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Type the word',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      enabled: !_isAnswered,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isAnswered ? _nextQuestion : _submitPictureAnswer,
                child: Text(
                  _isAnswered
                      ? (_currentIndex == _quizData.length - 1
                            ? 'FINISH'
                            : 'NEXT QUESTION')
                      : 'SUBMIT',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ] else ...[
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Text(
                      currentMode == 'word_to_desc'
                          ? 'WHAT DOES THIS WORD MEAN?'
                          : 'WHAT WORD MATCHES THIS MEANING?',
                      style: const TextStyle(
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
                // ADDED BOTTOM PADDING HERE
                padding: const EdgeInsets.only(bottom: 15),
                itemCount: _currentOptions.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) {
                  final option = _currentOptions[i];
                  return _buildOptionButton(option, correctAnswer);
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
        ],
      ),
    );
  }

  Widget _buildOptionButton(String option, String correctAnswer) {
    Color backgroundColor = Colors.white;
    Color borderColor = Colors.grey.shade300;
    Color textColor = Colors.black87;
    IconData? icon;

    if (_isAnswered) {
      if (option == correctAnswer) {
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
