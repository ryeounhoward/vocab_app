import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../database/db_helper.dart';

class QuizSettingsPage extends StatefulWidget {
  const QuizSettingsPage({super.key});

  @override
  State<QuizSettingsPage> createState() => _QuizSettingsPageState();
}

class _QuizSettingsPageState extends State<QuizSettingsPage> {
  final TextEditingController _countController = TextEditingController();
  final DBHelper _dbHelper = DBHelper();

  // State variables
  int _currentLimit = 10;
  bool _useAllWords = false;
  int _maxAvailableItems = 0;
  bool _enableSound = true;
  bool _enableResultSound = true;
  bool _enableCountdownTimer = false;
  bool _enableDurationTimer = false;
  String _quizMode = 'desc_to_word'; // Default mode

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final String quizMode = prefs.getString('quiz_mode') ?? 'desc_to_word';
    final int maxItems = await _computeMaxAvailableItems(prefs, quizMode);

    setState(() {
      _currentLimit = prefs.getInt('quiz_total_items') ?? 10;
      _useAllWords = prefs.getBool('quiz_use_all_items') ?? false;
      _enableSound = prefs.getBool('quiz_sound_enabled') ?? true;
      _enableResultSound = prefs.getBool('quiz_result_sound_enabled') ?? true;
      bool countdown = prefs.getBool('quiz_timer_enabled') ?? false;
      bool duration =
          prefs.getBool('quiz_duration_timer_enabled') ?? !countdown;

      if (countdown && duration) {
        duration = false; // Prefer countdown if both somehow true
      }

      _enableCountdownTimer = countdown;
      _enableDurationTimer = duration;
      _quizMode = quizMode;
      _maxAvailableItems = maxItems;
      _countController.text = _currentLimit.toString();
    });
  }

  Future<void> _saveSettings() async {
    int newLimit = _currentLimit;

    if (!_useAllWords) {
      if (_countController.text.isEmpty) return;

      newLimit = int.tryParse(_countController.text) ?? 10;

      // --- VALIDATION: minimum 1, upper bound handled by quiz page ---
      if (newLimit < 1) newLimit = 1;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('quiz_total_items', newLimit);
    await prefs.setBool('quiz_use_all_items', _useAllWords);
    await prefs.setBool('quiz_sound_enabled', _enableSound);
    await prefs.setBool('quiz_result_sound_enabled', _enableResultSound);
    await prefs.setBool('quiz_timer_enabled', _enableCountdownTimer);
    await prefs.setBool('quiz_duration_timer_enabled', _enableDurationTimer);
    await prefs.setString('quiz_mode', _quizMode); // Save the mode

    setState(() {
      _currentLimit = newLimit;
      _countController.text = newLimit.toString();
    });

    if (mounted) {
      // Pass 'true' back to the previous screen to indicate success
      Navigator.pop(context, true);
    }
  }

  Future<int> _computeMaxAvailableItems(
    SharedPreferences prefs,
    String quizMode,
  ) async {
    final bool isIdiomQuiz =
        quizMode == 'idiom_desc_to_idiom' ||
        quizMode == 'idiom_to_desc' ||
        quizMode == 'idiom_mixed';

    if (isIdiomQuiz) {
      final bool useAllIdioms = prefs.getBool('quiz_use_all_idioms') ?? true;
      final List<Map<String, dynamic>> allIdioms = await _dbHelper.queryAll(
        DBHelper.tableIdioms,
      );

      if (useAllIdioms) {
        return allIdioms.length;
      }

      final List<String> selectedIdsStr =
          prefs.getStringList('quiz_selected_idiom_ids') ?? <String>[];
      final Set<int> selectedIds = selectedIdsStr
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();

      if (selectedIds.isEmpty) return 0;

      return allIdioms.where((item) {
        final dynamic id = item['id'];
        if (id is int) return selectedIds.contains(id);
        if (id is String) {
          final parsed = int.tryParse(id);
          return parsed != null && selectedIds.contains(parsed);
        }
        return false;
      }).length;
    } else {
      final bool useAllWords = prefs.getBool('quiz_use_all_words') ?? true;
      final List<Map<String, dynamic>> allVocab = await _dbHelper.queryAll(
        DBHelper.tableVocab,
      );

      if (useAllWords) {
        return allVocab.length;
      }

      final List<String> selectedIdsStr =
          prefs.getStringList('quiz_selected_word_ids') ?? <String>[];
      final Set<int> selectedIds = selectedIdsStr
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();

      if (selectedIds.isEmpty) return 0;

      return allVocab.where((item) {
        final dynamic id = item['id'];
        if (id is int) return selectedIds.contains(id);
        if (id is String) {
          final parsed = int.tryParse(id);
          return parsed != null && selectedIds.contains(parsed);
        }
        return false;
      }).length;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quiz Preferences"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          // --- SECTION 1: SOUND ---
          const Text(
            "Audio Settings",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Enable Sound Effects"),
            subtitle: const Text("Play sounds for correct/wrong answers"),
            activeThumbColor: Colors.indigo,
            value: _enableSound,
            onChanged: (val) {
              setState(() => _enableSound = val);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Enable Game Result Sound"),
            subtitle: const Text("Play a sound at the end of each quiz"),
            activeThumbColor: Colors.indigo,
            value: _enableResultSound,
            onChanged: (val) {
              setState(() => _enableResultSound = val);
            },
          ),
          const Divider(height: 30),

          // --- SECTION 2: TIMER ---
          const Text(
            "Timer",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Countdown timer"),
            subtitle: const Text(
              "60 seconds per question. Total time = items × 60.",
            ),
            activeThumbColor: Colors.indigo,
            value: _enableCountdownTimer,
            onChanged: (val) {
              setState(() {
                _enableCountdownTimer = val;
                if (val) _enableDurationTimer = false;
              });
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Duration timer"),
            subtitle: const Text("Count how long you take to finish the quiz."),
            activeThumbColor: Colors.indigo,
            value: _enableDurationTimer,
            onChanged: (val) {
              setState(() {
                _enableDurationTimer = val;
                if (val) _enableCountdownTimer = false;
              });
            },
          ),
          const Divider(height: 30),

          // --- SECTION 3: QUIZ MODE ---
          const Text(
            "Quiz Mode",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          DropdownMenu<String>(
            width: MediaQuery.of(context).size.width - 48,
            menuHeight: 250,
            initialSelection: _quizMode,
            label: const Text("Quiz Mode"),
            onSelected: (String? newValue) async {
              if (newValue == null) return;

              setState(() => _quizMode = newValue);

              final prefs = await SharedPreferences.getInstance();
              final int maxItems = await _computeMaxAvailableItems(
                prefs,
                newValue,
              );

              if (!mounted) return;
              setState(() {
                _maxAvailableItems = maxItems;
              });
            },
            dropdownMenuEntries: const [
              DropdownMenuEntry(
                value: 'desc_to_word',
                label: 'Definition to Word (Default)',
              ),
              DropdownMenuEntry(
                value: 'word_to_desc',
                label: 'Word to Definition',
              ),
              DropdownMenuEntry(
                value: 'word_to_synonym',
                label: 'Word to Synonym',
              ),
              DropdownMenuEntry(
                value: 'synonym_to_word',
                label: 'Synonym to Word',
              ),
              DropdownMenuEntry(value: 'pic_to_word', label: 'Picture to Word'),
              DropdownMenuEntry(
                value: 'idiom_desc_to_idiom',
                label: 'Definition to Idiom',
              ),
              DropdownMenuEntry(
                value: 'idiom_to_desc',
                label: 'Idiom to Definition',
              ),
              DropdownMenuEntry(
                value: 'mixed',
                label: 'Word & Definition (Mixed)',
              ),
              DropdownMenuEntry(
                value: 'mixed_with_pic',
                label: 'Picture, Word & Definition (Mixed)',
              ),
              DropdownMenuEntry(
                value: 'idiom_mixed',
                label: 'Idiom & Meaning (Mixed)',
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            "Choose if you want to guess the word, a synonym, the definition, or from a picture.",
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),

          const Divider(height: 30),

          // --- SECTION 4: COUNT ---
          const Text(
            "Question Count",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "How many questions per quiz? Maximum available for this quiz: $_maxAvailableItems",
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 15),

          TextField(
            controller: _countController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            enabled: !_useAllWords,
            decoration: InputDecoration(
              labelText: "Number of Items",
              hintText: "e.g., 10",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Use all available words/idioms"),
            subtitle: const Text(
              "Ignore the number above and use every stored item.",
            ),
            activeThumbColor: Colors.indigo,
            value: _useAllWords,
            onChanged: (val) {
              setState(() => _useAllWords = val);
            },
          ),

          const SizedBox(height: 20),

          // --- SAVE BUTTON ---
          SizedBox(
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _saveSettings,
              child: const Text(
                "SAVE SETTINGS",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
