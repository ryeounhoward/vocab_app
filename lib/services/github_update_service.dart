import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
        final String latestTag = data['tag_name'];

        final assets = data['assets'];
        if (assets is! List || assets.isEmpty) return;

        final String downloadUrl = assets[0]['browser_download_url'];

        final PackageInfo packageInfo = await PackageInfo.fromPlatform();
        final String currentVersion = "v${packageInfo.version}";

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
        content: const Text(
          "The app will download the new version and automatically open the installer.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
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
    _startDownload();
  }

  void _startDownload() {
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
              if (!mounted) return;
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
