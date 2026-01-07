import 'package:flutter/material.dart';

class IdiomsPage extends StatefulWidget {
  const IdiomsPage({super.key});

  @override
  State<IdiomsPage> createState() => _IdiomsPageState();
}

class _IdiomsPageState extends State<IdiomsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Idioms"),
      ),
      body: const Center(
        child: Text(
          "Idioms Content Template",
          style: TextStyle(fontSize: 20, color: Colors.grey),
        ),
      ),
    );
  }
}