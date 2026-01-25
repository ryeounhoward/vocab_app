import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

// SERVICES
import 'services/notification_service.dart';

// PAGES
import 'pages/menu_screen.dart';
import 'pages/settings_page.dart';
import 'pages/quiz_page.dart';
import 'pages/vocabulary_test_page.dart';
import 'pages/notes_page.dart'; // Import your new Notes Page

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    int count = inputData?['wordCount'] ?? 1;
    await NotificationService.init();
    await NotificationService.showWordNotification(count: count);
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Audio setup
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

  // Background services
  _initBackgroundServices();

  runApp(const MyApp());
}

Future<void> _initBackgroundServices() async {
  await NotificationService.init();
  try {
    Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  } catch (e) {
    debugPrint("Workmanager init failed: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService.navigatorKey,
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const MainContainer(),
      title: 'Vocabulary App',

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,

        // This is the correct name for version 11.5.0
        // Because you used 'as quill', you must use 'quill.FlutterQuillLocalizations'
        quill.FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US')],
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

  // Added NotesPage() to the list of screens
  final List<Widget> _pages = [
    const MenuPage(), // 0
    const QuizPage(), // 1
    const VocabularyTestPage(), // 2
    const NotesPage(), // 3: Added the Notes tab here
    const SettingsPage(), // 4
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.rate_review),
            label: 'Review',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.style), label: 'Practice'),
          BottomNavigationBarItem(icon: Icon(Icons.quiz), label: 'Quiz'),
          // ADDED THIS ITEM:
          BottomNavigationBarItem(
            icon: Icon(Icons.note_alt_outlined),
            label: 'Notes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
