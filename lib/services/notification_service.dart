import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart'; // Ensure this path is correct
import '../pages/review_page.dart'; // Ensure this path is correct
import '../pages/favorite_page.dart'; // Ensure this path is correct

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @pragma('vm:entry-point')
  static void onNotificationTap(NotificationResponse response) async {
    if (response.id != null) {
      await _notificationsPlugin.cancel(response.id!);
    }

    if (response.payload == null) return;

    final data = jsonDecode(response.payload!);
    final dbHelper = DBHelper();

    await Future.delayed(const Duration(milliseconds: 200));

    if (response.actionId == 'fav_action') {
      await dbHelper.toggleFavorite(data['id'], true, data['table']);
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const FavoritesPage()),
        (route) => route.isFirst,
      );
    } else {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) =>
              ReviewPage(selectedId: data['id'], originTable: data['table']),
        ),
        (route) => route.isFirst,
      );
    }
  }

  static Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: onNotificationTap,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'word_of_day_high_res',
            'Word of the Day Reminders',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
  }

  static Future<void> requestPermissions() async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  // --- UPDATED METHOD: Accepts count ---
  static Future<void> showWordNotification({int count = 1}) async {
    // Note: We don't check 'remind_active' here strictly,
    // because Workmanager usually handles that check before calling this.
    // However, if you call this manually, we can check.
    final prefs = await SharedPreferences.getInstance();
    // If it's a manual call and disabled, stop.
    // (Optional logic depending on how you want the "Test" button to behave)
    // if (!(prefs.getBool('remind_active') ?? false)) return;

    await _triggerNotification(count);
  }

  // Test button helper
  static Future<void> showTestNotification() async {
    // Default to 1 for quick test, or load from prefs
    final prefs = await SharedPreferences.getInstance();
    int count = prefs.getInt('remind_word_count') ?? 1;
    await _triggerNotification(count);
  }

  // --- MAIN LOGIC ---
  static Future<void> _triggerNotification(int count) async {
    final dbHelper = DBHelper();

    // 1. Get ALL words (or optimize this to get random limit in SQL)
    final List<Map<String, dynamic>> allWords = await dbHelper.queryAll(
      DBHelper.tableVocab,
    );

    if (allWords.isEmpty) return;

    // 2. Shuffle locally to get random words
    List<Map<String, dynamic>> shuffledWords = List.from(allWords)..shuffle();

    // 3. Take exactly 'count' words (e.g., 2 or 3)
    // Use .take() to avoid errors if count > total words
    final wordsToShow = shuffledWords.take(count).toList();

    // 4. Loop and send notification for EACH word
    for (int i = 0; i < wordsToShow.length; i++) {
      final wordItem = wordsToShow[i];
      await _sendSingleNotification(wordItem, i); // Pass index for unique ID

      // Optional: Tiny delay so they arrive in order
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  static Future<void> _sendSingleNotification(
    Map<String, dynamic> wordItem,
    int index,
  ) async {
    final dbHelper = DBHelper();
    String wordTitle =
        "${wordItem['word']} (${wordItem['word_type'] ?? 'word'})";
    String description = wordItem['description'] ?? "No meaning provided.";

    String exampleText = "";
    List<String> examplesList = (wordItem['examples'] as String? ?? "")
        .split('\n')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (examplesList.isNotEmpty) {
      exampleText =
          "\nExample: ${examplesList[Random().nextInt(examplesList.length)]}";
    }

    String payload = jsonEncode({
      'id': wordItem['id'],
      'table': DBHelper.tableVocab,
    });

    await dbHelper.insertNotification({
      'title': wordTitle,
      'body': description,
      'route': 'review',
      'route_args': payload,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'read': 0,
    });

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'word_of_day_high_res',
          'Word of the Day',
          importance: Importance.max,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(
            "$description$exampleText",
            contentTitle: wordTitle,
          ),
          playSound: true,
          // GROUP KEY ensures they stack nicely
          groupKey: 'com.vocab.daily_words',
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              'open_action',
              'Open',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'fav_action',
              'Add to favorites',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        );

    // generate a semi-random ID, but add index to ensure uniqueness in this batch
    int notificationId = Random().nextInt(10000) + index;

    await _notificationsPlugin.show(
      notificationId,
      wordTitle,
      description,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }
}
