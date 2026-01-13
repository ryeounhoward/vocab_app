import 'package:flutter/material.dart';

import 'sort_words_data_page.dart';
import 'sort_idioms_data_page.dart';
import 'word_groups_page.dart';
import 'idiom_groups_page.dart';

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
            leading: const Icon(Icons.menu_book, color: Colors.indigo),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Word sort settings saved!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.list_alt, color: Colors.indigo),
            title: const Text('Word Groups'),
            subtitle: const Text('Create and edit named groups of words'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const WordGroupsPage()),
              );

              if (result == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Word group saved!'),
                    duration: Duration(seconds: 2),
                  ),
                );
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Idiom sort settings saved!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.list_alt, color: Colors.deepPurple),
            title: const Text('Idiom Groups'),
            subtitle: const Text('Create and edit named groups of idioms'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const IdiomGroupsPage(),
                ),
              );

              if (result == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Idiom group saved!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
