import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auto_backup_service.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

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

    double progress = 0;
    int sentBytes = 0;
    int totalBytes = 0;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            String mbStr = totalBytes > 0
                ? '${(sentBytes / (1024 * 1024)).toStringAsFixed(2)} MB / ${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB'
                : '';
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              content: SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Uploading backup to Google Drive...'),
                    const SizedBox(height: 18),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 12),
                    Text(mbStr, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final ok = await AutoBackupService.runNowInteractive(
      onProgress: (frac, sent, total) {
        progress = frac.clamp(0.0, 1.0);
        sentBytes = sent;
        totalBytes = total;
        if (mounted) {
          // ignore: use_build_context_synchronously
          (context as Element).markNeedsBuild();
        }
      },
    );

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
      body: ListView(
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
          const SizedBox(height: 18),
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
        ],
      ),
    );
  }
}
