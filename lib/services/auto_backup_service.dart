import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../pages/google_drive_service.dart';
import 'full_backup_service.dart';

enum AutoBackupFrequency { daily, weekly, monthly }

class AutoBackupService {
  static const String prefsEnabledKey = 'auto_full_backup_enabled';
  static const String prefsFrequencyKey = 'auto_full_backup_frequency';
  static const String prefsLastRunMsKey = 'auto_full_backup_last_run_ms';
  static const String prefsLastStatusKey = 'auto_full_backup_last_status';
  static const String prefsLastErrorKey = 'auto_full_backup_last_error';

  static const String workUniqueName = 'full_backup_task';
  static const String workTaskName = 'full_backup_periodic';

  static AutoBackupFrequency parseFrequency(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'weekly':
        return AutoBackupFrequency.weekly;
      case 'monthly':
        return AutoBackupFrequency.monthly;
      case 'daily':
      default:
        return AutoBackupFrequency.daily;
    }
  }

  static String frequencyLabel(AutoBackupFrequency freq) {
    switch (freq) {
      case AutoBackupFrequency.daily:
        return 'Daily';
      case AutoBackupFrequency.weekly:
        return 'Weekly';
      case AutoBackupFrequency.monthly:
        return 'Monthly';
    }
  }

  static String frequencyValue(AutoBackupFrequency freq) {
    switch (freq) {
      case AutoBackupFrequency.daily:
        return 'daily';
      case AutoBackupFrequency.weekly:
        return 'weekly';
      case AutoBackupFrequency.monthly:
        return 'monthly';
    }
  }

  static Duration durationFor(AutoBackupFrequency freq) {
    switch (freq) {
      case AutoBackupFrequency.daily:
        return const Duration(days: 1);
      case AutoBackupFrequency.weekly:
        return const Duration(days: 7);
      case AutoBackupFrequency.monthly:
        return const Duration(days: 30);
    }
  }

  static Future<void> applySchedulingFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(prefsEnabledKey) ?? false;
    if (!enabled) {
      await cancel();
      return;
    }

    final freq = parseFrequency(prefs.getString(prefsFrequencyKey));
    final duration = durationFor(freq);

    Duration initialDelay = Duration.zero;
    final lastRunMs = prefs.getInt(prefsLastRunMsKey);
    if (lastRunMs != null) {
      final lastRun = DateTime.fromMillisecondsSinceEpoch(lastRunMs);
      final nextDue = lastRun.add(duration);
      final diff = nextDue.difference(DateTime.now());
      if (!diff.isNegative) {
        initialDelay = diff;
      }
    }

    await Workmanager().registerPeriodicTask(
      workUniqueName,
      workTaskName,
      frequency: duration,
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );

    debugPrint(
      'Auto backup scheduled: ${frequencyLabel(freq)} (initialDelay: $initialDelay)',
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(workUniqueName);
  }

  static Future<bool> runNowInteractive({
    void Function(double fraction, int sentBytes, int totalBytes)? onProgress,
  }) async {
    return _runBackup(interactive: true, onProgress: onProgress);
  }

  static Future<bool> runInBackgroundNonInteractive() async {
    return _runBackup(interactive: false);
  }

  static Future<bool> _runBackup({
    required bool interactive,
    void Function(double fraction, int sentBytes, int totalBytes)? onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final drive = GoogleDriveService();
      final account = await drive.ensureSignedIn(interactive: interactive);
      if (account == null) {
        await _recordResult(
          prefs,
          status: 'skipped',
          error: 'Not signed in (or sign-in required).',
        );
        return false;
      }

      final fullBackup = FullBackupService();
      final zipFile = await fullBackup.buildFullBackupZipToTemp();
      if (zipFile == null) {
        await _recordResult(
          prefs,
          status: 'skipped',
          error: 'No data found to back up.',
        );
        return true;
      }

      await drive.uploadFile(
        zipFile,
        FullBackupService.fullBackupZipFileName,
        onProgress: onProgress,
        interactive: interactive,
      );

      await _recordResult(prefs, status: 'success');
      return true;
    } catch (e) {
      await _recordResult(prefs, status: 'error', error: e.toString());
      if (kDebugMode) {
        debugPrint('Auto backup failed: $e');
      }
      return false;
    }
  }

  static Future<void> _recordResult(
    SharedPreferences prefs, {
    required String status,
    String? error,
  }) async {
    await prefs.setInt(
      prefsLastRunMsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setString(prefsLastStatusKey, status);

    if (error != null && error.trim().isNotEmpty) {
      await prefs.setString(prefsLastErrorKey, error);
    } else {
      await prefs.remove(prefsLastErrorKey);
    }
  }
}
