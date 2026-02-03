import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/google_drive_service.dart';
import '../services/auto_backup_service.dart';
import '../services/full_backup_service.dart';

class BackupPreferencesPage extends StatefulWidget {
  const BackupPreferencesPage({super.key});

  @override
  State<BackupPreferencesPage> createState() => _BackupPreferencesPageState();
}

class _BackupPreferencesPageState extends State<BackupPreferencesPage> {
  bool _enabled = false;
  AutoBackupFrequency _frequency = AutoBackupFrequency.daily;

  bool _isRunningNow = false;

  DateTime? _lastRun;
  String? _lastStatus;
  String? _lastError;

  bool _historyLoading = false;
  String? _historyError;
  List<DriveFileRevision> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadHistory(interactive: false);
  }

  String _formatDriveTime(DateTime? t) {
    if (t == null) return '-';
    final local = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatMb(int bytes) {
    if (bytes <= 0) return '-';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _loadHistory({required bool interactive}) async {
    if (_historyLoading) return;
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });

    try {
      final drive = GoogleDriveService();
      final items = await drive.listFileRevisionsByName(
        FullBackupService.fullBackupZipFileName,
        interactive: interactive,
        pageSize: 100,
      );
      if (!mounted) return;

      final sorted = List<DriveFileRevision>.from(items);
      sorted.sort((a, b) {
        final at = a.modifiedTime?.millisecondsSinceEpoch ?? 0;
        final bt = b.modifiedTime?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      setState(() {
        _history = sorted;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
      });
    }
  }

  static const String _driveVersionsInfoText =
      "Google Drive retains file versions for 30 days or up to 100 revisions. Versions older than this are automatically deleted to save space.";
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final enabled = prefs.getBool(AutoBackupService.prefsEnabledKey) ?? false;
    final freq = AutoBackupService.parseFrequency(
      prefs.getString(AutoBackupService.prefsFrequencyKey),
    );

    final lastRunMs = prefs.getInt(AutoBackupService.prefsLastRunMsKey);
    final lastRun = lastRunMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastRunMs);

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _frequency = freq;
      _lastRun = lastRun;
      _lastStatus = prefs.getString(AutoBackupService.prefsLastStatusKey);
      _lastError = prefs.getString(AutoBackupService.prefsLastErrorKey);
    });
  }

  Future<void> _persistAndSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AutoBackupService.prefsEnabledKey, _enabled);
    await prefs.setString(
      AutoBackupService.prefsFrequencyKey,
      AutoBackupService.frequencyValue(_frequency),
    );

    await AutoBackupService.applySchedulingFromPrefs();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _enabled
              ? 'Auto backup enabled (${AutoBackupService.frequencyLabel(_frequency)})'
              : 'Auto backup disabled',
        ),
      ),
    );

    await _load();
  }

  Future<void> _runNow() async {
    if (_isRunningNow) return;

    setState(() {
      _isRunningNow = true;
    });

    double progress = 0.01;
    String dialogMessage = 'Uploading to Google Drive (starting...)';

    int lastPercent = -1;
    void updateDialog(double fraction, String baseLabel) {
      final shownFraction = (fraction.isNaN || fraction < 0.01)
          ? 0.01
          : fraction.clamp(0.01, 1.0);
      final int percent = (shownFraction * 100).round();
      if (percent == lastPercent) return;
      lastPercent = percent;
      progress = shownFraction;
      dialogMessage = '$baseLabel ($percent%)';
    }

    StateSetter? dialogSetState;
    bool dialogOpen = true;
    bool dialogBuiltOnce = false;
    final dialogReady = Completer<void>();

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            dialogSetState = setState;
            if (!dialogBuiltOnce) {
              dialogBuiltOnce = true;
              if (!dialogReady.isCompleted) dialogReady.complete();
            }
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dialogMessage, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(value: progress, minHeight: 6),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // Ensure the dialog is mounted before starting upload,
    // otherwise early progress events can be lost.
    await dialogReady.future;

    final ok = await AutoBackupService.runNowInteractive(
      onProgress: (frac, sent, total) {
        if (!dialogOpen) return;
        final setter = dialogSetState;
        if (setter == null) return;
        setter(() {
          final String baseLabel = total > 0
              ? 'Uploading to Google Drive (${(sent / (1024 * 1024)).toStringAsFixed(2)} MB / ${(total / (1024 * 1024)).toStringAsFixed(2)} MB)'
              : 'Uploading to Google Drive';
          updateDialog(frac, baseLabel);
        });
      },
    );

    dialogOpen = false;
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    setState(() {
      _isRunningNow = false;
    });

    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Backup uploaded to Google Drive.' : 'Backup failed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auto Full Backup'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable automatic backup'),
              subtitle: const Text('Uploads full ZIP backup to Google Drive'),
              trailing: Switch(
                value: _enabled,
                activeThumbColor: Colors.indigo,
                onChanged: (v) async {
                  setState(() => _enabled = v);
                  await _persistAndSchedule();
                },
              ),
            ),
            const Divider(),
            const ListTile(
              title: Text('Backup frequency'),
              subtitle: Text('Choose how often to auto upload'),
              contentPadding: EdgeInsets.zero,
            ),
            DropdownMenu<AutoBackupFrequency>(
              width: MediaQuery.of(context).size.width - 40,
              initialSelection: _frequency,
              onSelected: (value) async {
                if (value == null) return;
                setState(() => _frequency = value);
                await _persistAndSchedule();
              },
              dropdownMenuEntries: AutoBackupFrequency.values
                  .map(
                    (f) => DropdownMenuEntry(
                      value: f,
                      label: AutoBackupService.frequencyLabel(f),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isRunningNow ? null : _runNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                child: _isRunningNow
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Backup now'),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              color: Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last backup: ${_lastRun == null ? 'Never' : _lastRun.toString()}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text('Status: ${_lastStatus ?? '-'}'),
                    if ((_lastError ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Error: $_lastError',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Note: Auto backup needs you to sign in to Google once and grant Drive access.\nBackground runs may be skipped if Google requires interaction.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Google Drive backup history',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _historyLoading
                      ? null
                      : () => _loadHistory(interactive: true),
                  icon: _historyLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              _driveVersionsInfoText,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            if ((_historyError ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _historyError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            if (_history.isEmpty && !_historyLoading)
              const Text(
                'No backups found in Drive yet. Tap Refresh after signing in.',
                style: TextStyle(color: Colors.black54),
              )
            else
              SizedBox(
                height: 280,
                child: Card(
                  elevation: 0,
                  color: Colors.grey.shade50,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      final titlePrefix = '#${index + 1}';
                      return ListTile(
                        dense: true,
                        title: Text(
                          '$titlePrefix  ${_formatDriveTime(item.modifiedTime)}',
                        ),
                        subtitle: Text(
                          'Size: ${_formatMb(item.sizeBytes)}${item.keepForever ? '  •  Kept forever' : ''}',
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Options',
                          onSelected: (value) async {
                            if (value == 'keep' || value == 'unkeep') {
                              final keep = value == 'keep';
                              try {
                                await GoogleDriveService()
                                    .setRevisionKeepForever(
                                      FullBackupService.fullBackupZipFileName,
                                      item.id,
                                      keepForever: keep,
                                      interactive: true,
                                    );
                                if (!mounted) return;
                                await _loadHistory(interactive: false);
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed: $e')),
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: item.keepForever ? 'unkeep' : 'keep',
                              child: Text(
                                item.keepForever
                                    ? 'Remove keep forever'
                                    : 'Keep forever',
                              ),
                            ),
                          ],
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.keepForever)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.lock, size: 18),
                                )
                              else
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.history, size: 18),
                                ),
                              const Icon(Icons.more_vert, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
