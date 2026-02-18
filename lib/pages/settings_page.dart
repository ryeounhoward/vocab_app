import 'package:flutter/material.dart';
import 'favorite_page.dart';
import 'manage_data_page.dart';
import 'backup_restore_page.dart';
import 'about_page.dart';
import 'manage_idioms_page.dart';
import 'vocabulary_test_settings_page.dart';
import 'word_of_day_page.dart';
import 'quiz_history_page.dart';
import 'api_settings_page.dart';
import 'voice_selection_page.dart';
import 'practice_preferences_page.dart';
import 'sort_data_page.dart';
import 'profile_page.dart';
import 'manage_cheat_sheet_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // This variable tracks if any settings were changed that require the Quiz/Review page to reload
  bool _needsRefresh = false;

  /// Helper method to navigate and track if changes were made
  Future<void> _navigateTo(BuildContext context, Widget page) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );

    // If the sub-page returned true, we need to signal the Quiz/Review page to reload
    if (result == true) {
      setState(() {
        _needsRefresh = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Handle pop manually
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Return the _needsRefresh value back to the previous screen (Menu/Home)
        Navigator.pop(context, _needsRefresh);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Settings"),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _needsRefresh),
          ),
        ),
        body: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.person, color: Colors.indigo),
              title: const Text("Profile"),
              subtitle: const Text("Google login and profile info"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ProfilePage()),
            ),
            ListTile(
              leading: const Icon(Icons.star, color: Colors.orange),
              title: const Text("Favorites"),
              subtitle: const Text("View your starred words"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const FavoritesPage()),
            ),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.indigo),
              title: const Text("History"),
              subtitle: const Text("Quickly review your past activities"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const QuizHistoryPage()),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.indigo),
              title: const Text("Manage Vocabulary"),
              subtitle: const Text("Add, edit, or delete your words"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ManageDataPage()),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.indigo),
              title: const Text("Manage Idioms"),
              subtitle: const Text("Add, edit, or delete your idioms"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ManageIdiomsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check, color: Colors.indigo),
              title: const Text("Manage Cheat Sheet"),
              subtitle: const Text("Add, edit, or delete PDF and HTML files"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ManageCheatSheetPage()),
            ),

            // --- FIXED: Removed 'const' from SortDataPage() ---
            ListTile(
              leading: const Icon(Icons.sort, color: Colors.indigo),
              title: const Text("Manage Sort Data"),
              subtitle: const Text(
                "Choose data to practice, review, and quiz based on your preferences",
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, SortDataPage()),
            ),
            ListTile(
              leading: const Icon(
                Icons.notification_important,
                color: Colors.indigo,
              ),
              title: const Text("Word of the Day"),
              subtitle: const Text("Set notification reminders for words"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const WordOfDayPage()),
            ),

            ListTile(
              leading: const Icon(Icons.quiz, color: Colors.indigo),
              title: const Text("Quiz Preferences"),
              subtitle: const Text("Set your quiz preferences"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const QuizSettingsPage(),
                  ),
                );
                if (result == true) {
                  setState(() => _needsRefresh = true);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Quiz Preferences Saved!")),
                    );
                  }
                }
              },
            ),

            ListTile(
              leading: const Icon(Icons.style, color: Colors.indigo),
              title: const Text("Review & Practice Preferences"),
              subtitle: const Text("Set your review and practice preferences"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PracticePreferencesPage(),
                  ),
                );
                if (result == true) {
                  setState(() => _needsRefresh = true);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Practice Preferences Saved!"),
                      ),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.record_voice_over,
                color: Colors.indigo,
              ),
              title: const Text("Change Voice"),
              subtitle: const Text(
                "Select your preferred text-to-speech voice",
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const VoiceSelectionPage()),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Colors.indigo),
              title: const Text("APIs"),
              subtitle: const Text("Add your Gemini API key & model"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ApiSettingsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.backup, color: Colors.teal),
              title: const Text("Backup & Restore"),
              subtitle: const Text("Export or Import your data via JSON"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const BackupRestorePage()),
            ),
            ListTile(
              leading: const Icon(Icons.info, color: Colors.teal),
              title: const Text("About"),
              subtitle: const Text("App version, developer info, and more"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const AboutPage()),
            ),
          ],
        ),
      ),
    );
  }
}
