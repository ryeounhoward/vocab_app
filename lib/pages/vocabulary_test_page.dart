import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import 'quiz_history_page.dart';

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

  // In-memory caches to avoid re-querying the DB on every restart.
  // (This removes the loading spinner in most restarts.)
  List<Map<String, dynamic>>? _rawVocabCache;
  List<Map<String, dynamic>>? _rawIdiomsCache;

  // Timer state
  bool _isCountdownTimerEnabled = false;
  bool _isDurationTimerEnabled = false;
  int _totalDurationSeconds = 0; // for countdown
  int _remainingSeconds = 0; // for countdown
  int _elapsedSeconds = 0; // for duration/count-up
  Timer? _timer;
  DateTime? _quizStartTime;
  DateTime? _questionStartTime;
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
  static String? _cachedSelectionSignature;

  static int _cachedHintPoints = 0;

  int _hintPoints = 0;
  String? _pictureHint;
  List<String> _revealedHints = [];
  String? _emptyReason; // tracks why the quiz has no data
  String? _selectionSignature;

  // Quiz history (only for desc_to_word / word_to_desc)
  final List<Map<String, dynamic>> _historyItems = [];
  bool _historySavedForCurrentQuiz = false;
  Map<String, dynamic>? _lastSavedHistoryItem;

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

  String _buildSelectionSignature(SharedPreferences prefs, String mode) {
    final bool isIdiomQuiz =
        mode == 'idiom_desc_to_idiom' ||
        mode == 'idiom_to_desc' ||
        mode == 'idiom_mixed';

    if (isIdiomQuiz) {
      final bool useAllIdioms = prefs.getBool('quiz_use_all_idioms') ?? true;
      final List<String> selectedIds =
          prefs.getStringList('quiz_selected_idiom_ids') ?? const <String>[];
      final int? groupId = prefs.getInt('quiz_selected_idiom_group_id');
      return 'idioms:$useAllIdioms:${groupId ?? 'none'}:${selectedIds.join(',')}';
    }

    final bool useAllWords = prefs.getBool('quiz_use_all_words') ?? true;
    final List<String> selectedIds =
        prefs.getStringList('quiz_selected_word_ids') ?? const <String>[];
    final int? groupId = prefs.getInt('quiz_selected_word_group_id');
    return 'words:$useAllWords:${groupId ?? 'none'}:${selectedIds.join(',')}';
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
    final String signature = _buildSelectionSignature(prefs, mode);

    // Restore only if we have a cached quiz with the same mode
    if (_cachedQuizData != null &&
        _cachedQuizData!.isNotEmpty &&
        _cachedQuizMode == mode &&
        _cachedSelectionSignature == signature &&
        !_cachedTimeOver) {
      setState(() {
        _quizMode = mode;
        _selectionSignature = signature;
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
        _questionStartTime = DateTime.now();
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
    await _generateQuizInternal(forceReload: false);
  }

  Future<void> _generateQuizFresh() async {
    await _generateQuizInternal(forceReload: true);
  }

  Future<void> _generateQuizInternal({required bool forceReload}) async {
    final prefs = await SharedPreferences.getInstance();

    // Load quiz mode early so we know which table we need.
    final String requestedMode = prefs.getString('quiz_mode') ?? 'desc_to_word';

    final bool isIdiomQuiz =
        requestedMode == 'idiom_desc_to_idiom' ||
        requestedMode == 'idiom_to_desc' ||
        requestedMode == 'idiom_mixed';

    final bool willQueryDb =
        forceReload ||
        (isIdiomQuiz ? _rawIdiomsCache == null : _rawVocabCache == null);

    if (willQueryDb) {
      setState(() => _isLoading = true);
    }

    // Reset any existing timer
    _timer?.cancel();
    _timeOver = false;
    _answeredCount = 0;
    _elapsedSeconds = 0;
    _emptyReason = null;
    _historyItems.clear();
    _historySavedForCurrentQuiz = false;

    int targetCount = prefs.getInt('quiz_total_items') ?? 10;
    // Load quiz mode and timer settings from preferences
    _quizMode = requestedMode;
    _selectionSignature = _buildSelectionSignature(prefs, requestedMode);

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
    final bool isSynonymQuiz =
      _quizMode == 'word_to_synonym' || _quizMode == 'synonym_to_word';
    final bool isSentenceQuiz = _quizMode == 'sentence_to_word';

    List<Map<String, dynamic>> rawData;
    if (!forceReload) {
      final cached = isIdiomQuiz ? _rawIdiomsCache : _rawVocabCache;
      if (cached != null) {
        rawData = cached
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
      } else {
        rawData = await dbHelper.queryAll(
          isIdiomQuiz ? DBHelper.tableIdioms : DBHelper.tableVocab,
        );
      }
    } else {
      rawData = await dbHelper.queryAll(
        isIdiomQuiz ? DBHelper.tableIdioms : DBHelper.tableVocab,
      );
    }

    // Apply selected-words / selected-idioms filters
    if (!isIdiomQuiz) {
      final bool useAll = prefs.getBool('quiz_use_all_words') ?? true;
      if (!useAll) {
        final List<String> selectedIdsStr =
            prefs.getStringList('quiz_selected_word_ids') ?? <String>[];
        final Set<int> selectedIds = selectedIdsStr
            .map((s) => int.tryParse(s))
            .whereType<int>()
            .toSet();

        // If user turned off "use all" but did not select anything,
        // treat as "no data" instead of falling back to all words.
        if (selectedIds.isEmpty) {
          setState(() {
            _quizData = [];
            _isLoading = false;
            _emptyReason = 'no_words_selected';
          });
          return;
        }

        rawData = rawData
            .where((item) {
              final dynamic id = item['id'];
              if (id is int) {
                return selectedIds.contains(id);
              }
              if (id is String) {
                final parsed = int.tryParse(id);
                return parsed != null && selectedIds.contains(parsed);
              }
              return false;
            })
            .toList(growable: false);
      }
    } else {
      final bool useAllIdioms = prefs.getBool('quiz_use_all_idioms') ?? true;
      if (!useAllIdioms) {
        final List<String> selectedIdsStr =
            prefs.getStringList('quiz_selected_idiom_ids') ?? <String>[];
        final Set<int> selectedIds = selectedIdsStr
            .map((s) => int.tryParse(s))
            .whereType<int>()
            .toSet();

        if (selectedIds.isEmpty) {
          setState(() {
            _quizData = [];
            _isLoading = false;
            _emptyReason = 'no_idioms_selected';
          });
          return;
        }

        rawData = rawData
            .where((item) {
              final dynamic id = item['id'];
              if (id is int) {
                return selectedIds.contains(id);
              }
              if (id is String) {
                final parsed = int.tryParse(id);
                return parsed != null && selectedIds.contains(parsed);
              }
              return false;
            })
            .toList(growable: false);
      }
    }

    // Store caches (deep copy) for fast restarts.
    final stored = rawData
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    if (isIdiomQuiz) {
      _rawIdiomsCache = stored;
    } else {
      _rawVocabCache = stored;
    }

    List<Map<String, dynamic>> allWords = List<Map<String, dynamic>>.from(
      rawData,
    );

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
      // For synonym quiz modes:
      // - Questions must have a real word + at least one parsed synonym.
      // - Options pool can include all vocab words (even without synonyms)
      //   so synonym_to_word has enough distractor words.
      final List<Map<String, dynamic>> optionsPool = allWords.where((w) {
        final String word = (w['word'] ?? '').toString().trim();
        return word.isNotEmpty;
      }).toList();

      // Only use words that actually have at least one synonym as QUESTIONS.
      final List<Map<String, dynamic>> synonymQuestions = allWords.where((w) {
        final String word = (w['word'] ?? '').toString().trim();
        if (word.isEmpty) return false;
        return _parseSynonyms(w['synonyms']).isNotEmpty;
      }).toList();

      // Use the broad pool for options, but questions only from synonym words.
      _allWordsPool = optionsPool;
      allWords = synonymQuestions;

      // We can still run a quiz with fewer than 4 synonym-words; the options
      // list will just be smaller if there aren't enough distractors.
      if (allWords.isEmpty) {
        setState(() {
          _quizData = [];
          _isLoading = false;
        });
        return;
      }
    } else if (isSentenceQuiz) {
      // For sentence quiz mode:
      // - Questions must have at least one example sentence.
      // - Options can include all vocab words for distractors.
      final List<Map<String, dynamic>> optionsPool = allWords.where((w) {
        final String word = (w['word'] ?? '').toString().trim();
        return word.isNotEmpty;
      }).toList();

      final List<Map<String, dynamic>> sentenceQuestions = allWords.where((w) {
        final String word = (w['word'] ?? '').toString().trim();
        if (word.isEmpty) return false;
        return _parseExamples(w['examples']).isNotEmpty;
      }).toList();

      _allWordsPool = optionsPool;
      allWords = sentenceQuestions;

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

    _quizData = finalQuestions
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
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
      _revealedHints = [];
      _generateOptionsForCurrentQuestion(_allWordsPool);
      _quizStartTime = DateTime.now();
      _questionStartTime = DateTime.now();
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
    _cachedSelectionSignature = _selectionSignature;
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

      // If we somehow failed to parse a synonym, don't show a blank screen.
      if (correctSynonym.trim().isEmpty) {
        _currentOptions = [];
        return;
      }

      // Cache the chosen synonym so answer checking is stable
      currentQuestion['_correctSynonym'] = correctSynonym;

      // Gather distractor synonyms from ALL other words (not just one random
      // synonym per word). This makes the mode work even when only a few
      // words have synonyms.
      List<String> distractors = pool
          .where((w) => w['id'] != currentQuestion['id'])
          .expand((w) => _parseSynonyms(w['synonyms']))
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

    // Final safety net: never leave the UI with an empty options list
    // (it looks like a blank page). We'll keep it empty and show a message.
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
    } else if (currentMode == 'sentence_to_word') {
      return (currentQuestion['word'] ?? '').toString();
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

    _recordAnswerHistory(isCorrect);

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

    _recordAnswerHistory(isCorrect);

    // Play sound immediately
    _playSound(isCorrect);

    setState(() {
      _isAnswered = true;
      _selectedAnswer = answer;

      if (isCorrect) {
        _score++;
        _hintPoints++;
      }

      _answeredCount++;
    });
  }

  List<String> _parseSynonyms(dynamic rawValue) {
    final raw = (rawValue as String? ?? '').trim();
    if (raw.isEmpty) return const [];

    // Accept common separators: comma and new line.
    // (If you later want ';' or '|', add them here.)
    final parts = raw
        .split(RegExp(r'[\n,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return const [];
    return parts.toSet().toList();
  }

  List<String> _parseExamples(dynamic rawValue) {
    final raw = (rawValue as String? ?? '').trim();
    if (raw.isEmpty) return const [];

    final parts = raw
        .split(RegExp(r'[\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return const [];
    return parts;
  }

  String _maskWordInSentence(String sentence, String word) {
    final trimmedWord = word.trim();
    if (trimmedWord.isEmpty) return sentence;

    final pattern = RegExp(
      r'\b' + RegExp.escape(trimmedWord) + r'\b',
      caseSensitive: false,
    );

    if (!pattern.hasMatch(sentence)) return sentence;

    return sentence.replaceAllMapped(pattern, (match) {
      final int len = match.group(0)?.length ?? trimmedWord.length;
      return '_' * len;
    });
  }

  String _getSentencePrompt(Map<String, dynamic> item) {
    final cached = (item['_sentencePrompt'] as String? ?? '').trim();
    if (cached.isNotEmpty) return cached;

    final String word = (item['word'] ?? '').toString();
    final examples = _parseExamples(item['examples']);
    if (examples.isEmpty) return '';

    examples.shuffle();
    final int takeCount = min(3, examples.length);
    final List<String> selected = examples.take(takeCount).toList();

    String chosen = selected.first;
    for (final s in selected) {
      if (RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false)
          .hasMatch(s)) {
        chosen = s;
        break;
      }
    }

    final masked = _maskWordInSentence(chosen, word);
    item['_sentencePrompt'] = masked;
    return masked;
  }

  List<String> _getAllSynonyms(Map<String, dynamic> item) {
    return _parseSynonyms(item['synonyms']);
  }

  String _getRandomSynonym(Map<String, dynamic> item) {
    final parts = _parseSynonyms(item['synonyms']);
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
        _revealedHints = [];
        _questionStartTime = DateTime.now();
      });
    } else {
      // Finished all questions before timer expired
      _timer?.cancel();
      _showResultDialog();
    }
  }

  bool _isHistoryEligibleMode(String mode) {
    return mode == 'desc_to_word' ||
        mode == 'word_to_desc' ||
        mode == 'sentence_to_word';
  }

  int _getCurrentQuestionDurationSeconds() {
    if (_questionStartTime == null) return 0;
    final int seconds = DateTime.now()
        .difference(_questionStartTime!)
        .inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  Map<String, dynamic> _buildWordSnapshot(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'word': item['word'],
      'description': item['description'],
      'examples': item['examples'],
      'word_type': item['word_type'],
      'image_path': item['image_path'],
      'synonyms': item['synonyms'],
      'is_favorite': item['is_favorite'],
    };
  }

  void _recordAnswerHistory(bool isCorrect) {
    if (!_isHistoryEligibleMode(_quizMode)) return;

    final String currentMode = _questionModes.isNotEmpty
        ? _questionModes[_currentIndex]
        : _quizMode;

    if (!_isHistoryEligibleMode(currentMode)) return;

    if (_quizData.isEmpty) return;
    final currentQuestion = _quizData[_currentIndex];

    _historyItems.add({
      'wordId': currentQuestion['id'],
      'word': (currentQuestion['word'] ?? '').toString(),
      'isCorrect': isCorrect,
      'durationSeconds': _getCurrentQuestionDurationSeconds(),
      'wordData': _buildWordSnapshot(currentQuestion),
    });
  }

  int _getQuizElapsedSeconds() {
    if (_elapsedSeconds > 0) return _elapsedSeconds;
    if (_quizStartTime == null) return 0;
    final int seconds = DateTime.now().difference(_quizStartTime!).inSeconds;
    if (_isCountdownTimerEnabled && _totalDurationSeconds > 0) {
      return seconds.clamp(0, _totalDurationSeconds);
    }
    return seconds < 0 ? 0 : seconds;
  }

  Future<void> _saveQuizHistoryIfEligible() async {
    if (_historySavedForCurrentQuiz) return;
    if (!_isHistoryEligibleMode(_quizMode)) return;
    if (_quizData.isEmpty) return;
    if (_historyItems.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString('quiz_history') ?? '[]';
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    final List<Map<String, dynamic>> history = decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final int nextNumber = (prefs.getInt('quiz_history_next_number') ?? 1);

    final Map<String, dynamic> historyItem = {
      'quizNumber': nextNumber,
      'date': DateTime.now().toIso8601String(),
      'quizMode': _quizMode,
      'durationSeconds': _getQuizElapsedSeconds(),
      'totalItems': _quizData.length,
      'items': List<Map<String, dynamic>>.from(_historyItems),
    };

    history.add(historyItem);

    await prefs.setString('quiz_history', jsonEncode(history));
    await prefs.setInt('quiz_history_next_number', nextNumber + 1);
    _historySavedForCurrentQuiz = true;
    _lastSavedHistoryItem = historyItem;
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
    final List<String> synonyms = _getAllSynonyms(currentQuestion);
    final List<String> unusedHints = synonyms
        .where((syn) => !_revealedHints.contains(syn))
        .toList(growable: false);

    if (synonyms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No synonym available for this word to use as a hint."),
        ),
      );
      return;
    }

    if (unusedHints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("All hints for this word have been revealed."),
        ),
      );
      return;
    }

    unusedHints.shuffle();
    final String hint = unusedHints.first;

    setState(() {
      _revealedHints = [..._revealedHints, hint];
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

  Future<void> _speakQuestionText(String text) async {
    if (text.trim().isEmpty) return;

    if (_currentVoice != null) {
      await flutterTts.setVoice(_currentVoice!);
    }

    await flutterTts.speak(text);
  }

  void _showResultDialog() {
    _saveQuizHistoryIfEligible();
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
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isHistoryEligibleMode(_quizMode))
                OutlinedButton(
                  onPressed: () async {
                    await _saveQuizHistoryIfEligible();
                    final item = _lastSavedHistoryItem;
                    if (item == null || !context.mounted) return;
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            QuizHistoryDetailPage(historyItem: item),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    ),
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'VIEW HISTORY',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              if (_isHistoryEligibleMode(_quizMode)) const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _generateQuizFresh();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  minimumSize: const Size.fromHeight(50),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'QUIZ AGAIN',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTimeUpDialog() {
    _saveQuizHistoryIfEligible();
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
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isHistoryEligibleMode(_quizMode))
                OutlinedButton(
                  onPressed: () async {
                    await _saveQuizHistoryIfEligible();
                    final item = _lastSavedHistoryItem;
                    if (item == null || !context.mounted) return;
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            QuizHistoryDetailPage(historyItem: item),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    ),
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'VIEW HISTORY',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              if (_isHistoryEligibleMode(_quizMode)) const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _generateQuizFresh();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  minimumSize: const Size.fromHeight(50),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'QUIZ AGAIN',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
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
            icon: const Icon(Icons.history),
            tooltip: 'Quiz history',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const QuizHistoryPage(),
                ),
              );
            },
          ),
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
      String message;
      if (_emptyReason == 'no_words_selected') {
        message =
            "No words are selected for quizzes. Please go to Settings → Sort Data Preferences → Sort Words Data and choose some words, or turn on 'Use all words'.";
      } else if (_emptyReason == 'no_idioms_selected') {
        message =
            "No idioms are selected for quizzes. Please go to Settings → Sort Data Preferences → Sort Idioms Data and choose some idioms, or turn on 'Use all idioms'.";
      } else {
        message = _quizMode == 'pic_to_word'
            ? "Add images to your vocabulary words to play this mode."
            : (_quizMode == 'idiom_desc_to_idiom' ||
                  _quizMode == 'idiom_to_desc' ||
                  _quizMode == 'idiom_mixed')
            ? "You need at least 4 idioms in your idiom list to start a quiz."
            : (_quizMode == 'word_to_synonym' || _quizMode == 'synonym_to_word')
            ? "You need at least 1 word with synonyms in your vocabulary list to start this quiz."
        : _quizMode == 'sentence_to_word'
        ? "You need at least 1 word with example sentences in your vocabulary list to start this quiz."
            : "You need at least 4 words in your vocabulary list to start a quiz.";
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Text(message, textAlign: TextAlign.center)],
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
    final List<String> allSynonyms = _getAllSynonyms(currentQuestion);
    final bool canUseHint =
        !_isAnswered && _hintPoints > 0 && allSynonyms.isNotEmpty;

    String questionText;
    if (currentMode == 'word_to_desc') {
      questionText = (currentQuestion['word'] ?? 'No Word').toString();
    } else if (currentMode == 'idiom_to_desc') {
      questionText = (currentQuestion['idiom'] ?? 'No Idiom').toString();
    } else if (currentMode == 'word_to_synonym') {
      // In this mode the prompt should be the word itself.
      questionText = (currentQuestion['word'] ?? 'No Word').toString();
    } else if (currentMode == 'sentence_to_word') {
      final String prompt = _getSentencePrompt(currentQuestion);
      questionText = prompt.isNotEmpty
          ? prompt
          : 'No example sentence available for this word.';
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
                          const SizedBox(height: 12),
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
                                    allSynonyms.isNotEmpty
                                        ? 'Synonyms: ${allSynonyms.join(', ')}'
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
                    Row(
                      children: [
                        Text('Hint points: $_hintPoints'),
                        const Spacer(),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.lightbulb_outline),
                          label: const Text('GET HINT'),
                          onPressed: canUseHint ? _usePictureHint : null,
                        ),
                      ],
                    ),
                    if (_revealedHints.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Hints: ${_revealedHints.join(', ')}',
                          style: const TextStyle(color: Colors.indigo),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Speak question',
                          icon: const Icon(
                            Icons.volume_up,
                            color: Colors.indigo,
                          ),
                          onPressed: () => _speakQuestionText(questionText),
                        ),
                      ],
                    ),
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
                              : currentMode == 'sentence_to_word'
                              ? 'WHICH WORD COMPLETES THIS SENTENCE?'
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
                          const SizedBox(height: 8),
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

                    if (_currentOptions.isEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          border: Border.all(color: Colors.amber.shade200),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No options could be generated for this question.',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tip: make sure the Synonyms field is like: Word 1, Word 2, Word 3',
                              style: TextStyle(color: Colors.black87),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _generateOptionsForCurrentQuestion(
                                    _allWordsPool,
                                  );
                                });
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('RELOAD OPTIONS'),
                            ),
                          ],
                        ),
                      ),
                    ] else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _currentOptions.length,
                        separatorBuilder: (ctx, i) =>
                            const SizedBox(height: 12),
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
              _generateQuizFresh();
            },
            child: const Text('Restart', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
