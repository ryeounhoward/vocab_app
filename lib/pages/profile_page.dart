import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../database/db_helper.dart';
import 'google_drive_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final DBHelper _dbHelper = DBHelper();
  final GoogleDriveService _googleDriveService = GoogleDriveService();

  GoogleSignInAccount? _account;
  bool _isLoading = true;

  final TextEditingController _bioController = TextEditingController();
  String _savedBio = '';

  static const String _coverAssetPath = 'assets/images/bg.jpg';
  static const String _googleIconAssetPath =
      'assets/images/Google_Favicon_2025.svg.png';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
    });

    final account = await _googleDriveService.ensureSignedIn(
      interactive: false,
    );
    String? bio;
    if (account != null) {
      bio = await _dbHelper.getPreference(_bioKeyFor(account));
    }

    if (!mounted) return;
    setState(() {
      _account = account;
      _savedBio = (bio ?? '').toString();
      _bioController.text = _savedBio;
      _isLoading = false;
    });
  }

  Future<void> _refreshAccount() async {
    final account = await _googleDriveService.ensureSignedIn(
      interactive: false,
    );

    String? bio;
    if (account != null) {
      bio = await _dbHelper.getPreference(_bioKeyFor(account));
    }

    if (!mounted) return;
    setState(() {
      _account = account;
      _savedBio = (bio ?? '').toString();
      _bioController.text = _savedBio;
    });
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    final account = await _googleDriveService.ensureSignedIn(interactive: true);

    String? bio;
    if (account != null) {
      bio = await _dbHelper.getPreference(_bioKeyFor(account));
    }

    if (!mounted) return;
    setState(() {
      _account = account;
      _savedBio = (bio ?? '').toString();
      _bioController.text = _savedBio;
      _isLoading = false;
    });
  }

  Future<void> _logout() async {
    await _googleDriveService.signOut();
    if (!mounted) return;
    setState(() {
      _account = null;
      _savedBio = '';
      _bioController.text = '';
    });
  }

  Future<void> _saveBio() async {
    if (_account == null) return;
    final String bio = _bioController.text.trim();
    await _dbHelper.setPreference(_bioKeyFor(_account!), bio);
    if (!mounted) return;
    setState(() {
      _savedBio = bio;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bio saved')));
  }

  Future<void> _openBioEditor() async {
    final TextEditingController controller = TextEditingController(
      text: _savedBio,
    );

    final String? updated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Edit bio',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Write something about you...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, controller.text.trim());
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (updated == null) return;

    _bioController.text = updated;
    await _saveBio();
  }

  String _firstNameFor(GoogleSignInAccount account) {
    final displayName = account.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName.split(RegExp(r'\s+')).first;
    }

    final email = account.email.trim();
    final atIndex = email.indexOf('@');
    if (atIndex > 0) return email.substring(0, atIndex);
    return email;
  }

  String _lastNameFor(GoogleSignInAccount account) {
    final displayName = account.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      final parts = displayName
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return parts.sublist(1).join(' ');
      }
      return '';
    }
    return '';
  }

  String _fullNameFor(GoogleSignInAccount account) {
    final displayName = account.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final email = account.email.trim();
    final atIndex = email.indexOf('@');
    if (atIndex > 0) return email.substring(0, atIndex);
    return email;
  }

  String _bioKeyFor(GoogleSignInAccount account) {
    return 'profile_bio:${account.email.toLowerCase().trim()}';
  }

  Widget _buildAvatar(GoogleSignInAccount account) {
    final photoUrl = account.photoUrl;

    if (photoUrl == null || photoUrl.trim().isEmpty) {
      return const CircleAvatar(
        radius: 42,
        backgroundColor: Colors.white,
        child: Icon(Icons.person, size: 42, color: Colors.grey),
      );
    }

    return CircleAvatar(
      radius: 42,
      backgroundColor: Colors.white,
      child: ClipOval(
        child: Image.network(
          photoUrl,
          width: 84,
          height: 84,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const SizedBox(
              width: 84,
              height: 84,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(Icons.person, size: 42, color: Colors.grey),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoggedIn = _account != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), centerTitle: true),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: 220,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(_coverAssetPath, fit: BoxFit.cover),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Color(0xAA000000)],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _isLoading
                            ? const SizedBox(
                                height: 84,
                                width: 84,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              )
                            : (_account != null
                                  ? _buildAvatar(_account!)
                                  : const CircleAvatar(
                                      radius: 42,
                                      backgroundColor: Colors.white,
                                      child: Icon(
                                        Icons.person_outline,
                                        size: 42,
                                        color: Colors.grey,
                                      ),
                                    )),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : (_account != null
                              ? Text(
                                  _fullNameFor(_account!),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: _login,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Image.asset(
                                        _googleIconAssetPath,
                                        width: 22,
                                        height: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Sign in with Google',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                  ),
                ),
              ),
              if (isLoggedIn) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Bio',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                (_savedBio.trim().isNotEmpty)
                                    ? _savedBio.trim()
                                    : 'Tap edit to add your bio.',
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.35,
                                  color: _savedBio.trim().isNotEmpty
                                      ? Colors.black87
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: _logout,
                                icon: const Icon(Icons.logout),
                                label: const Text('Logout'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _openBioEditor,
                              borderRadius: BorderRadius.circular(18),
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.indigo,
                                child: const Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
