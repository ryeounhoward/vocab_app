import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:flutter_svg/flutter_svg.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appVersion = '';
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
    _startCountdown();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = info.version;
      });
    } catch (_) {
      // If something goes wrong, leave version empty.
    }
  }

  void _startCountdown() {
    void update() {
      final now = DateTime.now();
      final diff = _examDate.difference(now);
      if (!mounted) return;
      setState(() {
        _timeLeft = diff.isNegative ? Duration.zero : diff;
      });
    }

    update();
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer timer) => update(),
    );
  }

  Future<void> _openDriveLink(BuildContext context) async {
    final uri = Uri.parse(_driveUrl);
    if (!await url_launcher.launchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Drive link.')),
      );
    }
  }

  Future<void> _openFacebookLink(BuildContext context) async {
    final uri = Uri.parse(_facebookUrl);
    if (!await url_launcher.launchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Facebook page.')),
      );
    }
  }

  Future<void> _openGithubLink(BuildContext context) async {
    final uri = Uri.parse(_githubUrl);
    if (!await url_launcher.launchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open GitHub repository.')),
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Widget _buildCountdownTile(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.indigo,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final versionText = _appVersion.isEmpty ? 'Loading...' : _appVersion;
    final int days = _timeLeft.inDays;
    final int hours = _timeLeft.inHours % 24;
    final int minutes = _timeLeft.inMinutes % 60;
    final int seconds = _timeLeft.inSeconds % 60;
    final bool examReached = _timeLeft == Duration.zero;

    return Scaffold(
      appBar: AppBar(title: const Text('About'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
                  if (examReached)
                    const Text(
                      'Exam day has arrived!',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.black87,
                      ),
                    )
                  else
                    Row(
                      children: [
                        _buildCountdownTile('$days', 'Days'),
                        const SizedBox(width: 8),
                        _buildCountdownTile('$hours', 'Hours'),
                        const SizedBox(width: 8),
                        _buildCountdownTile('$minutes', 'Minutes'),
                        const SizedBox(width: 8),
                        _buildCountdownTile('$seconds', 'Seconds'),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Disclaimer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'This application was developed as a personal learning tool for practicing quizzes and keeping vocabulary notes. The project prioritizes learning and experimentation over polished code structure or production-ready design. Some parts were implemented quickly to support the learning process. This app is intended for educational use only.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Created by $_creatorName',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text('Version: $versionText', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            ListTile(
              leading: SvgPicture.asset(
                'assets/images/Google_Drive_icon_(2020).svg',
                width: 24,
                height: 24,
              ),
              title: const Text('Civil Service Reviewer (Google Drive)'),
              subtitle: const Text('Open the reviewer files in Google Drive'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openDriveLink(context),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: SvgPicture.asset(
                'assets/images/2023_Facebook_icon.svg',
                width: 24,
                height: 24,
              ),
              title: const Text('Facebook Support'),
              subtitle: const Text('Message on Facebook for help or support'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openFacebookLink(context),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: SvgPicture.asset(
                'assets/images/Octicons-mark-github.svg',
                width: 24,
                height: 24,
              ),
              title: const Text('GitHub Repository'),
              subtitle: const Text('View source code and contribute on GitHub'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openGithubLink(context),
            ),
          ],
        ),
      ),
    );
  }
}
