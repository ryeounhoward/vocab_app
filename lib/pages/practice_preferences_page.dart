import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PracticePreferencesPage extends StatefulWidget {
  const PracticePreferencesPage({super.key});

  @override
  State<PracticePreferencesPage> createState() =>
      _PracticePreferencesPageState();
}

class _PracticePreferencesPageState extends State<PracticePreferencesPage> {
  bool _enableSwooshSound = true;
  bool _enableFavoriteSound = true;
  String _practiceMode = 'vocab'; // 'vocab' or 'idiom'
  String _practiceOrder = 'shuffle'; // 'shuffle', 'az', 'za'

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enableSwooshSound =
          prefs.getBool('practice_swoosh_sound_enabled') ?? true;
      _enableFavoriteSound = prefs.getBool('favorite_sound_enabled') ?? true;
      _practiceMode = prefs.getString('practice_mode') ?? 'vocab';
      _practiceOrder = prefs.getString('practice_order') ?? 'shuffle';
    });
  }

  Future<void> _updateSwooshSound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('practice_swoosh_sound_enabled', value);
    if (mounted) {
      setState(() {
        _enableSwooshSound = value;
      });
    }
  }

  Future<void> _updateFavoriteSound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('favorite_sound_enabled', value);
    if (mounted) {
      setState(() {
        _enableFavoriteSound = value;
      });
    }
  }

  Future<void> _updatePracticeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('practice_mode', mode);
    if (mounted) {
      setState(() {
        _practiceMode = mode;
      });
    }
  }

  Future<void> _updatePracticeOrder(String order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('practice_order', order);
    if (mounted) {
      setState(() {
        _practiceOrder = order;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!mounted) return;
    // Return true so the caller (SettingsPage) can show a SnackBar.
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & Practice Preferences'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            'Audio Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Swoosh Sound'),
            subtitle: const Text(
              'Play a swoosh sound when revealing the answer card',
            ),
            activeThumbColor: Colors.indigo,
            value: _enableSwooshSound,
            onChanged: (val) => _updateSwooshSound(val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Favorite Star Sound'),
            subtitle: const Text('Play a sound when marking items as favorite'),
            activeThumbColor: Colors.indigo,
            value: _enableFavoriteSound,
            onChanged: (val) => _updateFavoriteSound(val),
          ),
          const Divider(height: 30),
          const SizedBox(height: 10),
          const Text(
            'Practice Content',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'Choose the content you want in practice sessions.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          // Practice mode (words vs idioms)
          DropdownMenu<String>(
            width: MediaQuery.of(context).size.width - 48,
            menuHeight: 250,
            initialSelection: _practiceMode,
            label: const Text('Practice content'),
            onSelected: (String? value) {
              if (value != null) {
                _updatePracticeMode(value);
              }
            },
            dropdownMenuEntries: const [
              DropdownMenuEntry<String>(value: 'vocab', label: 'Words'),
              DropdownMenuEntry<String>(value: 'idiom', label: 'Idioms'),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Order',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'How items are ordered in Review.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          DropdownMenu<String>(
            width: MediaQuery.of(context).size.width - 48,
            menuHeight: 250,
            initialSelection: _practiceOrder,
            label: const Text('Order'),
            onSelected: (String? value) {
              if (value != null) {
                _updatePracticeOrder(value);
              }
            },
            dropdownMenuEntries: const [
              DropdownMenuEntry<String>(value: 'shuffle', label: 'Shuffle'),
              DropdownMenuEntry<String>(
                value: 'az',
                label: 'Ascending (A - Z)',
              ),
              DropdownMenuEntry<String>(
                value: 'za',
                label: 'Descending (Z - A)',
              ),
            ],
          ),
          const SizedBox(height: 24),
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
                'SAVE SETTINGS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
