import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:vocab_app/pages/vocabulary_test_page.dart';
import 'package:workmanager/workmanager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'services/notification_service.dart';
// Import your pages for the main app
import 'pages/menu_screen.dart'; // Change to your actual file path
import 'pages/settings_page.dart'; // Change to your actual file path
import 'pages/quiz_page.dart'; // Change to your actual file path

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 1. Get Count
    int count = inputData?['wordCount'] ?? 1;

    // 2. Init Service
    await NotificationService.init();

    // 3. Show Notifications
    await NotificationService.showWordNotification(count: count);

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure audio so short sounds can mix with other apps (e.g., Spotify)
  if (!kIsWeb) {
    AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: <AVAudioSessionOptions>{AVAudioSessionOptions.mixWithOthers},
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
  }

  // Start UI first to avoid blocking first frame on startup
  runApp(const MyApp());

  // Initialize services in background to prevent splash freeze
  _initBackgroundServices();
}

Future<void> _initBackgroundServices() async {
  await NotificationService.init();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService
          .navigatorKey, // Important for clicking notifications
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const MainContainer(),
      title: 'Vocabulary',
    );
  }
}

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;

  // 1. ORDER FIXED: Matches the BottomNavigationBar below
  final List<Widget> _pages = [
    const MenuPage(), // Index 0: Review
    const QuizPage(), // Index 1: Practice (Flashcards?)
    const VocabularyTestPage(), // Index 2: The New Test
    const SettingsPage(), // Index 3: Settings
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The body updates based on _currentIndex
      body: _pages[_currentIndex],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo, // Highlight color
        unselectedItemColor: Colors.grey,
        items: const [
          // Index 0
          BottomNavigationBarItem(
            icon: Icon(Icons.rate_review),
            label: 'Review',
          ),
          // Index 1
          BottomNavigationBarItem(
            icon: Icon(Icons.style), // Changed icon to distinguish from Quiz
            label: 'Practice',
          ),
          // Index 2 (The New Quiz)
          BottomNavigationBarItem(
            icon: Icon(Icons.quiz), // Used the Quiz icon here
            label: 'Quiz',
          ),
          // Index 3
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
