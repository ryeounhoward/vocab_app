import 'package:flutter/material.dart';
import 'package:vocab_app/pages/favorite_page.dart';
import 'package:vocab_app/pages/manage_data_page.dart';
import 'package:vocab_app/pages/backup_restore_page.dart';
import 'package:vocab_app/pages/manage_idioms_page.dart';
import 'package:vocab_app/pages/vocabulary_test_settings_page.dart';
import 'package:vocab_app/pages/word_of_day_page.dart';
import 'voice_selection_page.dart';
import 'practice_preferences_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), centerTitle: true),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.star, color: Colors.orange),
            title: const Text("Favorites"),
            subtitle: const Text("View your starred words"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FavoritesPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.indigo),
            title: const Text("Manage Vocabulary"),
            subtitle: const Text("Add, edit, or delete your words"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ManageDataPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.indigo),
            title: const Text("Manage Idioms"),
            subtitle: const Text("Add, edit, or delete your idioms"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ManageIdiomsPage(),
                ),
              );
            },
          ),

          ListTile(
            leading: const Icon(
              Icons.notification_important,
              color: Colors.indigo,
            ),
            title: const Text("Word of the Day"),
            subtitle: const Text("Set notification reminders for words"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const WordOfDayPage()),
              );
            },
          ),

          // --- UPDATED QUIZ PREFERENCES TILE ---
          ListTile(
            leading: const Icon(
              Icons.quiz, // Changed icon to quiz to make it clearer
              color: Colors.indigo,
            ),
            title: const Text("Quiz Preferences"),
            subtitle: const Text("Set your quiz preferences"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              // 1. Wait for result from QuizSettingsPage
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const QuizSettingsPage(),
                ),
              );

              // 2. If result is true, show SnackBar here
              if (result == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Quiz Preferences Saved!"),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.style, color: Colors.indigo),
            title: const Text("Practice Preferences"),
            subtitle: const Text("Set your practice session preferences"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PracticePreferencesPage(),
                ),
              );
            },
          ),

          // -------------------------------------
          ListTile(
            leading: const Icon(Icons.record_voice_over, color: Colors.indigo),
            title: const Text("Change Voice"),
            subtitle: const Text("Select your preferred text-to-speech voice"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const VoiceSelectionPage(),
                ),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.backup, color: Colors.teal),
            title: const Text("Backup & Restore"),
            subtitle: const Text("Export or Import your data via JSON"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BackupRestorePage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
