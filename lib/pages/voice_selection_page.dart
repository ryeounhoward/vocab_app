import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceSelectionPage extends StatefulWidget {
  const VoiceSelectionPage({super.key});

  @override
  State<VoiceSelectionPage> createState() => _VoiceSelectionPageState();
}

class _VoiceSelectionPageState extends State<VoiceSelectionPage> {
  final FlutterTts flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _voices = [];
  String? _selectedVoiceName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVoicesAndCurrentSelection();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadVoicesAndCurrentSelection() async {
    // 1. Fetch voices from system
    List<dynamic> voices = await flutterTts.getVoices;

    // Optional: Filter for English only to make the list cleaner
    voices = voices
        .where((v) => v['locale'].toString().contains("en"))
        .toList();

    // 2. Fetch saved selection
    final prefs = await SharedPreferences.getInstance();
    String? savedVoice = prefs.getString('selected_voice_name');

    // 3. MOVE SELECTED TO TOP
    if (savedVoice != null) {
      int selectedIndex = voices.indexWhere((v) => v['name'] == savedVoice);
      if (selectedIndex != -1) {
        // Remove the selected voice from its current position
        var selectedVoiceData = voices.removeAt(selectedIndex);
        // Insert it at the very beginning (Index 0)
        voices.insert(0, selectedVoiceData);
      }
    }

    setState(() {
      _voices = voices;
      _selectedVoiceName = savedVoice;
      _isLoading = false;
    });
  }

  void _previewVoice(Map<String, String> voice) async {
    await flutterTts.setVoice(voice);
    await flutterTts.speak("Testing this voice.");
  }

  void _selectVoice(Map<String, String> voice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_voice_name', voice['name']!);
    await prefs.setString('selected_voice_locale', voice['locale']!);

    setState(() {
      _selectedVoiceName = voice['name'];
    });

    _previewVoice(voice);

    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Voice set to ${voice['name']}"),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select Voice"), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              thickness: 8.0,
              radius: const Radius.circular(10),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _voices.length,
                itemBuilder: (context, index) {
                  Map<String, String> voice = Map<String, String>.from(
                    _voices[index],
                  );
                  bool isSelected = _selectedVoiceName == voice['name'];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- ADDED: Header for the first item if it is selected ---
                      if (index == 0 && isSelected)
                        const Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            top: 16,
                            bottom: 8,
                          ),
                          child: Text(
                            "CURRENTLY SELECTED",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      // --- Header for the rest of the list ---
                      if (index == 1 && _selectedVoiceName != null)
                        const Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            top: 16,
                            bottom: 8,
                          ),
                          child: Text(
                            "ALL AVAILABLE VOICES",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),

                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: IconButton(
                          icon: Icon(
                            Icons.play_circle_fill,
                            color: isSelected
                                ? Colors.indigo
                                : Colors.grey[400],
                            size: 35,
                          ),
                          onPressed: () => _previewVoice(voice),
                        ),
                        title: Text(
                          voice['name']!,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? Colors.indigo : Colors.black87,
                          ),
                        ),
                        subtitle: Text(voice['locale']!),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 28,
                              )
                            : const Icon(
                                Icons.circle_outlined,
                                color: Colors.grey,
                              ),
                        onTap: () => _selectVoice(voice),
                      ),
                      if (index == 0 && isSelected)
                        const Divider(), // Separator after selected voice
                    ],
                  );
                },
              ),
            ),
    );
  }
}
