import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
import 'exam_countdown_page.dart';
import 'google_drive_Service.dart';
import '../database/db_helper.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // This variable tracks if any settings were changed that require the Quiz/Review page to reload
  bool _needsRefresh = false;
  final GoogleDriveService _googleDriveService = GoogleDriveService();
  final DBHelper _dbHelper = DBHelper();
  StreamSubscription<GoogleSignInAccount?>? _accountSub;
  GoogleSignInAccount? _account;
  int _unreadNotifications = 0;

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
    await _loadNotificationBadge();
  }

  @override
  void initState() {
    super.initState();
    _account = _googleDriveService.currentUser;
    _accountSub = _googleDriveService.onCurrentUserChanged.listen((account) {
      if (!mounted) return;
      setState(() {
        _account = account;
      });
    });
    _loadNotificationBadge();
  }

  @override
  void dispose() {
    _accountSub?.cancel();
    super.dispose();
  }

  String _displayName() {
    final name = _account?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = _account?.email.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'Profile';
  }

  Widget _buildProfileLeading() {
    final photoUrl = _account?.photoUrl;
    final size = 36.0;
    final fallback = const Icon(Icons.person, color: Colors.grey, size: 22);
    if (_account == null || photoUrl == null || photoUrl.trim().isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.grey.shade200,
        child: fallback,
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.grey.shade200,
        child: ClipOval(
          child: Image.network(
            photoUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            },
            errorBuilder: (context, error, stackTrace) => fallback,
          ),
        ),
      ),
    );
  }

  Future<void> _loadNotificationBadge() async {
    final count = await _dbHelper.getUnreadNotificationCount();
    if (!mounted) return;
    setState(() => _unreadNotifications = count);
  }

  Widget _buildProfileTrailing() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_unreadNotifications > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            height: 18,
            constraints: const BoxConstraints(minWidth: 18),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                _unreadNotifications > 99
                    ? '99+'
                    : _unreadNotifications.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (_unreadNotifications > 0) const SizedBox(width: 8),
        const Icon(Icons.arrow_forward_ios, size: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const double leadingWidth = 40;
    Widget wrapLeading(Widget child) {
      return SizedBox(
        width: leadingWidth,
        child: Center(child: child),
      );
    }

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
              leading: wrapLeading(_buildProfileLeading()),
              minLeadingWidth: leadingWidth,
              title: Text(_displayName()),
              subtitle: const Text("Profile information and notifications"),
              trailing: _buildProfileTrailing(),
              onTap: () => _navigateTo(context, const ProfilePage()),
            ),
            ListTile(
              leading: wrapLeading(
                const Icon(Icons.star, color: Colors.orange),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("Favorites"),
              subtitle: const Text("View your starred words"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const FavoritesPage()),
            ),
            ListTile(
              leading: wrapLeading(
                const Icon(Icons.history, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("History"),
              subtitle: const Text("Quickly review your past activities"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const QuizHistoryPage()),
            ),

            ListTile(
              leading: wrapLeading(
                const Icon(Icons.edit, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("Manage Vocabulary"),
              subtitle: const Text("Add, edit, or delete your words"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ManageDataPage()),
            ),
            ListTile(
              leading: wrapLeading(
                const Icon(Icons.edit, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("Manage Idioms"),
              subtitle: const Text("Add, edit, or delete your idioms"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ManageIdiomsPage()),
            ),
            ListTile(
              leading: wrapLeading(
                const Icon(Icons.fact_check, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("Manage Cheat Sheet"),
              subtitle: const Text("Add, edit, or delete PDF and HTML files"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ManageCheatSheetPage()),
            ),

            // --- FIXED: Removed 'const' from SortDataPage() ---
            ListTile(
              leading: wrapLeading(
                const Icon(Icons.sort, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("Manage Sort Data"),
              subtitle: const Text(
                "Choose data to practice, review, and quiz based on your preferences",
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, SortDataPage()),
            ),
            ListTile(
              leading: wrapLeading(
                const Icon(Icons.notification_important, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("Word of the Day"),
              subtitle: const Text("Set notification reminders for words"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const WordOfDayPage()),
            ),

            ListTile(
              leading: wrapLeading(
                const Icon(Icons.quiz, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
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
              leading: wrapLeading(
                const Icon(Icons.style, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
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
              leading: wrapLeading(
                const Icon(Icons.record_voice_over, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("Change Voice"),
              subtitle: const Text(
                "Select your preferred text-to-speech voice",
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const VoiceSelectionPage()),
            ),
            ListTile(
              leading: wrapLeading(
                const Icon(Icons.event, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("Exam Countdown"),
              subtitle: const Text("Set your exam date and visibility"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ExamCountdownPage()),
            ),
            ListTile(
              leading: wrapLeading(
                const Icon(Icons.auto_awesome, color: Colors.indigo),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("APIs"),
              subtitle: const Text("Add your Gemini API key & model"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const ApiSettingsPage()),
            ),
            ListTile(
              leading: wrapLeading(
                const Icon(Icons.backup, color: Colors.teal),
              ),
              minLeadingWidth: leadingWidth,
              title: const Text("Backup & Restore"),
              subtitle: const Text("Export or Import your data via JSON"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _navigateTo(context, const BackupRestorePage()),
            ),
            ListTile(
              leading: wrapLeading(const Icon(Icons.info, color: Colors.teal)),
              minLeadingWidth: leadingWidth,
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
