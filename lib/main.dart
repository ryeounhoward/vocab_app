import 'package:flutter/material.dart';
import 'package:vocab_app/pages/menu_screen.dart';
import 'pages/settings_page.dart';
import 'pages/quiz_page.dart';
import 'package:workmanager/workmanager.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await NotificationService.init();
    await NotificationService.showWordNotification();
    return Future.value(true);
  });
}

void main() async {
  // 1. Ensure Flutter is ready
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Notification Service
  await NotificationService.init();

  // 3. Initialize Workmanager for background tasks
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // 4. Start the App
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // This allows the NotificationService to control navigation
      navigatorKey: NotificationService.navigatorKey,
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

  final List<Widget> _pages = [
    const MenuPage(),
    const QuizPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.rate_review),
            label: 'Review',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.quiz), label: 'Practice'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
