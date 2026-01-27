import 'package:flutter/material.dart';

class DataRefreshSignal {
  // We use a static final so it is a single instance shared by the whole app
  static final ValueNotifier<int> refreshNotifier = ValueNotifier<int>(0);

  static void sendRefreshSignal() {
    print("🔔 Signal Sent!"); // Debug print
    refreshNotifier.value++;
  }
}
