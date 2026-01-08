import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../pages/review_page.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // This handles what happens when a user interact with the notification
  @pragma('vm:entry-point')
  static void onNotificationTap(NotificationResponse response) async {
    // 1. Immediately dismiss the notification from the tray
    if (response.id != null) {
      await _notificationsPlugin.cancel(response.id!);
    }

    if (response.payload == null) return;
    final data = jsonDecode(response.payload!);
    final dbHelper = DBHelper();

    // ACTION: "Add to favorites" button clicked
    if (response.actionId == 'fav_action') {
      // JUST add to database favorites silently.
      // Do NOT open the app (handled by showsUserInterface: false in trigger)
      await dbHelper.toggleFavorite(data['id'], true, data['table']);
      debugPrint("Silent add to favorites: ${data['id']}");
    }
    // ACTION: Main body clicked OR "Open" button clicked
    else {
      // 1. Add to favorites automatically because the user wanted to see it
      await dbHelper.toggleFavorite(data['id'], true, data['table']);

      // 2. Navigate the app to the specific card
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) =>
              ReviewPage(selectedId: data['id'], originTable: data['table']),
        ),
        (route) => route.isFirst, // Clear the stack to prevent navigation loops
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
      onDidReceiveNotificationResponse:
          onNotificationTap, // For foreground clicks
      onDidReceiveBackgroundNotificationResponse:
          onNotificationTap, // For clicks when app is closed
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
          "\n\nExample: ${examplesList[Random().nextInt(examplesList.length)]}";
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
              showsUserInterface: true, // This button OPENS the app
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'fav_action',
              'Add to favorites',
              showsUserInterface: false, // This button stays in BACKGROUND
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
