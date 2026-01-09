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
  bool _isExactHour = false; // <--- NEW SWITCH VARIABLE
  int _intervalHours = 1;
  int _wordCount = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    NotificationService.requestPermissions();
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isActive = prefs.getBool('remind_active') ?? false;
      _isRandom = prefs.getBool('remind_random') ?? true;
      _isExactHour = prefs.getBool('remind_exact') ?? false; // Load setting
      _intervalHours = prefs.getInt('remind_interval') ?? 1;
      _wordCount = prefs.getInt('remind_word_count') ?? 1;
    });
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remind_active', _isActive);
    await prefs.setBool('remind_random', _isRandom);
    await prefs.setBool('remind_exact', _isExactHour); // Save setting
    await prefs.setInt('remind_interval', _intervalHours);
    await prefs.setInt('remind_word_count', _wordCount);

    if (_isActive) {
      // --- LOGIC FOR TOP OF THE HOUR ---
      Duration initialDelay = Duration.zero;

      if (_isExactHour) {
        final now = DateTime.now();
        // Calculate the next top of the hour (e.g., if 10:20, target is 11:00)
        final nextHour = DateTime(
          now.year,
          now.month,
          now.day,
          now.hour + 1,
          0,
          0,
        );

        // Calculate difference
        initialDelay = nextHour.difference(now);

        // Safety check: ensure delay is positive
        if (initialDelay.isNegative) {
          initialDelay = Duration.zero;
        }
      }
      // ---------------------------------

      Workmanager().registerPeriodicTask(
        "word_reminder_task",
        "word_reminder_periodic",
        frequency: Duration(hours: _intervalHours),
        // This ensures the first run happens at the top of the next hour
        initialDelay: initialDelay,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        inputData: <String, dynamic>{
          'wordCount': _wordCount,
          'isRandom': _isRandom,
        },
      );
    } else {
      Workmanager().cancelByUniqueName("word_reminder_task");
    }

    if (mounted) {
      String message = "Settings Saved!";
      if (_isActive && _isExactHour) {
        message += " First alert at next hour.";
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      Navigator.pop(context);
    }
  }

  void _testNotification() async {
    await NotificationService.showWordNotification(count: _wordCount);
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
          // 1. ENABLE SWITCH
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

          // 2. TIMELY SWITCH (NEW)
          ListTile(
            title: const Text("Align to Exact Hour"),
            subtitle: const Text("Notify at every top of the hour"),
            trailing: Switch(
              value: _isExactHour,
              activeThumbColor: Colors.indigo,
              onChanged: (val) => setState(() => _isExactHour = val),
            ),
          ),
          const Divider(),

          // 3. ORDER MODE
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

          // 4. WORD COUNT
          const Divider(),
          const ListTile(
            title: Text("Words per Notification"),
            contentPadding: EdgeInsets.symmetric(horizontal: 16),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButton<int>(
              isExpanded: true,
              value: _wordCount,
              items: List.generate(5, (index) => index + 1).map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text("$value ${value == 1 ? "Word" : "Words"}"),
                );
              }).toList(),
              onChanged: (val) => setState(() => _wordCount = val!),
            ),
          ),

          // 5. INTERVAL
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
          const SizedBox(height: 15),
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
