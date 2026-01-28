import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // <--- 1. NEW IMPORT ADDED HERE
import 'package:workmanager/workmanager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';

// SERVICES
import 'services/notification_service.dart';

// PAGES
import 'pages/menu_screen.dart';
import 'pages/settings_page.dart';
import 'pages/quiz_page.dart';
import 'pages/vocabulary_test_page.dart';
import 'pages/notes_page.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    int count = inputData?['wordCount'] ?? 1;
    await NotificationService.init();
    await NotificationService.showWordNotification(count: count);
    return Future.value(true);
  });
}

// ==========================================================
// GITHUB AUTO-UPDATE SERVICE
// ==========================================================
class GitHubUpdateService {
  static const String owner = "ryeounhoward";
  static const String repo = "vocab_app";
  static bool _isCheckInProgress = false;

  static Future<void> checkForUpdates(BuildContext context) async {
    if (_isCheckInProgress) return;
    _isCheckInProgress = true;

    final url = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String latestTag = data['tag_name'];
        String downloadUrl = data['assets'][0]['browser_download_url'];

        PackageInfo packageInfo = await PackageInfo.fromPlatform();
        String currentVersion = "v${packageInfo.version}";

        if (latestTag != currentVersion) {
          if (!context.mounted) return;
          _showUpdateNotice(context, latestTag, downloadUrl);
        }
      }
    } catch (e) {
      debugPrint("Update check failed: $e");
    } finally {
      _isCheckInProgress = false;
    }
  }

  static void _showUpdateNotice(
    BuildContext context,
    String version,
    String url,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text("Update to $version?"),
        content: Text(
          "The app will download the new version and automatically open the installer.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close notice
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => _DownloadDialog(url: url),
              );
            },
            child: const Text("Download & Install"),
          ),
        ],
      ),
    );
  }
}

class _DownloadDialog extends StatefulWidget {
  final String url;
  const _DownloadDialog({required this.url});

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double _progress = 0;
  String _status = "Initializing...";
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    startDownload();
  }

  void startDownload() {
    try {
      OtaUpdate()
          .execute(widget.url, destinationFilename: 'app-release.apk')
          .listen(
            (OtaEvent event) {
              if (!mounted) return;
              setState(() {
                switch (event.status) {
                  case OtaStatus.DOWNLOADING:
                    _status = "Downloading...";
                    _progress = double.tryParse(event.value ?? "0") ?? 0;
                    break;
                  case OtaStatus.INSTALLING:
                    _status = "Opening installer...";
                    Navigator.pop(context);
                    break;
                  case OtaStatus.ALREADY_RUNNING_ERROR:
                    _status = "Already downloading...";
                    break;
                  case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                    _status = "Permission Denied";
                    _hasError = true;
                    break;
                  default:
                    if (event.status.toString().contains("ERROR")) {
                      _status = "Error: ${event.status}";
                      _hasError = true;
                    }
                    break;
                }
              });
            },
            onError: (e) {
              setState(() {
                _status = "Download Failed";
                _hasError = true;
              });
            },
          );
    } catch (e) {
      debugPrint("OTA Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Downloading Update"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress / 100),
          const SizedBox(height: 20),
          Text("$_status (${_progress.toInt()}%)"),
          if (_hasError)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
        ],
      ),
    );
  }
}

// ==========================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.notification,
          contentType: AndroidContentType.sonification,
        ),
      ),
    );
  }

  await NotificationService.init();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  runApp(const MyApp());
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GitHubUpdateService.checkForUpdates(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const MenuPage(),
      const QuizPage(),
      VocabularyTestPage(parentTabIndex: _currentIndex, myTabIndex: 2),
      const NotesPage(),
      const SettingsPage(),
    ];

    // 2. WRAP WITH POPSCOPE TO PREVENT BLACK SCREEN
    return PopScope(
      canPop: false, // We handle the pop manually
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // If not on first tab, go to first tab
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
        // If already on first tab, exit to Android Home Screen
        else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: pages),
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
      ),
    );
  }
}
