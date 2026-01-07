import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vocab_app/pages/idoms_page.dart';
import 'review_page.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Study Menu"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // TOP CARD: VOCABULARY
          Expanded(
            child: MenuCard(
              title: "Vocabulary",
              imagePath: "assets/vocabulary.jpg", // Replace with your asset path
              color: Colors.blueAccent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReviewPage()),
                );
              },
            ),
          ),
          
          // BOTTOM CARD: IDIOMS
          Expanded(
            child: MenuCard(
              title: "Idioms",
              imagePath: "assets/idioms.jpg", // Replace with your asset path
              color: Colors.orangeAccent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const IdiomsPage()),
                );
              },
            ),
          ),
        ],
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
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background Image (Placeholder used if asset missing)
              Image.network(
                "https://via.placeholder.com/400x200?text=$title", // Replace with Image.asset(imagePath)
                fit: BoxFit.cover,
              ),
              // Overlay for readability
              Container(
                color: Colors.black.withOpacity(0.4),
              ),
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
