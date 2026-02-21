import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../database/db_helper.dart';
import 'google_drive_Service.dart';
import 'review_page.dart';
import 'favorite_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final DBHelper _dbHelper = DBHelper();
  final GoogleDriveService _googleDriveService = GoogleDriveService();

  GoogleSignInAccount? _account;

  // Start as FALSE so we don't show spinner if data is already there
  bool _isLoading = false;
  bool _isSavingBio = false;
  bool _isLoadingBio = false;
  bool _isLoadingNotifications = false;
  List<Map<String, dynamic>> _notifications = <Map<String, dynamic>>[];
  int _notificationPage = 0;
  static const int _notificationsPerPage = 5;

  StreamSubscription<GoogleSignInAccount?>? _accountSub;
  final TextEditingController _bioController = TextEditingController();
  String _savedBio = '';

  static const String _coverAssetPath = 'assets/images/bg.jpg';
  static const String _googleIconAssetPath =
      'assets/images/Google_Favicon_2025.svg.png';

  @override
  void initState() {
    super.initState();

    // 1. SETUP LISTENER
    _accountSub = _googleDriveService.onCurrentUserChanged.listen((account) {
      _handleAccountChanged(account, silent: true);
    });

    // 2. CHECK IMMEDIATE CACHE (THE FIX)
    final existingUser = _googleDriveService.currentUser;

    if (existingUser != null) {
      // If we already have data, show it INSTANTLY.
      _account = existingUser;
      _isLoading = false;
      // Load bio from local cache only; Drive sync happens on pull-to-refresh.
      _handleAccountChanged(existingUser, silent: true);
      _loadNotifications();
    } else {
      // Only show loading if we really don't have a user yet
      _loadProfile();
      _loadNotifications();
    }
  }

  @override
  void dispose() {
    _accountSub?.cancel();
    _bioController.dispose();
    super.dispose();
  }

  // Modified to accept 'silent' parameter
  Future<void> _handleAccountChanged(
    GoogleSignInAccount? account, {
    bool silent = false,
  }) async {
    if (!mounted) return;

    if (account == null) {
      setState(() {
        _account = null;
        _savedBio = '';
        _bioController.text = '';
        _isLoading = false;
        _isLoadingBio = false;
      });
      return;
    }

    // Only show the big loading spinner if it's NOT a silent update
    if (!silent) {
      setState(() {
        _account = account;
        _isLoading = true;
      });
    } else {
      // If silent, just update the account variable so UI shows Name/Pic immediately
      setState(() {
        _account = account;
        // Sign-in succeeded; stop showing the full-screen loader immediately.
        _isLoading = false;
      });
    }

    // Load bio from local DB cache (fast, no Google UI/overlays).
    final localBio = await _dbHelper.getPreference(_bioKeyFor(account));
    final displayBio = (localBio ?? '').toString();

    if (!mounted) return;
    setState(() {
      _savedBio = displayBio;
      _bioController.text = displayBio;
      _isLoading = false;
      _isLoadingBio = false;
    });
  }

  Future<void> _syncBioFromDrive({bool showLoading = true}) async {
    final account = _account;
    if (account == null) return;

    if (showLoading && mounted) {
      setState(() {
        _isLoadingBio = true;
      });
    }

    try {
      // Non-interactive to avoid launching extra Google consent UI.
      final driveBio = await _googleDriveService.downloadBioString(
        interactive: false,
      );
      if (driveBio != null) {
        await _dbHelper.setPreference(_bioKeyFor(account), driveBio);
        if (!mounted) return;
        setState(() {
          _savedBio = driveBio;
          _bioController.text = driveBio;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBio = false;
        });
      }
    }
  }

  Future<void> _loadProfile() async {
    if (mounted) setState(() => _isLoading = true);
    // Check if we are already signed in silently
    final account = await _googleDriveService.ensureSignedIn(
      interactive: false,
    );

    // If ensureSignedIn returns null, we aren't logged in, so we stop loading
    if (account == null) {
      if (mounted) setState(() => _isLoading = false);
    }
    // _handleAccountChanged is called by the listener automatically,
    // or we can call it here manually if needed:
    if (account != null) {
      await _handleAccountChanged(account, silent: true);
    }
  }

  Future<void> _refreshProfile() async {
    await _loadProfile();
    await _syncBioFromDrive(showLoading: false);
    await _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoadingNotifications = true);
    final rows = await _dbHelper.getAllNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = rows;
      _isLoadingNotifications = false;
    });
  }

  Future<void> _markAllNotificationsRead() async {
    await _dbHelper.markAllNotificationsRead();
    await _loadNotifications();
  }

  void _nextNotificationPage() {
    final totalPages = _totalNotificationPages();
    if (_notificationPage + 1 >= totalPages) return;
    setState(() => _notificationPage += 1);
  }

  void _previousNotificationPage() {
    if (_notificationPage == 0) return;
    setState(() => _notificationPage -= 1);
  }

  int _totalNotificationPages() {
    if (_notifications.isEmpty) return 1;
    return (_notifications.length / _notificationsPerPage).ceil();
  }

  List<Map<String, dynamic>> _currentNotificationPageItems() {
    final start = _notificationPage * _notificationsPerPage;
    if (start >= _notifications.length) return <Map<String, dynamic>>[];
    final end = (start + _notificationsPerPage).clamp(0, _notifications.length);
    return _notifications.sublist(start, end);
  }

  int _unreadNotificationCount() {
    return _notifications
        .where((notification) => (notification['read'] ?? 0) != 1)
        .length;
  }

  Future<void> _openNotification(Map<String, dynamic> notification) async {
    final int? id = notification['id'] as int?;
    if (id != null) {
      await _dbHelper.markNotificationRead(id);
    }

    final route = (notification['route'] ?? '').toString();
    final routeArgs = (notification['route_args'] ?? '').toString();
    if (route == 'review' && routeArgs.isNotEmpty) {
      final data = jsonDecode(routeArgs);
      final int? itemId = data['id'] as int?;
      final String? table = data['table'] as String?;
      if (itemId != null && table != null) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ReviewPage(selectedId: itemId, originTable: table),
          ),
        );
      }
    } else if (route == 'favorites') {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const FavoritesPage()),
      );
    }

    await _loadNotifications();
  }

  Future<void> _login() async {
    setState(() => _isLoading = true); // Manual login needs spinner

    final account = await _googleDriveService.ensureSignedIn(interactive: true);

    if (account == null) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      final err = GoogleDriveService.lastSignInError;
      final msg = (err == null) ? '' : err.toString();
      final bool looksDeveloperError = msg.contains('ApiException: 10');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            looksDeveloperError
                ? 'Google Sign-In Error (SHA-1). Check Console.'
                : 'Sign-in cancelled.',
          ),
        ),
      );
      return;
    }
    // Listener will handle the rest
  }

  Future<void> _logout() async {
    await _googleDriveService.signOut();
    if (!mounted) return;
    setState(() {
      _account = null;
      _savedBio = '';
      _bioController.text = '';
      _isLoading = false;
    });
  }

  Future<void> _saveBio() async {
    if (_account == null) return;
    final String bio = _bioController.text.trim();

    setState(() => _isSavingBio = true);

    try {
      await _dbHelper.setPreference(_bioKeyFor(_account!), bio);
      await _googleDriveService.uploadBioString(bio);

      if (!mounted) return;
      setState(() {
        _savedBio = bio;
        _isSavingBio = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bio saved to Google Drive')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingBio = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
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
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
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

    if (updated != null) {
      _bioController.text = updated;
      await _saveBio();
    }
  }

  String _fullNameFor(GoogleSignInAccount account) {
    final displayName = account.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return account.email;
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
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.person, size: 42, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only show "Not Logged In" state if account is null AND we are not loading
    final bool isLoggedIn = _account != null;
    final bool isSigningInOrRestoring = _isLoading && !isLoggedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), centerTitle: true),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshProfile,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // 1. Header
              SizedBox(
                height: 220,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      _coverAssetPath,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: Colors.blueGrey),
                    ),
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
                        child: isLoggedIn
                            ? _buildAvatar(_account!)
                            : const CircleAvatar(
                                radius: 42,
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.person_outline,
                                  size: 42,
                                  color: Colors.grey,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Name Card or Login Button
              if (isLoggedIn)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: Text(
                      _fullNameFor(_account!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton(
                    onPressed: isSigningInOrRestoring ? null : _login,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isSigningInOrRestoring)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Image.asset(
                                _googleIconAssetPath,
                                width: 22,
                                height: 22,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.login),
                              ),
                            const SizedBox(width: 10),
                            Text(
                              isSigningInOrRestoring
                                  ? 'Signing in…'
                                  : 'Sign in with Google',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Back up and sync your data.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),

              // 3. Bio Card
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

                              (_isSavingBio || _isLoadingBio)
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Text(
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
                              onTap: (_isSavingBio || _isLoadingBio)
                                  ? null
                                  : _openBioEditor,
                              borderRadius: BorderRadius.circular(18),
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: (_isSavingBio || _isLoadingBio)
                                    ? Colors.grey
                                    : Colors.indigo,
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

              // 4. Notifications
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Notifications',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _notifications.isEmpty
                                  ? null
                                  : _markAllNotificationsRead,
                              child: Text(
                                _unreadNotificationCount() > 0
                                    ? 'Mark all read (${_unreadNotificationCount()})'
                                    : 'Mark all read',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_isLoadingNotifications)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (_notifications.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 16,
                          ),
                          child: Text(
                            'No notifications yet.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        Column(
                          children: [
                            ..._currentNotificationPageItems().map((
                              notification,
                            ) {
                              final String title = (notification['title'] ?? '')
                                  .toString();
                              final String body = (notification['body'] ?? '')
                                  .toString();
                              final bool isRead =
                                  (notification['read'] ?? 0) == 1;
                              return Column(
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () =>
                                          _openNotification(notification),
                                      hoverColor: Colors.grey.withOpacity(0.08),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                              ),
                                          title: Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: isRead
                                                  ? FontWeight.w500
                                                  : FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: Text(
                                            body,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          trailing: isRead
                                              ? null
                                              : const Icon(
                                                  Icons.circle,
                                                  size: 8,
                                                  color: Colors.indigo,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 1),
                                ],
                              );
                            }),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _notificationPage == 0
                                          ? null
                                          : _previousNotificationPage,
                                      child: const Text('Previous'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed:
                                          _notificationPage + 1 >=
                                              _totalNotificationPages()
                                          ? null
                                          : _nextNotificationPage,
                                      child: const Text('Next'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Page ${_notificationPage + 1} of ${_totalNotificationPages()}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
