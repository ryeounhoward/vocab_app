import 'package:flutter/material.dart';
import 'package:vocab_app/pages/idiom_review_page.dart';
import 'package:vocab_app/pages/review_page.dart';
import 'package:vocab_app/pages/conversation_page.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
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

                  // 3. CONVERSATION CARD
                  SizedBox(
                    height: cardHeight,
                    child: MenuCard(
                      title: "Conversation",
                      imagePath: "assets/images/conversation.jpg",
                      color: Colors.greenAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ConversationPage(),
                          ),
                        );
                      },
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

class MenuCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final Color color;
  final VoidCallback onTap;

  const MenuCard({
    required this.title,
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
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
