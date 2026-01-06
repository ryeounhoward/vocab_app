import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../database/db_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final dbHelper = DBHelper();
  final FlutterTts flutterTts = FlutterTts();
  List<Map<String, dynamic>> _vocabList = [];
  bool _isLoading = true;
  int? _flippedIndex;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initTts();
  }

  void _initTts() async {
    final prefs = await SharedPreferences.getInstance();
    String? voiceName = prefs.getString('selected_voice_name');
    String? voiceLocale = prefs.getString('selected_voice_locale');

    if (voiceName != null && voiceLocale != null) {
      await flutterTts.setVoice({"name": voiceName, "locale": voiceLocale});
    } else {
      await flutterTts.setLanguage("en-US");
    }

    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  void _loadData() async {
    final data = await dbHelper.queryAll();
    List<Map<String, dynamic>> shuffledList = List.from(data);
    shuffledList.shuffle();
    setState(() {
      _vocabList = shuffledList;
      _isLoading = false;
    });
  }

  Future<void> _speak(String text) async {
    String textToRead = text;
    if (textToRead == "No description available.") {
      textToRead = "There is no meaning available for this word.";
    }
    await flutterTts.speak(textToRead);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_vocabList.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text("No vocabulary found. Please add some first."),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Practice"), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "Tap the card to see the answer.\nSwipe to move to the next word.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            Expanded(
              child: PageView.builder(
                itemCount: _vocabList.length,
                controller: PageController(viewportFraction: 0.85),
                onPageChanged: (index) {
                  setState(() {
                    _flippedIndex = null;
                    flutterTts.stop();
                  });
                },
                itemBuilder: (context, index) {
                  final item = _vocabList[index];
                  bool isThisCardFlipped = _flippedIndex == index;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        flutterTts.stop();
                        if (_flippedIndex == index) {
                          _flippedIndex = null;
                        } else {
                          _flippedIndex = index;
                        }
                      });
                    },
                    child: _buildFlipCard(item, isThisCardFlipped),
                  );
                },
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipCard(Map<String, dynamic> item, bool isFlipped) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final rotate = Tween(begin: 3.14, end: 0.0).animate(animation);
        return AnimatedBuilder(
          animation: rotate,
          child: child,
          builder: (context, child) {
            final isBack = (rotate.value > 3.14 / 2);
            return Transform(
              transform: Matrix4.rotationY(rotate.value),
              alignment: Alignment.center,
              child: isBack ? Container() : child,
            );
          },
        );
      },
      child: isFlipped
          ? _buildCardSide(
              key: const ValueKey(true),
              content: item['word'] ?? "No word",
              // Changed item['type'] to item['word_type']
              subContent: item['word_type'] != null && item['word_type'] != ""
                  ? "(${item['word_type']})"
                  : null,
              color: Colors.indigo,
              textColor: Colors.white,
            )
          : _buildCardSide(
              key: const ValueKey(false),
              content: item['description'] != null && item['description'] != ""
                  ? item['description']
                  : "No description available.",
              subContent: null,
              color: Colors.white,
              textColor: Colors.black87,
            ),
    );
  }

  Widget _buildCardSide({
    required Key key,
    required String content,
    String? subContent,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 5),
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              // ignore: deprecated_member_use
              icon: Icon(Icons.volume_up, color: textColor.withOpacity(0.6)),
              onPressed: () => _speak(content),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    content,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  if (subContent != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subContent,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        // ignore: deprecated_member_use
                        color: textColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
