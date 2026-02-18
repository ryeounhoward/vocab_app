import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path_provider/path_provider.dart'; // Required for temporary files

class DriveFileVersion {
  final String id;
  final String name;
  final int sizeBytes;
  final DateTime? modifiedTime;

  const DriveFileVersion({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.modifiedTime,
  });
}

class DriveFileRevision {
  final String id;
  final int sizeBytes;
  final DateTime? modifiedTime;
  final bool keepForever;

  const DriveFileRevision({
    required this.id,
    required this.sizeBytes,
    required this.modifiedTime,
    required this.keepForever,
  });
}

class GoogleDriveService {
  // Drive scopes are only requested when we actually need Drive.
  static const List<String> _driveScopes = [drive.DriveApi.driveFileScope];

  static final GoogleSignIn _googleSignIn = GoogleSignIn();

  // google_sign_in v6 does not expose a reliable “check granted scopes” API.
  // Cache when we have successfully requested Drive scope in this session.
  static bool _driveScopeGranted = false;

  static Object? _lastSignInError;
  static Object? get lastSignInError => _lastSignInError;

  int _parseSizeBytes(Object? raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  Stream<GoogleSignInAccount?> get onCurrentUserChanged =>
      _googleSignIn.onCurrentUserChanged;

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// Ensures the user is signed in
  Future<GoogleSignInAccount?> _ensureSignedIn({
    bool interactive = true,
  }) async {
    GoogleSignInAccount? account = _googleSignIn.currentUser;

    if (account != null) {
      _lastSignInError = null;
      return account;
    }

    try {
      account = await _googleSignIn.signInSilently(suppressErrors: true);
    } catch (e) {
      debugPrint("Silent sign-in failed: $e");
      _lastSignInError = e;
    }

    if (account == null && interactive) {
      try {
        account = await _googleSignIn.signIn();
      } on PlatformException catch (e) {
        _lastSignInError = e;
        if (e.code == 'sign_in_canceled') return null;
        debugPrint('Sign-in failed: $e');
        return null;
      } catch (e) {
        _lastSignInError = e;
        debugPrint("Sign-in failed: $e");
        return null;
      }
    }
    return account;
  }

  Future<bool> _ensureDriveScopes({required bool interactive}) async {
    if (_driveScopeGranted) return true;
    if (!interactive) return false;
    try {
      final granted = await _googleSignIn.requestScopes(_driveScopes);
      if (granted) _driveScopeGranted = true;
      return granted;
    } catch (e) {
      debugPrint('requestScopes failed: $e');
      return false;
    }
  }

  Future<T> _withDriveApiRetry<T>(
    Future<T> Function(drive.DriveApi api) action, {
    required bool interactive,
  }) async {
    final driveApi = await getDriveApi(interactive: interactive);
    if (driveApi == null) {
      throw StateError('Google Drive not available (not signed in)');
    }

    try {
      return await action(driveApi);
    } catch (e) {
      final String msg = e.toString();
      if (msg.contains('401') || msg.contains('unauthorized')) {
        try {
          await _googleSignIn.signInSilently(reAuthenticate: true);
        } catch (_) {}
        final retryApi = await getDriveApi(interactive: interactive);
        if (retryApi == null) rethrow;
        return await action(retryApi);
      }
      rethrow;
    }
  }

  Future<GoogleSignInAccount?> ensureSignedIn({bool interactive = true}) async {
    return _ensureSignedIn(interactive: interactive);
  }

  Future<drive.DriveApi?> getDriveApi({bool interactive = true}) async {
    try {
      final account = await _ensureSignedIn(interactive: interactive);
      if (account == null) return null;

      final hasScope = await _ensureDriveScopes(interactive: interactive);
      if (!hasScope) return null;

      final headers = await account.authHeaders;
      if (headers.isEmpty) return null;

      return drive.DriveApi(GoogleAuthClient(headers));
    } catch (e) {
      debugPrint("Drive API Error: $e");
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _driveScopeGranted = false;
  }

  // --- GENERIC FILE METHODS ---

  Future<List<DriveFileVersion>> listFileVersions(
    String fileName, {
    bool interactive = false,
    int pageSize = 50,
  }) async {
    return _withDriveApiRetry<List<DriveFileVersion>>((driveApi) async {
      final fileList = await driveApi.files.list(
        q: "name = '$fileName' and trashed = false",
        orderBy: 'modifiedTime desc',
        pageSize: pageSize,
        $fields: 'files(id, name, size, modifiedTime)',
      );

      final files = fileList.files ?? const <drive.File>[];
      return files
          .where((f) => (f.id ?? '').isNotEmpty)
          .map(
            (f) => DriveFileVersion(
              id: f.id!,
              name: f.name ?? fileName,
              sizeBytes: _parseSizeBytes(f.size),
              modifiedTime: f.modifiedTime,
            ),
          )
          .toList();
    }, interactive: interactive);
  }

  Future<List<DriveFileRevision>> listFileRevisionsByName(
    String fileName, {
    bool interactive = false,
    int pageSize = 100,
  }) async {
    return _withDriveApiRetry<List<DriveFileRevision>>((driveApi) async {
      final fileList = await driveApi.files.list(
        q: "name = '$fileName' and trashed = false",
        orderBy: 'modifiedTime desc',
        pageSize: 1,
        $fields: 'files(id)',
      );

      final files = fileList.files ?? const <drive.File>[];
      if (files.isEmpty || (files.first.id ?? '').isEmpty) {
        return const <DriveFileRevision>[];
      }

      final fileId = files.first.id!;

      final List<DriveFileRevision> out = <DriveFileRevision>[];
      String? pageToken;
      do {
        final revs = await driveApi.revisions.list(
          fileId,
          pageSize: pageSize,
          pageToken: pageToken,
          $fields:
              'nextPageToken,revisions(id, modifiedTime, size, keepForever)',
        );

        final items = revs.revisions ?? const <drive.Revision>[];
        out.addAll(
          items
              .where((r) => (r.id ?? '').isNotEmpty)
              .map(
                (r) => DriveFileRevision(
                  id: r.id!,
                  sizeBytes: _parseSizeBytes(r.size),
                  modifiedTime: r.modifiedTime,
                  keepForever: r.keepForever ?? false,
                ),
              ),
        );

        pageToken = revs.nextPageToken;
      } while (pageToken != null && pageToken!.isNotEmpty);

      // Display latest first (newest -> oldest).
      out.sort((a, b) {
        final at = a.modifiedTime?.millisecondsSinceEpoch ?? 0;
        final bt = b.modifiedTime?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      return out;
    }, interactive: interactive);
  }

  Future<void> setRevisionKeepForever(
    String fileName,
    String revisionId, {
    required bool keepForever,
    bool interactive = true,
  }) async {
    await _withDriveApiRetry<void>((driveApi) async {
      final fileList = await driveApi.files.list(
        q: "name = '$fileName' and trashed = false",
        orderBy: 'modifiedTime desc',
        pageSize: 1,
        $fields: 'files(id)',
      );
      final files = fileList.files ?? const <drive.File>[];
      if (files.isEmpty || (files.first.id ?? '').isEmpty) {
        throw StateError('Backup file not found in Drive');
      }
      final fileId = files.first.id!;

      final patch = drive.Revision()..keepForever = keepForever;
      await driveApi.revisions.update(patch, fileId, revisionId);
    }, interactive: interactive);
  }

  Future<void> uploadFile(
    File localFile,
    String fileName, {
    void Function(double fraction, int sentBytes, int totalBytes)? onProgress,
    bool interactive = true,
  }) async {
    await _withDriveApiRetry<void>((driveApi) async {
      final fileList = await driveApi.files.list(
        q: "name = '$fileName' and trashed = false",
        orderBy: 'modifiedTime desc',
        pageSize: 1,
        $fields: "files(id, modifiedTime)",
      );

      final driveFile = drive.File()..name = fileName;
      final int length = await localFile.length();

      // Wrap the file stream to report progress
      int sent = 0;
      final stream = localFile.openRead().transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, sink) {
            sent += chunk.length;
            onProgress?.call(sent / length, sent, length);
            sink.add(chunk);
          },
        ),
      );
      final media = drive.Media(stream, length);

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        final fileId = fileList.files!.first.id!;
        await driveApi.files.update(driveFile, fileId, uploadMedia: media);
        debugPrint("Updated existing file: $fileName");
      } else {
        await driveApi.files.create(driveFile, uploadMedia: media);
        debugPrint("Created new file: $fileName");
      }
      onProgress?.call(1.0, length, length);
    }, interactive: interactive);
  }

  Future<File?> downloadFile(
    String fileName,
    String savePath, {
    void Function(double fraction, int receivedBytes, int totalBytes)?
    onProgress,
    bool interactive = true,
  }) async {
    return _withDriveApiRetry<File?>((driveApi) async {
      final fileList = await driveApi.files.list(
        q: "name = '$fileName' and trashed = false",
        pageSize: 1,
        $fields: "files(id, size)",
      );

      if (fileList.files == null || fileList.files!.isEmpty) return null;

      final selected = fileList.files!.first;
      final fileId = selected.id!;

      final int totalBytes = _parseSizeBytes(selected.size);

      final drive.Media media =
          await driveApi.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final localFile = File(savePath);
      final sink = localFile.openWrite();
      int receivedBytes = 0;
      onProgress?.call(0.0, 0, totalBytes);
      try {
        await for (final chunk in media.stream) {
          receivedBytes += chunk.length;
          sink.add(chunk);

          final double fraction = totalBytes > 0
              ? (receivedBytes / totalBytes)
              : 0.0;
          onProgress?.call(fraction, receivedBytes, totalBytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final double finalFraction = totalBytes > 0 ? 1.0 : 0.0;
      onProgress?.call(finalFraction, receivedBytes, totalBytes);

      return localFile;
    }, interactive: interactive);
  }

  Future<File?> downloadFileRevisionByName(
    String fileName,
    String revisionId,
    String savePath, {
    void Function(double fraction, int receivedBytes, int totalBytes)?
    onProgress,
    bool interactive = true,
  }) async {
    return _withDriveApiRetry<File?>((driveApi) async {
      final fileList = await driveApi.files.list(
        q: "name = '$fileName' and trashed = false",
        pageSize: 1,
        $fields: "files(id)",
      );

      if (fileList.files == null || fileList.files!.isEmpty) return null;

      final fileId = fileList.files!.first.id;
      if (fileId == null || fileId.isEmpty) return null;

      int totalBytes = 0;
      try {
        final drive.Revision rev =
            await driveApi.revisions.get(fileId, revisionId, $fields: 'id,size')
                as drive.Revision;
        totalBytes = _parseSizeBytes(rev.size);
      } catch (_) {
        totalBytes = 0;
      }

      final drive.Media media =
          await driveApi.revisions.get(
                fileId,
                revisionId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final localFile = File(savePath);
      final sink = localFile.openWrite();
      int receivedBytes = 0;
      onProgress?.call(0.0, 0, totalBytes);
      try {
        await for (final chunk in media.stream) {
          receivedBytes += chunk.length;
          sink.add(chunk);

          final double fraction = totalBytes > 0
              ? (receivedBytes / totalBytes)
              : 0.0;
          onProgress?.call(fraction, receivedBytes, totalBytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final double finalFraction = totalBytes > 0 ? 1.0 : 0.0;
      onProgress?.call(finalFraction, receivedBytes, totalBytes);

      return localFile;
    }, interactive: interactive);
  }

  // --- BIO SPECIFIC METHODS ---

  /// Saves the Bio string to 'user_bio.txt' in Google Drive
  Future<void> uploadBioString(
    String bioContent, {
    bool interactive = true,
  }) async {
    final directory = await getTemporaryDirectory();
    final tempFile = File('${directory.path}/user_bio.txt');

    // Write the string to a temp file
    await tempFile.writeAsString(bioContent);

    // Upload that file
    await uploadFile(tempFile, 'user_bio.txt', interactive: interactive);
  }

  /// Downloads 'user_bio.txt' from Drive and returns the string content
  Future<String?> downloadBioString({bool interactive = false}) async {
    try {
      final directory = await getTemporaryDirectory();
      final savePath = '${directory.path}/user_bio.txt';

      final file = await downloadFile(
        'user_bio.txt',
        savePath,
        interactive: interactive,
      );

      if (file != null && await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('Could not download bio: $e');
    }
    return null;
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  GoogleAuthClient(this._headers);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}
