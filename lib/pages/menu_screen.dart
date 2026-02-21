import 'dart:async';
import 'dart:convert';

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
import 'package:vocab_app/pages/exam_countdown_page.dart';
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
  static const String _defaultNoteText =
      'Stay focused, stay prepared, and keep pushing forward!';
  final DBHelper _dbHelper = DBHelper();
  String? _wordGroupName;
  String? _idiomGroupName;

  final GoogleDriveService _googleDriveService = GoogleDriveService();
  StreamSubscription<GoogleSignInAccount?>? _accountSub;
  GoogleSignInAccount? _account;

  DateTime _examDate = DateTime(2026, 3, 8);
  Duration _timeLeft = Duration.zero;
  Timer? _countdownTimer;
  bool _showCountdown = true;
  bool _showNote = true;
  List<String> _notes = [_defaultNoteText];
  int _noteDurationSeconds = 4;
  int _noteIndex = 0;
  Timer? _noteTimer;
  String _countdownPalette = 'indigo';
  int _unreadNotifications = 0;

  static final List<_CountdownPalette> _palettes = [
    _CountdownPalette(
      id: 'indigo',
      name: 'Indigo (Default)',
      light: Colors.indigo.shade50,
      dark: Colors.indigo,
    ),
    _CountdownPalette(
      id: 'teal',
      name: 'Teal',
      light: Colors.teal.shade100,
      dark: Colors.teal.shade600,
    ),
    _CountdownPalette(
      id: 'emerald',
      name: 'Emerald',
      light: Colors.green.shade100,
      dark: Colors.green.shade600,
    ),
    _CountdownPalette(
      id: 'blue',
      name: 'Blue',
      light: Colors.blue.shade100,
      dark: Colors.blue.shade600,
    ),
    _CountdownPalette(
      id: 'cyan',
      name: 'Cyan',
      light: Colors.cyan.shade100,
      dark: Colors.cyan.shade700,
    ),
    _CountdownPalette(
      id: 'orange',
      name: 'Orange',
      light: Colors.white,
      dark: Colors.orange.shade700,
    ),
    _CountdownPalette(
      id: 'amber',
      name: 'Amber',
      light: Colors.amber.shade100,
      dark: Colors.amber.shade700,
    ),
    _CountdownPalette(
      id: 'rose',
      name: 'Rose',
      light: Colors.pink.shade100,
      dark: Colors.pink.shade600,
    ),
    _CountdownPalette(
      id: 'purple',
      name: 'Purple',
      light: Colors.deepPurple.shade100,
      dark: Colors.deepPurple.shade600,
    ),
    _CountdownPalette(
      id: 'slate',
      name: 'Slate',
      light: Colors.blueGrey.shade100,
      dark: Colors.blueGrey.shade700,
    ),
  ];

  bool get _isLoggedIn => _account != null;

  @override
  void initState() {
    super.initState();
    _loadSelectedGroups();
    _loadCountdownPrefs();
    _loadNotificationBadge();
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
    _countdownTimer?.cancel();
    _noteTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCountdownPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final show = prefs.getBool('exam_countdown_show') ?? true;
    final millis = prefs.getInt('exam_countdown_date');
    final paletteId = prefs.getString('exam_countdown_palette') ?? 'indigo';
    final notesRaw = prefs.getString('exam_countdown_notes');
    final duration = prefs.getInt('exam_countdown_note_duration') ?? 4;
    final showNote = prefs.getBool('exam_countdown_note_show') ?? true;
    final date = millis != null
        ? DateTime.fromMillisecondsSinceEpoch(millis)
        : DateTime(2026, 3, 8);
    final decodedNotes = _decodeNotes(notesRaw);
    if (!mounted) return;
    setState(() {
      _showCountdown = show;
      _showNote = showNote;
      _notes = decodedNotes.isNotEmpty ? decodedNotes : [_defaultNoteText];
      _noteDurationSeconds = _clampDuration(duration);
      _noteIndex = 0;
      _examDate = date;
      _countdownPalette = _palettes.any((p) => p.id == paletteId)
          ? paletteId
          : 'indigo';
    });
    _startCountdown();
    _startNoteRotation();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    void update() {
      final diff = _examDate.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _timeLeft = diff.isNegative ? Duration.zero : diff);
    }

    update();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (t) => update(),
    );
  }

  void _startNoteRotation() {
    _noteTimer?.cancel();
    if (!_showNote || _notes.length < 2) return;
    _noteTimer = Timer.periodic(Duration(seconds: _noteDurationSeconds), (_) {
      if (!mounted) return;
      setState(() {
        _noteIndex = (_noteIndex + 1) % _notes.length;
      });
    });
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
    final avatar = _buildAvatarContent();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        if (_unreadNotifications > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              height: 16,
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1),
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
          ),
      ],
    );
  }

  Widget _buildAvatarContent() {
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
    if (!mounted) return;
    await _loadCountdownPrefs();
    await _loadNotificationBadge();
  }

  void _comingSoon(String featureName) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$featureName: coming soon')));
  }

  Future<void> _openCountdownSettings() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExamCountdownPage()),
    );
    if (!mounted) return;
    await _loadCountdownPrefs();
    await _loadNotificationBadge();
  }

  Future<void> _loadNotificationBadge() async {
    final count = await _dbHelper.getUnreadNotificationCount();
    if (!mounted) return;
    setState(() => _unreadNotifications = count);
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
    final int days = _timeLeft.inDays;
    final int hours = _timeLeft.inHours % 24;
    final int minutes = _timeLeft.inMinutes % 60;
    final int seconds = _timeLeft.inSeconds % 60;

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
                if (_showCountdown) ...[
                  const SizedBox(height: 12),
                  _buildCountdownSection(days, hours, minutes, seconds),
                ],
                if (_showNote) ...[
                  const SizedBox(height: 12),
                  _buildNoteCard(showEditButton: !_showCountdown),
                ],
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

  Widget _buildCountdownSection(int d, int h, int m, int s) {
    final palette = _palettes.firstWhere(
      (p) => p.id == _countdownPalette,
      orElse: () => _palettes.first,
    );
    final cardColor = palette.light;
    final titleColor = _useLightText(cardColor) ? Colors.white : Colors.black87;
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exam Countdown',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildCountdownBox('$d', 'Days'),
                  const SizedBox(width: 8),
                  _buildCountdownBox('$h', 'Hours'),
                  const SizedBox(width: 8),
                  _buildCountdownBox('$m', 'Mins'),
                  const SizedBox(width: 8),
                  _buildCountdownBox('$s', 'Secs'),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openCountdownSettings,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit, size: 16, color: Colors.black87),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownBox(String value, String label) {
    final palette = _palettes.firstWhere(
      (p) => p.id == _countdownPalette,
      orElse: () => _palettes.first,
    );
    final badgeColor = palette.dark;
    final forceWhite = palette.id == 'orange';
    final valueColor = forceWhite
        ? Colors.white
        : _useLightText(badgeColor)
        ? Colors.white
        : Colors.black87;
    final labelColor = forceWhite
        ? Colors.white70
        : valueColor.withOpacity(0.7);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 10, color: labelColor)),
          ],
        ),
      ),
    );
  }

  bool _useLightText(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
  }

  int _clampDuration(int value) {
    if (value < 2) return 2;
    if (value > 10) return 10;
    return value;
  }

  List<String> _decodeNotes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((note) => note.trim())
            .where((note) => note.isNotEmpty)
            .toList();
      }
    } catch (_) {
      return [];
    }
    return [];
  }

  Widget _buildNoteCard({required bool showEditButton}) {
    final palette = _palettes.firstWhere(
      (p) => p.id == _countdownPalette,
      orElse: () => _palettes.first,
    );
    final cardColor = palette.light;
    final textColor = _useLightText(cardColor) ? Colors.white : Colors.black87;
    final note = _notes.isEmpty
        ? _defaultNoteText
        : _notes[_noteIndex.clamp(0, _notes.length - 1)];
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            height: 40,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Text(
                note,
                key: ValueKey('note_${note}_$_noteIndex'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
          ),
        ),
        if (showEditButton)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openCountdownSettings,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit,
                    size: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CountdownPalette {
  final String id;
  final String name;
  final Color light;
  final Color dark;

  const _CountdownPalette({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
  });
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
