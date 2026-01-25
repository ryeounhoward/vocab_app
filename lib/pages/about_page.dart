import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appVersion = '';
  String _cacheSize = '0.00 MB';
  String _dataSize = '0.00 MB';

  static const String _creatorName = 'Ryeoun Howard';
  static const String _driveUrl =
      'https://drive.google.com/drive/folders/1zaqUPx0PLKP_AY5PDFy4QCqW0cOhWNjK?usp=sharing';
  static const String _facebookUrl = 'https://www.facebook.com/ryeounhoward23/';
  static const String _githubUrl = 'https://github.com/ryeounhoward/vocab_app';

  static final DateTime _examDate = DateTime(2026, 3, 8);
  Duration _timeLeft = Duration.zero;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadStorageInfo();
    _startCountdown();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {}
  }

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

  // --- NEW: CONFIRMATION MODAL FOR CLEAR CACHE ---
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
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
    } catch (_) {}
  }

  void _startCountdown() {
    void update() {
      final diff = _examDate.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _timeLeft = diff.isNegative ? Duration.zero : diff);
    }

    update();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (t) => update(),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // Helper to build rows in the info section
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
    final int days = _timeLeft.inDays;
    final int hours = _timeLeft.inHours % 24;
    final int minutes = _timeLeft.inMinutes % 60;
    final int seconds = _timeLeft.inSeconds % 60;

    return Scaffold(
      appBar: AppBar(title: const Text('About'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Exam Countdown
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Exam Countdown',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildCountdownBox('$days', 'Days'),
                      const SizedBox(width: 8),
                      _buildCountdownBox('$hours', 'Hours'),
                      const SizedBox(width: 8),
                      _buildCountdownBox('$minutes', 'Mins'),
                      const SizedBox(width: 8),
                      _buildCountdownBox('$seconds', 'Secs'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. Disclaimer
            const Text(
              'Disclaimer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This application was developed as a personal learning tool for practicing quizzes and keeping vocabulary notes. The project prioritizes learning and experimentation over polished code structure or production-ready design. Some parts were implemented quickly to support the learning process. This app is intended for educational use only.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 24),

            // 3. App Information (Grouped for consistent spacing/color)
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
                  _buildInfoRow(
                    'Version',
                    Text(
                      _appVersion,
                      style: const TextStyle(fontWeight: FontWeight.w500),
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

            // 4. Social Links
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

  // --- UI HELPER WIDGETS ---

  Widget _buildCountdownBox(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.indigo,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.white70),
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
