import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../services/notification_service.dart';

class WordOfDayPage extends StatefulWidget {
  const WordOfDayPage({super.key});

  @override
  State<WordOfDayPage> createState() => _WordOfDayPageState();
}

class _WordOfDayPageState extends State<WordOfDayPage> {
  bool _isActive = false;
  bool _isRandom = true;
  int _intervalHours = 2;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // 1. REQUEST PERMISSION ON OPEN
    NotificationService.requestPermissions();
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isActive = prefs.getBool('remind_active') ?? false;
      _isRandom = prefs.getBool('remind_random') ?? true;
      _intervalHours = prefs.getInt('remind_interval') ?? 2;
    });
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remind_active', _isActive);
    await prefs.setBool('remind_random', _isRandom);
    await prefs.setInt('remind_interval', _intervalHours);

    if (_isActive) {
      Workmanager().registerPeriodicTask(
        "word_reminder_task",
        "word_reminder_periodic",
        frequency: Duration(hours: _intervalHours),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else {
      Workmanager().cancelByUniqueName("word_reminder_task");
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Settings Saved!")));
      Navigator.pop(context);
    }
  }

  void _testNotification() async {
    // 2. CALL THE NEW TEST FUNCTION
    await NotificationService.showTestNotification();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sending test notification...")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Word of the Day"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text("Enable Reminders"),
            subtitle: const Text("Get notifications for vocabulary"),
            trailing: Switch(
              value: _isActive,
              activeThumbColor: Colors.indigo,
              onChanged: (val) => setState(() => _isActive = val),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text("Order Mode"),
            subtitle: Text(
              _isRandom ? "Random Words" : "Sequential (List Order)",
            ),
            trailing: Switch(
              value: _isRandom,
              activeThumbColor: Colors.indigo,
              onChanged: (val) => setState(() => _isRandom = val),
            ),
          ),
          const Divider(),
          const ListTile(
            title: Text("Remind me every:"),
            contentPadding: EdgeInsets.symmetric(horizontal: 16),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButton<int>(
              isExpanded: true,
              value: _intervalHours,
              items: List.generate(12, (index) => index + 1).map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text("$value ${value == 1 ? "Hour" : "Hours"}"),
                );
              }).toList(),
              onChanged: (val) => setState(() => _intervalHours = val!),
            ),
          ),
          const SizedBox(height: 40),
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
          // const SizedBox(height: 15),
          // SizedBox(
          //   height: 55,
          //   child: OutlinedButton(
          //     style: OutlinedButton.styleFrom(
          //       side: const BorderSide(color: Colors.indigo),
          //       foregroundColor: Colors.indigo,
          //       shape: RoundedRectangleBorder(
          //         borderRadius: BorderRadius.circular(8),
          //       ),
          //     ),
          //     onPressed: _testNotification,
          //     child: const Text(
          //       "TEST NOTIFICATION NOW",
          //       style: TextStyle(fontWeight: FontWeight.bold),
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }
}
