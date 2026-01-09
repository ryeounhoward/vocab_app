import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../pages/review_page.dart';
import '../pages/favorite_page.dart'; // Import your FavoritesPage

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @pragma('vm:entry-point')
  static void onNotificationTap(NotificationResponse response) async {
    // Dismiss notification
    if (response.id != null) {
      await _notificationsPlugin.cancel(response.id!);
    }

    if (response.payload == null) return;

    final data = jsonDecode(response.payload!);
    final dbHelper = DBHelper();

    // Small delay to ensure the app context is ready after waking up
    await Future.delayed(const Duration(milliseconds: 200));

    // --- ACTION: "Add to favorites" button clicked ---
    if (response.actionId == 'fav_action') {
      // 1. Add to database
      await dbHelper.toggleFavorite(data['id'], true, data['table']);
      debugPrint("Added to favorites and opening Favorites Page");

      // 2. Open the App directly to FavoritesPage
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const FavoritesPage()),
        (route) => route.isFirst,
      );
    }
    // --- ACTION: Main body clicked OR "Open" button clicked ---
    else {
      // Navigate to ReviewPage to see the specific word
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

  static Future<void> showWordNotification() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('remind_active') ?? false)) return;
    await _triggerNotification();
  }

  static Future<void> showTestNotification() async {
    await _triggerNotification();
  }

  static Future<void> _triggerNotification() async {
    final dbHelper = DBHelper();
    final List<Map<String, dynamic>> words = await dbHelper.queryAll(
      DBHelper.tableVocab,
    );
    if (words.isEmpty) return;

    final wordItem = words[Random().nextInt(words.length)];

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
              // 1. CHANGED THIS TO TRUE
              // This is required to open the app and show the FavoritesPage
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        );

    await _notificationsPlugin.show(
      Random().nextInt(100000),
      wordTitle,
      description,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }
}
