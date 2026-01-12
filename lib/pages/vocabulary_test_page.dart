import 'dart:math';
import 'dart:io';
import 'dart:async';
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

  // Timer state
  bool _isCountdownTimerEnabled = false;
  bool _isDurationTimerEnabled = false;
  int _totalDurationSeconds = 0; // for countdown
  int _remainingSeconds = 0; // for countdown
  int _elapsedSeconds = 0; // for duration/count-up
  Timer? _timer;
  DateTime? _quizStartTime;
  int _answeredCount = 0;
  bool _timeOver = false;

  // Quiz mode state (aligned with settings page)
  String _quizMode =
      'desc_to_word'; // vocab: desc_to_word, word_to_desc, word_to_synonym, synonym_to_word, mixed, pic_to_word, mixed_with_pic; idioms: idiom_desc_to_idiom, idiom_to_desc, idiom_mixed
  List<String> _questionModes = []; // per-question mode (for mixed)

  // Logic for the current question
  bool _isAnswered = false;
  String? _selectedAnswer;
  List<String> _currentOptions = [];
  final TextEditingController _answerController = TextEditingController();

  // Text-to-Speech (for meanings in picture mode)
  final FlutterTts flutterTts = FlutterTts();
  Map<String, String>? _currentVoice;

  // Cached session so leaving the page does not reset the quiz
  static List<Map<String, dynamic>>? _cachedQuizData;
  static List<Map<String, dynamic>>? _cachedAllWordsPool;
  static List<String> _cachedQuestionModes = [];
  static List<String> _cachedCurrentOptions = [];
  static int _cachedCurrentIndex = 0;
  static int _cachedScore = 0;
  static bool _cachedIsAnswered = false;
  static String? _cachedSelectedAnswer;
  static bool _cachedTimeOver = false;
  static bool _cachedIsCountdownTimerEnabled = false;
  static bool _cachedIsDurationTimerEnabled = false;
  static int _cachedTotalDurationSeconds = 0;
  static int _cachedRemainingSeconds = 0;
  static int _cachedElapsedSeconds = 0;
  static int _cachedAnsweredCount = 0;
  static String? _cachedQuizMode;

  static int _cachedHintPoints = 0;

  int _hintPoints = 0;
  String? _pictureHint;

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
    _initQuizPage();
  }

  @override
  void dispose() {
    _saveSession();
    flutterTts.stop();
    _timer?.cancel();
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

  // --- HINT SOUND FUNCTION ---
  Future<void> _playHintSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool isSoundEnabled = prefs.getBool('quiz_sound_enabled') ?? true;
      if (!isSoundEnabled) return;

      final player = AudioPlayer();
      await player.play(AssetSource('sounds/star2.mp3'));
      player.onPlayerComplete.listen((event) {
        player.dispose();
      });
    } catch (e) {
      debugPrint("Error playing hint sound: $e");
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

  // Initialize quiz either from cached session (same mode) or as a new quiz
  Future<void> _initQuizPage() async {
    final prefs = await SharedPreferences.getInstance();
    final String mode = prefs.getString('quiz_mode') ?? 'desc_to_word';

    // Restore only if we have a cached quiz with the same mode
    if (_cachedQuizData != null &&
        _cachedQuizData!.isNotEmpty &&
        _cachedQuizMode == mode &&
        !_cachedTimeOver) {
      setState(() {
        _quizMode = mode;
        _quizData = _cachedQuizData!;
        _allWordsPool = _cachedAllWordsPool ?? [];
        _questionModes = List<String>.from(_cachedQuestionModes);
        _currentOptions = List<String>.from(_cachedCurrentOptions);
        _currentIndex = _cachedCurrentIndex;
        _score = _cachedScore;
        _isAnswered = _cachedIsAnswered;
        _selectedAnswer = _cachedSelectedAnswer;
        _timeOver = _cachedTimeOver;
        _isCountdownTimerEnabled = _cachedIsCountdownTimerEnabled;
        _isDurationTimerEnabled = _cachedIsDurationTimerEnabled;
        _totalDurationSeconds = _cachedTotalDurationSeconds;
        _remainingSeconds = _cachedRemainingSeconds;
        _elapsedSeconds = _cachedElapsedSeconds;
        _answeredCount = _cachedAnsweredCount;
        _hintPoints = _cachedHintPoints;
        _isLoading = false;
        // Recreate a start time based on elapsed seconds
        _quizStartTime = DateTime.now().subtract(
          Duration(seconds: _elapsedSeconds),
        );
      });

      _startRestoredTimer();
    } else {
      // No valid cache or mode changed: start a new quiz
      _generateQuiz();
    }
  }

  void _startRestoredTimer() {
    if (!(_isCountdownTimerEnabled || _isDurationTimerEnabled) ||
        _quizData.isEmpty ||
        _timeOver) {
      return;
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _elapsedSeconds++;

        if (_isCountdownTimerEnabled) {
          if (_remainingSeconds <= 1) {
            _remainingSeconds = 0;
            timer.cancel();
            _handleTimeUp();
          } else {
            _remainingSeconds--;
          }
        }
      });
    });
  }

  Future<void> _generateQuiz() async {
    setState(() => _isLoading = true);

    // Reset any existing timer
    _timer?.cancel();
    _timeOver = false;
    _answeredCount = 0;
    _elapsedSeconds = 0;

    final prefs = await SharedPreferences.getInstance();
    int targetCount = prefs.getInt('quiz_total_items') ?? 10;
    // Load quiz mode and timer settings from preferences
    _quizMode = prefs.getString('quiz_mode') ?? 'desc_to_word';

    bool countdown = prefs.getBool('quiz_timer_enabled') ?? false;
    bool duration = prefs.getBool('quiz_duration_timer_enabled') ?? !countdown;

    // Ensure mutual exclusivity between countdown and duration timers
    if (countdown && duration) {
      duration = false; // Prefer countdown if both somehow true
    }

    _isCountdownTimerEnabled = countdown;
    _isDurationTimerEnabled = duration;

    // Clear any previous cached session when starting a fresh quiz
    _cachedQuizData = null;
    _cachedAllWordsPool = null;
    _cachedQuestionModes = [];
    _cachedCurrentOptions = [];
    _cachedQuizMode = _quizMode;

    final dbHelper = DBHelper();

    // Decide which table to use based on quiz mode
    final bool isIdiomQuiz =
        _quizMode == 'idiom_desc_to_idiom' ||
        _quizMode == 'idiom_to_desc' ||
        _quizMode == 'idiom_mixed';
    final bool isSynonymQuiz =
        _quizMode == 'word_to_synonym' || _quizMode == 'synonym_to_word';

    final rawData = await dbHelper.queryAll(
      isIdiomQuiz ? DBHelper.tableIdioms : DBHelper.tableVocab,
    );

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
    } else if (isSynonymQuiz) {
      // Only use words that actually have at least one synonym
      allWords = allWords.where((w) {
        final raw = (w['synonyms'] as String? ?? '').trim();
        if (raw.isEmpty) return false;
        final parts = raw
            .split(RegExp(r'[\n,]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        return parts.isNotEmpty;
      }).toList();

      _allWordsPool = allWords;

      if (allWords.length < 4) {
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

      // Mixed (Random): word & definition only (vocabulary)
      if (_quizMode == 'mixed') {
        return Random().nextBool() ? 'desc_to_word' : 'word_to_desc';
      }

      // Mixed with picture: picture, word & definition (vocabulary)
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

      // Idioms mixed: idiom & meaning
      if (_quizMode == 'idiom_mixed') {
        return Random().nextBool() ? 'idiom_desc_to_idiom' : 'idiom_to_desc';
      }

      // All other fixed modes
      return _quizMode;
    });

    // Reset quiz state for a fresh run
    setState(() {
      _currentIndex = 0;
      _score = 0;
      _isAnswered = false;
      _selectedAnswer = null;
      _answerController.clear();
      _isLoading = false;
      _hintPoints = 0;
      _pictureHint = null;
      _generateOptionsForCurrentQuestion(_allWordsPool);
      _quizStartTime = DateTime.now();
      _elapsedSeconds = 0;

      // Start timer if either countdown or duration timer is enabled
      if ((_isCountdownTimerEnabled || _isDurationTimerEnabled) &&
          _quizData.isNotEmpty) {
        if (_isCountdownTimerEnabled) {
          _totalDurationSeconds = _quizData.length * 60;
          _remainingSeconds = _totalDurationSeconds;
        } else {
          _totalDurationSeconds = 0;
          _remainingSeconds = 0;
        }

        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            _elapsedSeconds++;

            if (_isCountdownTimerEnabled) {
              if (_remainingSeconds <= 1) {
                _remainingSeconds = 0;
                timer.cancel();
                _handleTimeUp();
              } else {
                _remainingSeconds--;
              }
            }
          });
        });
      }
    });
  }

  void _saveSession() {
    if (_quizData.isEmpty) return;

    _cachedQuizData = _quizData
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    _cachedAllWordsPool = _allWordsPool
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    _cachedQuestionModes = List<String>.from(_questionModes);
    _cachedCurrentOptions = List<String>.from(_currentOptions);
    _cachedCurrentIndex = _currentIndex;
    _cachedScore = _score;
    _cachedIsAnswered = _isAnswered;
    _cachedSelectedAnswer = _selectedAnswer;
    _cachedTimeOver = _timeOver;
    _cachedIsCountdownTimerEnabled = _isCountdownTimerEnabled;
    _cachedIsDurationTimerEnabled = _isDurationTimerEnabled;
    _cachedTotalDurationSeconds = _totalDurationSeconds;
    _cachedRemainingSeconds = _remainingSeconds;
    _cachedElapsedSeconds = _elapsedSeconds;
    _cachedAnsweredCount = _answeredCount;
    _cachedHintPoints = _hintPoints;
    _cachedQuizMode = _quizMode;
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
    // For word_to_synonym: question = word, options = synonyms
    // For idiom_to_desc: question = idiom, options = meanings
    if (currentMode == 'word_to_desc' || currentMode == 'idiom_to_desc') {
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
    } else if (currentMode == 'word_to_synonym') {
      // Options are synonyms; correct one is a random synonym of this word
      final String correctSynonym = _getRandomSynonym(currentQuestion);

      // Cache the chosen synonym so answer checking is stable
      currentQuestion['_correctSynonym'] = correctSynonym;

      List<String> distractors = pool
          .where((w) => w['id'] != currentQuestion['id'])
          .map(_getRandomSynonym)
          .where((s) => s.trim().isNotEmpty && s != correctSynonym)
          .toSet()
          .toList();

      distractors.shuffle();
      List<String> options = distractors.take(3).toList();

      options.add(correctSynonym);
      options.shuffle();

      _currentOptions = options;
    } else {
      // For desc_to_word: options are vocabulary words
      // For idiom_desc_to_idiom: options are idioms
      final String key = currentMode.startsWith('idiom') ? 'idiom' : 'word';
      final String correctTerm = (currentQuestion[key] ?? '').toString();

      List<String> distractors = pool
          .where((w) => (w[key] ?? '') != currentQuestion[key])
          .map((w) => (w[key] ?? '').toString())
          .where((w) => w.trim().isNotEmpty)
          .toSet()
          .toList();

      distractors.shuffle();
      List<String> options = distractors.take(3).toList();

      options.add(correctTerm);
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

    if (currentMode == 'word_to_desc' || currentMode == 'idiom_to_desc') {
      return (currentQuestion['description'] ?? 'No Description').toString();
    } else if (currentMode == 'word_to_synonym') {
      final dynamic stored = currentQuestion['_correctSynonym'];
      if (stored is String && stored.isNotEmpty) {
        return stored;
      }

      // Fallback (should be rare): compute one on the fly
      return _getRandomSynonym(currentQuestion);
    } else {
      final String key = currentMode.startsWith('idiom') ? 'idiom' : 'word';
      return (currentQuestion[key] ?? '').toString();
    }
  }

  void _submitPictureAnswer() {
    if (_isAnswered || _timeOver) return;

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
      _answeredCount++;
      if (isCorrect) {
        _score++;
        _hintPoints++;
      }
    });
  }

  void _submitAnswer(String answer) {
    if (_isAnswered || _timeOver) return;

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

      _answeredCount++;
    });
  }

  String _getRandomSynonym(Map<String, dynamic> item) {
    final raw = (item['synonyms'] as String? ?? '').trim();
    if (raw.isEmpty) return '';

    final parts = raw
        .split(RegExp(r'[\n,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '';
    parts.shuffle();
    return parts.first;
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
        _pictureHint = null;
      });
    } else {
      // Finished all questions before timer expired
      _timer?.cancel();
      _showResultDialog();
    }
  }

  void _handleTimeUp() {
    if (!mounted || _timeOver) return;

    setState(() {
      _timeOver = true;
    });

    _showTimeUpDialog();
  }

  void _usePictureHint() {
    if (_quizData.isEmpty || _isAnswered || _hintPoints <= 0) {
      return;
    }

    final currentQuestion = _quizData[_currentIndex];
    final String hint = _getRandomSynonym(currentQuestion);

    if (hint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No synonym available for this word to use as a hint."),
        ),
      );
      return;
    }

    setState(() {
      _pictureHint = hint;
      _hintPoints--;
    });

    _playHintSound();
  }

  Future<void> _speakCurrentMeaning() async {
    if (_quizData.isEmpty) return;

    final currentQuestion = _quizData[_currentIndex];
    final String word = (currentQuestion['word'] ?? '').toString();
    final String desc = (currentQuestion['description'] ?? '').toString();
    final String synonym = _getRandomSynonym(currentQuestion);

    if (_currentVoice != null) {
      await flutterTts.setVoice(_currentVoice!);
    }

    if (desc.isEmpty && synonym.isEmpty) {
      await flutterTts.speak(word);
      return;
    }

    String sentence = '';
    if (desc.isNotEmpty) {
      sentence = '$word means $desc.';
    } else {
      sentence = word;
    }

    if (synonym.isNotEmpty) {
      sentence += ' A synonym is $synonym.';
    }

    await flutterTts.speak(sentence);
  }

  void _showResultDialog() {
    String feedback = _getFeedbackMessage();

    Color feedbackColor = (_score / _quizData.length) >= 0.7
        ? Colors.green
        : Colors.red;

    // Play game result sound based on final score
    _playResultSound();

    // Compute summary numbers (works for all modes and with/without timers)
    final int totalItems = _quizData.length;
    final int answered = _answeredCount.clamp(0, totalItems);
    final int correct = _score.clamp(0, answered);
    final int wrong = (answered - correct).clamp(0, totalItems);
    final int notAnswered = (totalItems - answered).clamp(0, totalItems);

    Duration? elapsedDuration;
    if (_quizStartTime != null) {
      int elapsedSeconds;

      if (_elapsedSeconds > 0) {
        elapsedSeconds = _elapsedSeconds;
      } else {
        elapsedSeconds = DateTime.now().difference(_quizStartTime!).inSeconds;
      }

      if (_isCountdownTimerEnabled && _totalDurationSeconds > 0) {
        elapsedSeconds = elapsedSeconds.clamp(0, _totalDurationSeconds);
      }

      if (elapsedSeconds < 0) elapsedSeconds = 0;
      elapsedDuration = Duration(seconds: elapsedSeconds);
    }

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
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (elapsedDuration != null)
                    Text('Duration: ${_formatDuration(elapsedDuration)}'),
                  if (elapsedDuration != null) const SizedBox(height: 8),
                  Text('Total items: $totalItems'),
                  Text('Correct: $correct'),
                  Text('Wrong: $wrong'),
                  Text('Not answered: $notAnswered'),
                ],
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

  void _showTimeUpDialog() {
    if (_quizData.isEmpty) return;

    final int totalItems = _quizData.length;
    final int answered = _answeredCount.clamp(0, totalItems);
    final int correct = _score.clamp(0, answered);
    final int wrong = (answered - correct).clamp(0, totalItems);
    final int notAnswered = (totalItems - answered).clamp(0, totalItems);

    final int baseSeconds = _elapsedSeconds > 0
        ? _elapsedSeconds
        : _totalDurationSeconds;
    final Duration totalDuration = Duration(
      seconds: baseSeconds.clamp(0, 86400 * 7),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Time is up!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total time: ${_formatDuration(totalDuration)}'),
            const SizedBox(height: 12),
            Text('Total items: $totalItems'),
            Text('Answered: $answered'),
            Text('Correct: $correct'),
            Text('Wrong: $wrong'),
            Text('Not answered: $notAnswered'),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _generateQuiz();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'QUIZ AGAIN',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int seconds = d.inSeconds.remainder(60);

    final parts = <String>[];
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0 || hours > 0) parts.add('${minutes}m');
    parts.add('${seconds}s');
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vocabulary Quiz"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Restart quiz',
            onPressed: _quizData.isEmpty ? null : _confirmRestartQuiz,
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
              Text(
                _quizMode == 'pic_to_word'
                    ? "Add images to your vocabulary words to play this mode."
                    : (_quizMode == 'idiom_desc_to_idiom' ||
                          _quizMode == 'idiom_to_desc' ||
                          _quizMode == 'idiom_mixed')
                    ? "You need at least 4 idioms in your idiom list to start a quiz."
                    : (_quizMode == 'word_to_synonym' ||
                          _quizMode == 'synonym_to_word')
                    ? "You need at least 4 words with synonyms in your vocabulary list to start this quiz."
                    : "You need at least 4 words in your vocabulary list to start a quiz.",
                textAlign: TextAlign.center,
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

    final bool isSynonymMode =
        currentMode == 'word_to_synonym' || currentMode == 'synonym_to_word';
    final bool showSynonymHint =
        !currentMode.startsWith('idiom') &&
        !isSynonymMode &&
        currentMode != 'word_to_desc' &&
        currentMode != 'desc_to_word';
    final String randomSynonym = showSynonymHint
        ? _getRandomSynonym(currentQuestion)
        : '';

    String questionText;
    if (currentMode == 'word_to_desc') {
      questionText = (currentQuestion['word'] ?? 'No Word').toString();
    } else if (currentMode == 'idiom_to_desc') {
      questionText = (currentQuestion['idiom'] ?? 'No Idiom').toString();
    } else if (currentMode == 'synonym_to_word') {
      // Show one synonym as the question; cache it so it stays stable
      String promptSynonym =
          (currentQuestion['_promptSynonym'] as String? ?? '').trim();
      if (promptSynonym.isEmpty) {
        promptSynonym = _getRandomSynonym(currentQuestion);
        currentQuestion['_promptSynonym'] = promptSynonym;
      }
      questionText = promptSynonym.isNotEmpty
          ? promptSynonym
          : 'No synonym available for this word.';
    } else {
      questionText = (currentQuestion['description'] ?? 'No Description')
          .toString();
    }

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (!_timeOver && _isCountdownTimerEnabled)
                Text(
                  'Time left: ${_formatDuration(Duration(seconds: _remainingSeconds))}',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (!_timeOver && _isDurationTimerEnabled)
                Text(
                  'Time: ${_formatDuration(Duration(seconds: _elapsedSeconds))}',
                  style: const TextStyle(
                    color: Colors.indigo,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                const SizedBox.shrink(),
              Text(
                "Question ${_currentIndex + 1} of ${_quizData.length}",
                style: const TextStyle(color: Colors.grey, fontSize: 16),
                textAlign: TextAlign.right,
              ),
            ],
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
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Hint points: $_hintPoints',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: !_isAnswered && _hintPoints > 0
                                          ? _usePictureHint
                                          : null,
                                      icon: const Icon(
                                        Icons.lightbulb_outline,
                                        size: 18,
                                      ),
                                      label: const Text('HINT'),
                                    ),
                                  ],
                                ),
                                if (_pictureHint != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Hint: $_pictureHint',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ],
                              ],
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
                                      : correctAnswer;

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
                                  const SizedBox(height: 8),
                                  Text(
                                    randomSynonym.isNotEmpty
                                        ? 'Synonym: $randomSynonym'
                                        : 'No synonym available for this word.',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.blueGrey,
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 15),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            currentMode == 'word_to_desc'
                                ? 'WHAT DOES THIS WORD MEAN?'
                                : currentMode == 'word_to_synonym'
                                ? 'WHICH SYNONYM MATCHES THIS WORD?'
                                : currentMode == 'synonym_to_word'
                                ? 'WHICH WORD MATCHES THIS SYNONYM?'
                                : currentMode == 'idiom_to_desc'
                                ? 'WHAT DOES THIS IDIOM MEAN?'
                                : currentMode == 'idiom_desc_to_idiom'
                                ? 'WHICH IDIOM MATCHES THIS MEANING?'
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
                          if (showSynonymHint) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                randomSynonym.isNotEmpty
                                    ? 'Synonym: $randomSynonym'
                                    : 'No synonym available for this word.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'OPTIONS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _currentOptions.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) {
                        final option = _currentOptions[i];
                        return _buildOptionButton(option, correctAnswer);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isAnswered)
              SizedBox(
                height: 50,
                width: double.infinity,
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

  void _confirmRestartQuiz() {
    if (_quizData.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart quiz?'),
        content: const Text(
          'This will start a new quiz and reset your current progress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _timer?.cancel();
              _generateQuiz();
            },
            child: const Text('Restart', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
