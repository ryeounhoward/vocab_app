import 'dart:async';
import 'dart:convert'; // For GitHub API JSON
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http; // For update check
import 'package:ota_update/ota_update.dart'; // For auto-install

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appVersion = '';
  String _cacheSize = '0.00 MB';
  String _dataSize = '0.00 MB';

  // Update State
  bool _isCheckingUpdate = false;
  String? _latestVersion;
  String? _downloadUrl;

  static const String _creatorName = 'Ryeoun Howard';
  static const String _driveUrl =
      'https://drive.google.com/drive/folders/1zaqUPx0PLKP_AY5PDFy4QCqW0cOhWNjK?usp=sharing';
  static const String _facebookUrl = 'https://www.facebook.com/ryeounhoward23/';
  static const String _githubUrl = 'https://github.com/ryeounhoward/vocab_app';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadStorageInfo();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  // --- GITHUB UPDATE LOGIC ---
  Future<void> _checkForUpdateManual() async {
    setState(() => _isCheckingUpdate = true);
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/ryeounhoward/vocab_app/releases/latest',
        ),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String latestTag = data['tag_name'];
        String url = data['assets'][0]['browser_download_url'];

        if (latestTag != "v$_appVersion") {
          setState(() {
            _latestVersion = latestTag;
            _downloadUrl = url;
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You are on the latest version!')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to check for updates')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _confirmUpdate() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("Update to $_latestVersion?"),
        content: const Text(
          "The app will download the new version and automatically open the installer.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showDownloadProgressModal();
            },
            child: const Text("Download & Install"),
          ),
        ],
      ),
    );
  }

  void _showDownloadProgressModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _OtaDownloadDialog(url: _downloadUrl!),
    );
  }

  // --- STORAGE LOGIC ---
  Future<void> _loadStorageInfo() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final appDir = await getApplicationDocumentsDirectory();
      double cache = await _getTotalSize(cacheDir);
      double data = await _getTotalSize(appDir);
      if (!mounted) return;
      setState(() {
        _cacheSize = "${(cache / (1024 * 1024)).toStringAsFixed(2)} MB";
        _dataSize = "${(data / (1024 * 1024)).toStringAsFixed(2)} MB";
      });
    } catch (_) {}
  }

  Future<double> _getTotalSize(Directory dir) async {
    double totalSize = 0;
    try {
      if (dir.existsSync()) {
        dir.listSync(recursive: true).forEach((entity) {
          if (entity is File) totalSize += entity.lengthSync();
        });
      }
    } catch (_) {}
    return totalSize;
  }

  void _confirmClearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Clear Cache?"),
        content: const Text(
          "This will remove temporary files. Your saved notes and data will not be deleted.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _executeClearCache();
            },
            child: const Text(
              "Clear",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeClearCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
      _loadStorageInfo();
      if (!mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
    } catch (_) {}
  }

  Widget _buildInfoRow(String label, Widget valueWidget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          valueWidget,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Disclaimer
            const Text(
              'Disclaimer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This application was developed as a personal learning tool for practicing quizzes and keeping vocabulary notes. This app is intended for educational use only.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 24),

            // 2. App Information
            const Text(
              'App Information',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    'Created by',
                    Text(
                      _creatorName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),

                  // VERSION ROW
                  _buildInfoRow(
                    'Version',
                    Row(
                      children: [
                        Text(
                          _appVersion,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 12),
                        if (_latestVersion == null)
                          GestureDetector(
                            onTap: _isCheckingUpdate
                                ? null
                                : _checkForUpdateManual,
                            child: Text(
                              _isCheckingUpdate
                                  ? 'Checking...'
                                  : 'Check Update',
                              style: const TextStyle(
                                color: Colors.indigo,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: _confirmUpdate,
                            child: const Text(
                              'Update Available!',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  _buildInfoRow(
                    'App Data',
                    Text(
                      _dataSize,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  _buildInfoRow(
                    'Cache',
                    Row(
                      children: [
                        Text(
                          _cacheSize,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _confirmClearCache,
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),

            // 3. Social Links
            _buildLinkTile(
              'assets/images/Google_Drive_icon_(2020).svg',
              'Civil Service Reviewer',
              () => _openUrl(_driveUrl),
            ),
            _buildLinkTile(
              'assets/images/2023_Facebook_icon.svg',
              'Facebook Support',
              () => _openUrl(_facebookUrl),
            ),
            _buildLinkTile(
              'assets/images/Octicons-mark-github.svg',
              'GitHub Repository',
              () => _openUrl(_githubUrl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkTile(String iconPath, String title, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SvgPicture.asset(iconPath, width: 24, height: 24),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await url_launcher.launchUrl(uri)) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }
}

// --- SEPARATE DIALOG WIDGET TO FIX THE "ALREADY RUNNING" ERROR ---
class _OtaDownloadDialog extends StatefulWidget {
  final String url;
  const _OtaDownloadDialog({required this.url});

  @override
  State<_OtaDownloadDialog> createState() => _OtaDownloadDialogState();
}

class _OtaDownloadDialogState extends State<_OtaDownloadDialog> {
  double _progress = 0;
  String _status = "Starting download...";

  @override
  void initState() {
    super.initState();
    _startOta();
  }

  void _startOta() {
    try {
      OtaUpdate()
          .execute(widget.url, destinationFilename: 'app-release.apk')
          .listen(
            (OtaEvent event) {
              if (!mounted) return;
              setState(() {
                if (event.status == OtaStatus.DOWNLOADING) {
                  _progress = double.tryParse(event.value ?? "0") ?? 0;
                  _status = "Downloading...";
                } else if (event.status == OtaStatus.INSTALLING) {
                  _status = "Installing...";
                  Navigator.pop(context); // Close dialog
                } else if (event.status.toString().contains("ERROR")) {
                  _status = "Error: ${event.status}";
                }
              });
            },
            onError: (e) {
              if (mounted) setState(() => _status = "Download failed");
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
        ],
      ),
    );
  }
}
