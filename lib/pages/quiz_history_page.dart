import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'word_detail_page.dart';

class QuizHistoryPage extends StatefulWidget {
  const QuizHistoryPage({super.key});

  @override
  State<QuizHistoryPage> createState() => _QuizHistoryPageState();
}

class _QuizHistoryPageState extends State<QuizHistoryPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString('quiz_history') ?? '[]';
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    final List<Map<String, dynamic>> list = decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    list.sort((a, b) {
      final String aDate = (a['date'] ?? '').toString();
      final String bDate = (b['date'] ?? '').toString();
      return bDate.compareTo(aDate);
    });

    if (!mounted) return;
    setState(() {
      _history = list;
      _isLoading = false;
    });
  }

  String _formatDate(String iso) {
    if (iso.trim().isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final String monthName = months[dt.month - 1];
    return '$monthName ${dt.day}, ${dt.year}';
  }

  String _formatDuration(int seconds) {
    if (seconds < 0) seconds = 0;
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;
    final parts = <String>[];
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0 || hours > 0) parts.add('${minutes}m');
    parts.add('${secs}s');
    return parts.join(' ');
  }

  String _modeLabel(String mode) {
    if (mode == 'desc_to_word') return 'Definition to Word';
    if (mode == 'word_to_desc') return 'Word to Definition';
    if (mode == 'sentence_to_word') return 'Sentence to Word';
    return mode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz History'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? const Center(
              child: Text('No quiz history yet.', textAlign: TextAlign.center),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = _history[index];
                final String date = _formatDate(item['date'] ?? '');
                final int totalItems = (item['totalItems'] ?? 0) as int;
                final int durationSeconds =
                    (item['durationSeconds'] ?? 0) as int;
                final String mode = _modeLabel(
                  (item['quizMode'] ?? '').toString(),
                );
                final String quizLabel =
                    'Quiz ${(item['quizNumber'] ?? '').toString()}';

                final shape = RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                );

                return Card(
                  elevation: 2,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    shape: shape,
                    title: Text(
                      date.isNotEmpty ? '$quizLabel ($date)' : quizLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Duration: ${_formatDuration(durationSeconds)}'),
                          Text('Total items: $totalItems'),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              QuizHistoryDetailPage(historyItem: item),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class QuizHistoryDetailPage extends StatefulWidget {
  final Map<String, dynamic> historyItem;

  const QuizHistoryDetailPage({super.key, required this.historyItem});

  @override
  State<QuizHistoryDetailPage> createState() => _QuizHistoryDetailPageState();
}

class _QuizHistoryDetailPageState extends State<QuizHistoryDetailPage> {
  bool _showDetails = true;

  String _formatDuration(int seconds) {
    if (seconds < 0) seconds = 0;
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;
    final parts = <String>[];
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0 || hours > 0) parts.add('${minutes}m');
    parts.add('${secs}s');
    return parts.join(' ');
  }

  String _modeLabel(String mode) {
    if (mode == 'desc_to_word') return 'Definition to Word';
    if (mode == 'word_to_desc') return 'Word to Definition';
    if (mode == 'sentence_to_word') return 'Sentence to Word';
    return mode;
  }

  String _formatDate(String iso) {
    if (iso.trim().isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final String monthName = months[dt.month - 1];
    return '$monthName ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final historyItem = widget.historyItem;
    final List<Map<String, dynamic>> items =
        ((historyItem['items'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    final int totalItems = (historyItem['totalItems'] ?? 0) as int;
    final int durationSeconds = (historyItem['durationSeconds'] ?? 0) as int;
    final String mode = _modeLabel((historyItem['quizMode'] ?? '').toString());
    final String date = _formatDate((historyItem['date'] ?? '').toString());
    final int correctCount = items
        .where((e) => (e['isCorrect'] ?? false) == true)
        .length;
    final int skippedCount = items
        .where((e) => (e['isSkipped'] ?? false) == true)
        .length;

    final double scorePercent = totalItems <= 0
        ? 0
        : (correctCount / totalItems).clamp(0.0, 1.0) * 100.0;
    final bool isPassed = scorePercent >= 80.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Quiz Details'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: isPassed ? Colors.green : Colors.red,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$correctCount / $totalItems',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Score: ${scorePercent.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showDetails = !_showDetails;
                    });
                  },
                  child: Text(
                    _showDetails ? 'Collapse Details' : 'Show Details',
                  ),
                ),
              ],
            ),
            if (_showDetails)
              SizedBox(
                width: double.infinity,
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: Colors.indigo,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quiz mode: $mode',
                          style: const TextStyle(color: Colors.white),
                        ),
                        if (date.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Date: $date',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Duration: ${_formatDuration(durationSeconds)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Total items: $totalItems',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Skipped: $skippedCount',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Words',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        'No answered items were recorded for this quiz.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final String word = (item['word'] ?? '').toString();
                        final bool isSkipped =
                            (item['isSkipped'] ?? false) as bool;
                        final bool isCorrect =
                            (item['isCorrect'] ?? false) as bool;
                        final int itemDuration =
                            (item['durationSeconds'] ?? 0) as int;
                        final Map<String, dynamic>? wordData =
                            item['wordData'] == null
                            ? null
                            : Map<String, dynamic>.from(
                                item['wordData'] as Map,
                              );

                        final shape = RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        );

                        return Card(
                          elevation: 1,
                          shape: shape,
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            shape: shape,
                            title: Text(
                              word.isNotEmpty ? word : 'Unknown word',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isSkipped
                                        ? 'Skipped'
                                        : (isCorrect ? 'Correct' : 'Wrong'),
                                    style: TextStyle(
                                      color: isSkipped
                                          ? Colors.orange
                                          : (isCorrect
                                                ? Colors.green
                                                : Colors.red),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Duration: ${_formatDuration(itemDuration)}',
                                  ),
                                ],
                              ),
                            ),
                            trailing: TextButton(
                              onPressed: wordData == null
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              WordDetailPage(item: wordData),
                                        ),
                                      );
                                    },
                              child: const Text('VIEW'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
