import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_app/pages/idiom_review_page.dart';
import 'package:vocab_app/pages/review_page.dart';
import 'package:vocab_app/services/refresh_signal.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSelectedGroups();
    // Listen for the signal from the Sort page
    DataRefreshSignal.refreshNotifier.addListener(_onGlobalRefresh);
  }

  void _onGlobalRefresh() {
    if (mounted) {
      _loadSelectedGroups();
    }
  }

  @override
  void dispose() {
    DataRefreshSignal.refreshNotifier.removeListener(_onGlobalRefresh);
    super.dispose();
  }

  Future<void> _loadSelectedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force sync

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
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double cardHeight = constraints.maxHeight / 2;
            return SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    height: cardHeight,
                    child: MenuCard(
                      title: "Words",
                      subtitle: _wordGroupName,
                      imagePath: "assets/images/vocabulary.jpg",
                      color: Colors.blueAccent,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReviewPage(),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: cardHeight,
                    child: MenuCard(
                      title: "Idioms",
                      subtitle: _idiomGroupName,
                      imagePath: "assets/images/idioms.jpg",
                      color: Colors.orangeAccent,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const IdiomReviewPage(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Keep your MenuCard class as is...

class MenuCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String imagePath;
  final Color color;
  final VoidCallback onTap;

  const MenuCard({
    required this.title,
    this.subtitle,
    required this.imagePath,
    required this.color,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(imagePath, fit: BoxFit.cover),
              Container(color: Colors.black.withOpacity(0.4)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    // Display group name in brackets if it exists
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '(${subtitle!.trim()})',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
