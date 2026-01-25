import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_app/pages/idiom_review_page.dart';
import 'package:vocab_app/pages/notes_page.dart';
import 'package:vocab_app/pages/review_page.dart';

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
  }

  Future<void> _loadSelectedGroups() async {
    final prefs = await SharedPreferences.getInstance();

    final bool useAllWords = prefs.getBool('quiz_use_all_words') ?? true;
    final bool useAllIdioms = prefs.getBool('quiz_use_all_idioms') ?? true;

    final int? wordGroupId = prefs.getInt('quiz_selected_word_group_id');
    final int? idiomGroupId = prefs.getInt('quiz_selected_idiom_group_id');

    String? wordName;
    if (!useAllWords && wordGroupId != null) {
      final groups = await _dbHelper.getAllWordGroups();
      final group = groups.firstWhere(
        (g) => g['id'] == wordGroupId,
        orElse: () => <String, dynamic>{},
      );
      final name = (group['name'] ?? '').toString().trim();
      if (name.isNotEmpty) wordName = name;
    }

    String? idiomName;
    if (!useAllIdioms && idiomGroupId != null) {
      final groups = await _dbHelper.getAllIdiomGroups();
      final group = groups.firstWhere(
        (g) => g['id'] == idiomGroupId,
        orElse: () => <String, dynamic>{},
      );
      final name = (group['name'] ?? '').toString().trim();
      if (name.isNotEmpty) idiomName = name;
    }

    if (!mounted) return;
    setState(() {
      _wordGroupName = wordName;
      _idiomGroupName = idiomName;
    });
  }

  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // LayoutBuilder gives us the exact height of the safe area
        child: LayoutBuilder(
          builder: (context, constraints) {
            // We calculate the height so that exactly 2 cards fit in the view.
            // (Total Height / 2). The 3rd card will be off-screen until scrolled.
            final double cardHeight = constraints.maxHeight / 2;

            return SingleChildScrollView(
              child: Column(
                children: [
                  // 1. WORDS CARD
                  SizedBox(
                    height: cardHeight,
                    child: MenuCard(
                      title: "Words",
                      subtitle: _wordGroupName,
                      imagePath: "assets/images/vocabulary.jpg",
                      color: Colors.blueAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ReviewPage(),
                          ),
                        );
                      },
                    ),
                  ),

                  // 2. IDIOMS CARD
                  SizedBox(
                    height: cardHeight,
                    child: MenuCard(
                      title: "Idioms",
                      subtitle: _idiomGroupName,
                      imagePath: "assets/images/idioms.jpg",
                      color: Colors.orangeAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const IdiomReviewPage(),
                          ),
                        );
                      },
                    ),
                  ),

                  // SizedBox(
                  //   height: cardHeight,
                  //   child: MenuCard(
                  //     title: "Conversation",
                  //     imagePath: "assets/images/notes.jpg",
                  //     color: Colors.greenAccent,
                  //     onTap: () {
                  //       Navigator.push(
                  //         context,
                  //         MaterialPageRoute(
                  //           builder: (context) => const NotesPage(),
                  //         ),
                  //       );
                  //     },
                  //   ),
                  // ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

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
              // Background Image
              Image.asset(imagePath, fit: BoxFit.cover),
              // Overlay for readability
              Container(color: Colors.black.withOpacity(0.4)),
              // Title Text
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
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      Text(
                        '(${subtitle!.trim()})',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
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
