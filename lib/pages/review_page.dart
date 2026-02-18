import 'dart:convert'; // Added for jsonDecode
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vocab_app/services/refresh_signal.dart';
import '../database/db_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'search_page.dart';

class ReviewPage extends StatefulWidget {
  final int? selectedId;
  final String? originTable;

  const ReviewPage({super.key, this.selectedId, this.originTable});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final dbHelper = DBHelper();
  final FlutterTts flutterTts = FlutterTts();
  List<Map<String, dynamic>> _vocabList = [];
  bool _isLoading = true;
  PageController? _pageController;

  Map<String, String>? _currentVoice;

  // --- ADDED: Tense Configuration from WordDetailPage ---
  final List<String> _tenseOrder = const [
    'Present Tense',
    'Past Tense',
    'Present Participle',
    'Past Participle',
    'Present Perfect',
    'Past Perfect',
    'Future Perfect',
  ];
  static const Color _tenseAccentColor = Colors.indigo;
  static final Color _relatedFormsAccentColor = Colors.teal.shade700;
  bool _isRelatedFormsExpanded = false;
  bool _isTenseExpanded = false;
  // ------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadTenseDefaultPreference();
    _initTts();
    _loadAndShuffle();
    DataRefreshSignal.refreshNotifier.addListener(_onGlobalRefresh);
  }

  Future<void> _loadTenseDefaultPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final bool showByDefault = prefs.getBool('show_tenses_by_default') ?? false;
    if (!mounted) return;
    setState(() {
      _isRelatedFormsExpanded = showByDefault;
      _isTenseExpanded = showByDefault;
    });
  }

  void _onGlobalRefresh() {
    if (mounted) {
      _loadAndShuffle();
    }
  }

  @override
  void dispose() {
    DataRefreshSignal.refreshNotifier.removeListener(_onGlobalRefresh);
    flutterTts.stop();
    _pageController?.dispose();
    super.dispose();
  }

  void _initTts() async {
    final prefs = await SharedPreferences.getInstance();
    String? voiceName = prefs.getString('selected_voice_name');
    String? voiceLocale = prefs.getString('selected_voice_locale');

    if (voiceName != null && voiceLocale != null) {
      _currentVoice = {"name": voiceName, "locale": voiceLocale};
      await flutterTts.setVoice(_currentVoice!);
    } else {
      await flutterTts.setLanguage("en-US");
    }

    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);
  }

  void _loadAndShuffle() async {
    final data = await dbHelper.queryAll(DBHelper.tableVocab);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final bool useAllWords = prefs.getBool('quiz_use_all_words') ?? true;
    final List<String> storedIds =
        prefs.getStringList('quiz_selected_word_ids') ?? <String>[];
    final Set<int> selectedIds = storedIds
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .toSet();
    final int? groupId = prefs.getInt('quiz_selected_word_group_id');

    List<Map<String, dynamic>> filteredData;
    if (groupId != null) {
      final Set<int> groupIds = await dbHelper.getWordIdsForGroup(groupId);
      filteredData = data
          .where((item) => groupIds.contains(item['id'] as int? ?? -1))
          .toList();
    } else if (useAllWords) {
      filteredData = List<Map<String, dynamic>>.from(data);
    } else if (selectedIds.isNotEmpty) {
      filteredData = data
          .where((item) => selectedIds.contains(item['id'] as int? ?? -1))
          .toList();
    } else {
      filteredData = <Map<String, dynamic>>[];
    }

    final order = prefs.getString('practice_order') ?? 'shuffle';
    List<Map<String, dynamic>> orderedData = List.from(filteredData);

    if (order == 'az') {
      orderedData.sort((a, b) {
        final String aWord = (a['word'] ?? '').toString().toLowerCase();
        final String bWord = (b['word'] ?? '').toString().toLowerCase();
        return aWord.compareTo(bWord);
      });
    } else if (order == 'za') {
      orderedData.sort((a, b) {
        final String aWord = (a['word'] ?? '').toString().toLowerCase();
        final String bWord = (b['word'] ?? '').toString().toLowerCase();
        return bWord.compareTo(aWord);
      });
    } else {
      orderedData.shuffle();
    }

    int targetIndex = 0;
    if (widget.selectedId != null) {
      targetIndex = orderedData.indexWhere(
        (item) => item['id'] == widget.selectedId,
      );

      if (targetIndex == -1) {
        final fallback = data.firstWhere(
          (item) => item['id'] == widget.selectedId,
          orElse: () => <String, dynamic>{},
        );
        if (fallback.isNotEmpty) {
          orderedData.insert(0, Map<String, dynamic>.from(fallback));
          targetIndex = 0;
        } else {
          targetIndex = 0;
        }
      }
    }

    setState(() {
      _vocabList = orderedData;
      _isLoading = false;
      if (_vocabList.isNotEmpty) {
        int initialPage = (_vocabList.length * 100) + targetIndex;
        _pageController = PageController(
          viewportFraction: 0.93,
          initialPage: initialPage,
        );
      }
    });
  }

  Future<void> _playFavoriteSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('favorite_sound_enabled') ?? true;
      if (!enabled) return;

      final player = AudioPlayer();
      await player.play(AssetSource('sounds/star2.mp3'));
      player.onPlayerComplete.listen((event) {
        player.dispose();
      });
    } catch (e) {
      debugPrint('Error playing favorite sound: $e');
    }
  }

  Future<void> _speak(
    String word,
    String type,
    String desc,
    List<String> examples,
    String synonyms,
  ) async {
    if (_currentVoice != null) {
      await flutterTts.setVoice(_currentVoice!);
    }

    String article = "a";
    if (type.isNotEmpty) {
      String firstLetter = type.trim().substring(0, 1).toLowerCase();
      if ("aeiou".contains(firstLetter)) article = "an";
    }
    String wordType = type.isNotEmpty ? type : "word";
    String meaningPart = desc.isNotEmpty
        ? "$word is $article $wordType that means $desc."
        : "$word is $article $wordType.";

    String exampleText = "";
    if (examples.isNotEmpty) {
      exampleText = examples.length == 1
          ? " The example is: ${examples.first}"
          : " The examples are: ${examples.join(". ")}";
    }

    String synonymsPart = synonyms.trim().isNotEmpty
        ? " Its synonyms are: $synonyms."
        : "";

    await flutterTts.speak("$meaningPart$synonymsPart$exampleText");
  }

  void _toggleFav(int indexInList, Map<String, dynamic> item) async {
    int newStatus = (item['is_favorite'] == 1) ? 0 : 1;
    await dbHelper.toggleFavorite(
      item['id'],
      newStatus == 1,
      DBHelper.tableVocab,
    );
    setState(() {
      Map<String, dynamic> updatedItem = Map.from(item);
      updatedItem['is_favorite'] = newStatus;
      _vocabList[indexInList] = updatedItem;
    });
    if (newStatus == 1) _playFavoriteSound();
  }

  // --- ADDED: Tense Parser from WordDetailPage ---
  // Adjusted to accept a specific 'item' instead of using a global 'currentItem'
  Map<String, Map<String, String>> _parseTenseData(Map<String, dynamic> item) {
    final raw = (item['tense_data'] as String? ?? '').trim();
    if (raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};

      final Map<String, Map<String, String>> result = {};
      for (final tense in _tenseOrder) {
        final value = decoded[tense];
        if (value is! Map<String, dynamic>) continue;

        final conjugation = (value['conjugation'] ?? '').toString().trim();
        final example = (value['example'] ?? '').toString().trim();
        if (conjugation.isEmpty && example.isEmpty) continue;

        result[tense] = {'conjugation': conjugation, 'example': example};
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  List<Map<String, String>> _parseRelatedForms(Map<String, dynamic> item) {
    final raw = (item['related_forms'] as String? ?? '').trim();
    if (raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map>()
          .map(
            (entry) => {
              'form': (entry['form'] ?? '').toString().trim(),
              'type': (entry['type'] ?? '').toString().trim(),
              'meaning': (entry['meaning'] ?? '').toString().trim(),
              'example': (entry['example'] ?? '').toString().trim(),
            },
          )
          .where(
            (entry) =>
                entry['form']!.isNotEmpty ||
                entry['type']!.isNotEmpty ||
                entry['meaning']!.isNotEmpty ||
                entry['example']!.isNotEmpty,
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }
  // -----------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Words"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SearchPage()),
            ),
          ),
        ],
      ),
      body: _vocabList.isEmpty
          ? const Center(
              child: Text("No vocabulary found for current selection."),
            )
          : SafeArea(
              child: PageView.builder(
                itemCount: 1000000,
                controller: _pageController,
                onPageChanged: (index) => flutterTts.stop(),
                itemBuilder: (context, index) {
                  final actualIndex = index % _vocabList.length;
                  final item = _vocabList[actualIndex];
                  return _buildVocabCard(item, actualIndex);
                },
              ),
            ),
    );
  }

  Widget _buildVocabCard(Map<String, dynamic> item, int indexInList) {
    bool isFav = item['is_favorite'] == 1;
    List<String> examplesList = (item['examples'] as String? ?? "")
        .split('\n')
        .where((String e) => e.trim().isNotEmpty)
        .toList();
    // Added pronunciation and tense data extraction
    final pronunciation = (item['pronunciation'] as String? ?? '').trim();
    String synonyms = (item['synonyms'] as String? ?? '').trim();
    final tenseData = _parseTenseData(item);
    final relatedForms = _parseRelatedForms(item);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Image & Favorite Button ---
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child:
                        item['image_path'] != null && item['image_path'] != ""
                        ? Image.file(
                            File(item['image_path']),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: Colors.grey[200],
                            child: const Icon(
                              Icons.image,
                              size: 80,
                              color: Colors.grey,
                            ),
                          ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          isFav ? Icons.star : Icons.star_border,
                          color: isFav ? Colors.yellow : Colors.white,
                          size: 30,
                        ),
                        onPressed: () => _toggleFav(indexInList, item),
                      ),
                    ),
                  ),
                ],
              ),
              // --- Detail Content ---
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Header: Word, Type, Pronunciation, Audio ---
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: "${item['word'] ?? ''} ",
                                      style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: "(${item['word_type'] ?? ''})",
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w700,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (pronunciation.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  pronunciation,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.volume_up,
                            color: Colors.indigo,
                            size: 30,
                          ),
                          onPressed: () => _speak(
                            item['word'] ?? "",
                            item['word_type'] ?? "",
                            item['description'] ?? "",
                            examplesList,
                            synonyms,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 30),

                    // --- Meaning ---
                    const Text(
                      "Meaning",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['description'] ?? "No description provided.",
                      style: const TextStyle(fontSize: 18, height: 1.4),
                    ),
                    const SizedBox(height: 20),

                    // --- Synonyms ---
                    if (synonyms.isNotEmpty) ...[
                      const Text(
                        "Synonyms",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        synonyms,
                        style: const TextStyle(fontSize: 16, height: 1.3),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // --- Examples ---
                    if (examplesList.isNotEmpty) ...[
                      const Text(
                        "Examples",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...examplesList.asMap().entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            decoration: BoxDecoration(
                              border: const Border(
                                left: BorderSide(color: Colors.green, width: 4),
                              ),
                              color: Colors.green.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              entry.value,
                              style: const TextStyle(
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    if (relatedForms.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Related Forms",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _isRelatedFormsExpanded =
                                    !_isRelatedFormsExpanded;
                              });
                            },
                            icon: Icon(
                              _isRelatedFormsExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 20,
                            ),
                            label: Text(
                              _isRelatedFormsExpanded
                                  ? 'Hide related forms'
                                  : 'Show related forms',
                            ),
                          ),
                        ],
                      ),
                      if (_isRelatedFormsExpanded) ...[
                        const SizedBox(height: 10),
                        ...relatedForms.map(
                          (entry) => Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: _relatedFormsAccentColor,
                                  width: 4,
                                ),
                              ),
                              color: _relatedFormsAccentColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (entry['form']!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _relatedFormsAccentColor,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text.rich(
                                      TextSpan(
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                        children: [
                                          TextSpan(text: entry['form'] ?? ''),
                                          if (entry['type']!.isNotEmpty)
                                            TextSpan(
                                              text: ' (${entry['type']})',
                                              style: const TextStyle(
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (entry['meaning']!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('Definition: ${entry['meaning']}'),
                                ],
                                if (entry['example']!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Example: ${entry['example']}',
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],

                    // --- Tense / Conjugation ---
                    if (tenseData.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Tense / Form Conjugation",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _isTenseExpanded = !_isTenseExpanded;
                              });
                            },
                            icon: Icon(
                              _isTenseExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 20,
                            ),
                            label: Text(
                              _isTenseExpanded ? 'Hide tenses' : 'Show tenses',
                            ),
                          ),
                        ],
                      ),
                      if (_isTenseExpanded) ...[
                        const SizedBox(height: 10),
                        ..._tenseOrder
                            .where((t) => tenseData.containsKey(t))
                            .map(
                              (tense) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if ((tenseData[tense]?['conjugation'] ?? '')
                                        .isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _tenseAccentColor,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text.rich(
                                          TextSpan(
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                            children: [
                                              TextSpan(text: '$tense: '),
                                              TextSpan(
                                                text:
                                                    tenseData[tense]?['conjugation'] ??
                                                    '',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    if ((tenseData[tense]?['example'] ?? '')
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          8,
                                          10,
                                          8,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            left: BorderSide(
                                              color: _tenseAccentColor,
                                              width: 4,
                                            ),
                                          ),
                                          color: _tenseAccentColor
                                              .withOpacity(0.06),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          tenseData[tense]?['example'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        const SizedBox(height: 8),
                      ],
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
