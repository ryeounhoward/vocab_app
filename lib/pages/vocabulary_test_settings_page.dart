import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class QuizSettingsPage extends StatefulWidget {
  const QuizSettingsPage({super.key});

  @override
  State<QuizSettingsPage> createState() => _QuizSettingsPageState();
}

class _QuizSettingsPageState extends State<QuizSettingsPage> {
  final TextEditingController _countController = TextEditingController();

  // State variables
  int _currentLimit = 10;
  bool _enableSound = true;
  bool _enableResultSound = true;
  String _quizMode = 'desc_to_word'; // Default mode

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLimit = prefs.getInt('quiz_total_items') ?? 10;
      _enableSound = prefs.getBool('quiz_sound_enabled') ?? true;
      _enableResultSound = prefs.getBool('quiz_result_sound_enabled') ?? true;
      // Load quiz mode (defaulting to description -> word if not set)
      _quizMode = prefs.getString('quiz_mode') ?? 'desc_to_word';
      _countController.text = _currentLimit.toString();
    });
  }

  Future<void> _saveSettings() async {
    if (_countController.text.isEmpty) return;

    int newLimit = int.tryParse(_countController.text) ?? 10;

    // --- VALIDATION: 10 to 100 ---
    if (newLimit < 10) newLimit = 10;
    if (newLimit > 100) newLimit = 100;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('quiz_total_items', newLimit);
    await prefs.setBool('quiz_sound_enabled', _enableSound);
    await prefs.setBool('quiz_result_sound_enabled', _enableResultSound);
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
            activeColor: Colors.indigo,
            value: _enableSound,
            onChanged: (val) {
              setState(() => _enableSound = val);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Enable Game Result Sound"),
            subtitle: const Text("Play a sound at the end of each quiz"),
            activeColor: Colors.indigo,
            value: _enableResultSound,
            onChanged: (val) {
              setState(() => _enableResultSound = val);
            },
          ),
          const Divider(height: 30),

          // --- SECTION 2: QUIZ MODE ---
          const Text(
            "Quiz Mode",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _quizMode,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'desc_to_word',
                    child: Text("Definition to Word (Default)"),
                  ),
                  DropdownMenuItem(
                    value: 'word_to_desc',
                    child: Text("Word to Definition"),
                  ),
                  DropdownMenuItem(
                    value: 'pic_to_word',
                    child: Text("Picture to Word"),
                  ),
                  DropdownMenuItem(
                    value: 'mixed',
                    child: Text("Word & Definition (Mixed)"),
                  ),
                  DropdownMenuItem(
                    value: 'mixed_with_pic',
                    child: Text("Picture, Word & Definition (Mixed)"),
                  ),
                ],
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _quizMode = newValue);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            "Choose if you want to guess the word, the definition, or from a picture.",
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),

          const Divider(height: 30),

          // --- SECTION 3: COUNT ---
          const Text(
            "Question Count",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "How many questions per quiz? (10 - 100)",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 15),

          TextField(
            controller: _countController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: "Number of Items",
              hintText: "e.g., 10",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 40),

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
        ],
      ),
    );
  }
}
