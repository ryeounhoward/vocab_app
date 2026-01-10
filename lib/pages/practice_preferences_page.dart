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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice Preferences'),
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
            activeColor: Colors.indigo,
            value: _enableSwooshSound,
            onChanged: (val) => _updateSwooshSound(val),
          ),
        ],
      ),
    );
  }
}
