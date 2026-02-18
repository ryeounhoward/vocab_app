import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_app/pages/idiom_review_page.dart';
import 'package:vocab_app/pages/cheat_sheet_page.dart';
import 'package:vocab_app/pages/notes_page.dart';
import 'package:vocab_app/pages/quiz_page.dart';
import 'package:vocab_app/pages/review_page.dart';
import 'package:vocab_app/pages/settings_page.dart';
import 'package:vocab_app/pages/vocabulary_test_page.dart';
import 'package:vocab_app/services/refresh_signal.dart';
import 'package:vocab_app/services/github_update_service.dart';
import 'google_drive_Service.dart';
import '../database/db_helper.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final DBHelper _dbHelper = DBHelper();
  String? _wordGroupName;
  String? _idiomGroupName;

  final GoogleDriveService _googleDriveService = GoogleDriveService();
  StreamSubscription<GoogleSignInAccount?>? _accountSub;
  GoogleSignInAccount? _account;

  bool get _isLoggedIn => _account != null;

  @override
  void initState() {
    super.initState();
    _loadSelectedGroups();
    DataRefreshSignal.refreshNotifier.addListener(_onGlobalRefresh);

    _account = _googleDriveService.currentUser;
    _accountSub = _googleDriveService.onCurrentUserChanged.listen((account) {
      if (!mounted) return;
      setState(() {
        _account = account;
      });
    });

    unawaited(_restoreSignInSilently());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      GitHubUpdateService.checkForUpdates(context);
    });
  }

  Future<void> _restoreSignInSilently() async {
    final account = await _googleDriveService.ensureSignedIn(
      interactive: false,
    );
    if (!mounted) return;
    setState(() {
      _account = account;
    });
  }

  void _onGlobalRefresh() {
    if (mounted) {
      _loadSelectedGroups();
    }
  }

  @override
  void dispose() {
    DataRefreshSignal.refreshNotifier.removeListener(_onGlobalRefresh);
    _accountSub?.cancel();
    super.dispose();
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _firstNameFor(GoogleSignInAccount account) {
    final displayName = account.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      final parts = displayName
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty);
      final first = parts.isEmpty ? null : parts.first;
      if (first != null && first.isNotEmpty) return first;
    }

    final email = account.email.trim();
    final at = email.indexOf('@');
    if (at > 0) return email.substring(0, at);
    return email;
  }

  Widget _buildTopRightAvatar() {
    if (!_isLoggedIn) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.grey.shade200,
        child: Icon(Icons.person, color: Colors.grey),
      );
    }

    final photoUrl = _account?.photoUrl;
    if (photoUrl == null || photoUrl.trim().isEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.grey.shade200,
        child: Icon(Icons.person, color: Colors.grey),
      );
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.grey.shade200,
      child: ClipOval(
        child: Image.network(
          photoUrl,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.person, color: Colors.grey),
        ),
      ),
    );
  }

  Future<void> _openProfileOrSettings() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  void _comingSoon(String featureName) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$featureName: coming soon')));
  }

  Future<void> _loadSelectedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final bool useAllWords = prefs.getBool('quiz_use_all_words') ?? true;
    final bool useAllIdioms = prefs.getBool('quiz_use_all_idioms') ?? true;

    final int? wordGroupId = prefs.getInt('quiz_selected_word_group_id');
    final int? idiomGroupId = prefs.getInt('quiz_selected_idiom_group_id');

    String? wordName;
    if (useAllWords) {
      wordName = "All Words";
    } else if (wordGroupId != null) {
      final groups = await _dbHelper.getAllWordGroups();
      final group = groups.firstWhere(
        (g) => g['id'].toString() == wordGroupId.toString(),
        orElse: () => <String, dynamic>{},
      );
      wordName = group['name']?.toString() ?? "Selected Words";
    } else {
      wordName = "Selected Words";
    }

    String? idiomName;
    if (useAllIdioms) {
      idiomName = "All Idioms";
    } else if (idiomGroupId != null) {
      final groups = await _dbHelper.getAllIdiomGroups();
      final group = groups.firstWhere(
        (g) => g['id'].toString() == idiomGroupId.toString(),
        orElse: () => <String, dynamic>{},
      );
      idiomName = group['name']?.toString() ?? "Selected Idioms";
    } else {
      idiomName = "Selected Idioms";
    }

    if (!mounted) return;
    setState(() {
      _wordGroupName = wordName;
      _idiomGroupName = idiomName;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _account == null
                            ? '${_timeGreeting()}!'
                            : '${_timeGreeting()}, ${_firstNameFor(_account!)}!',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: _openProfileOrSettings,
                      borderRadius: BorderRadius.circular(24),
                      child: _buildTopRightAvatar(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.0,
                    children: [
                      MenuCard(
                        title: "Words",
                        subtitle: _wordGroupName,
                        icon: Icons.menu_book_rounded,
                        color: Colors.blueAccent,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ReviewPage(),
                          ),
                        ),
                      ),
                      MenuCard(
                        title: "Idioms",
                        subtitle: _idiomGroupName,
                        icon: Icons.lightbulb_rounded,
                        color: Colors.orangeAccent,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const IdiomReviewPage(),
                          ),
                        ),
                      ),
                      MenuCard(
                        title: "Practice",
                        subtitle: "Practice Mode",
                        icon: Icons.style,
                        color: Colors.purpleAccent,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const QuizPage(),
                          ),
                        ),
                      ),
                      MenuCard(
                        title: "Quiz",
                        subtitle: "Test Yourself",
                        icon: Icons.quiz,
                        color: Colors.indigo,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const VocabularyTestPage(),
                          ),
                        ),
                      ),
                      MenuCard(
                        title: "Notes",
                        subtitle: "My Notepad",
                        icon: Icons.note_alt_outlined,
                        color: Colors.teal,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NotesPage(),
                          ),
                        ),
                      ),
                      MenuCard(
                        title: "English",
                        subtitle: "Grammar & Usage",
                        icon: Icons.spellcheck,
                        color: Colors.redAccent,
                        onTap: () => _comingSoon('English'),
                      ),
                      MenuCard(
                        title: "Mathematics",
                        subtitle: "Formulas",
                        icon: Icons.calculate,
                        color: Colors.cyan,
                        onTap: () => _comingSoon('Mathematics'),
                      ),
                      MenuCard(
                        title: "Cheat Sheet",
                        subtitle: "Quick notes",
                        icon: Icons.fact_check,
                        color: Colors.brown,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CheatSheetPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MenuCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon; // Changed from imagePath to IconData
  final Color color;
  final VoidCallback onTap;

  const MenuCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(20);
    final hoverOverlay = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.06);
    final focusOverlay = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.10);
    final hsl = HSLColor.fromColor(color);
    final iconBg = hsl
        .withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0))
        .toColor()
        .withOpacity(0.45);

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withOpacity(0.8)],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: hoverOverlay,
          focusColor: focusOverlay,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    subtitle!.trim(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
