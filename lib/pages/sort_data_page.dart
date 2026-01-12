import 'package:flutter/material.dart';

import 'sort_words_data_page.dart';
import 'sort_idioms_data_page.dart';

class SortDataPage extends StatelessWidget {
  const SortDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sort Data Preferences'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.sort_by_alpha, color: Colors.indigo),
            title: const Text('Sort Words Data'),
            subtitle: const Text(
              'Choose which WORDS appear in practice, review, and quizzes',
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SortWordsDataPage(),
                ),
              );

              if (result == true && context.mounted) {
                Navigator.pop(context, true);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book, color: Colors.indigo),
            title: const Text('Sort Idioms Data'),
            subtitle: const Text(
              'Choose which IDIOMS appear in practice, review, and quizzes',
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SortIdiomsDataPage(),
                ),
              );

              if (result == true && context.mounted) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
    );
  }
}
