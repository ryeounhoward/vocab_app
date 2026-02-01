import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class GoogleDriveService {
  // Scopes required for the app
  static const List<String> _scopes = [drive.DriveApi.driveFileScope];

  // Initialize GoogleSignIn (v6 style)
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  /// 1. Ensures the user is signed in (Hidden Helper)
  Future<GoogleSignInAccount?> _ensureSignedIn({
    bool interactive = true,
  }) async {
    GoogleSignInAccount? account = _googleSignIn.currentUser;

    if (account != null) return account;

    // A. Try Silent Sign-In (v6 method)
    try {
      account = await _googleSignIn.signInSilently();
    } catch (e) {
      debugPrint("Silent sign-in failed: $e");
    }

    // B. Interactive Sign-In
    if (account == null && interactive) {
      try {
        account = await _googleSignIn.signIn();
      } catch (e) {
        debugPrint("User likely cancelled sign-in: $e");
        return null;
      }
    }

    return account;
  }

  // 2. Public method to ensure sign-in (for UI checks)
  Future<GoogleSignInAccount?> ensureSignedIn({bool interactive = true}) async {
    return _ensureSignedIn(interactive: interactive);
  }

  // 3. Get Authenticated Drive API Client
  Future<drive.DriveApi?> getDriveApi() async {
    try {
      final GoogleSignInAccount? account = await _ensureSignedIn(
        interactive: true,
      );
      if (account == null) return null;

      // C. Get Headers (v6 style - this works!)
      final Map<String, String> headers = await account.authHeaders;

      if (headers.isEmpty) return null;

      // Construct the authenticated client
      return drive.DriveApi(GoogleAuthClient(headers));
    } catch (e) {
      debugPrint("Drive API Error: $e");
      // If we get a 401, it might mean we need to sign in again
      if (e.toString().contains("401")) {
        await _googleSignIn.signOut();
      }
      rethrow;
    }
  }

  // 4. Sign Out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    debugPrint("User signed out.");
  }

  // 5. Upload File
  Future<void> uploadFile(
    File localFile,
    String fileName, {
    void Function(double fraction)? onProgress,
  }) async {
    final driveApi = await getDriveApi();
    if (driveApi == null) return;

    // Check if file exists to update instead of duplicate
    final fileList = await driveApi.files.list(
      q: "name = '$fileName' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: "files(id, modifiedTime)",
    );

    final driveFile = drive.File();
    driveFile.name = fileName;

    final int length = await localFile.length();

    int transferred = 0;
    int lastPercent = -1;
    final Stream<List<int>> stream = localFile.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (List<int> data, EventSink<List<int>> sink) {
          transferred += data.length;
          if (onProgress != null && length > 0) {
            final int percent = ((transferred / length) * 100).floor();
            if (percent != lastPercent) {
              lastPercent = percent;
              onProgress((transferred / length).clamp(0.0, 1.0).toDouble());
            }
          }
          sink.add(data);
        },
      ),
    );

    final media = drive.Media(stream, length);

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      // Update existing
      final fileId = fileList.files!.first.id!;
      await driveApi.files.update(driveFile, fileId, uploadMedia: media);
      debugPrint("File updated: $fileName");
    } else {
      // Create new
      await driveApi.files.create(driveFile, uploadMedia: media);
      debugPrint("File created: $fileName");
    }

    onProgress?.call(1.0);
  }

  // 6. Download File
  Future<File?> downloadFile(
    String fileName,
    String savePath, {
    void Function(double fraction)? onProgress,
  }) async {
    final driveApi = await getDriveApi();
    if (driveApi == null) return null;

    final fileList = await driveApi.files.list(
      q: "name = '$fileName' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: "files(id, size, modifiedTime)",
    );

    if (fileList.files == null || fileList.files!.isEmpty) {
      debugPrint("Backup file not found in Google Drive.");
      return null;
    }

    final selected = fileList.files!.first;
    final fileId = selected.id!;
    final int totalBytes = int.tryParse(selected.size ?? '') ?? 0;

    final drive.Media file =
        await driveApi.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;

    final localFile = File(savePath);

    final sink = localFile.openWrite();

    int transferred = 0;
    int lastPercent = -1;
    await for (final chunk in file.stream) {
      sink.add(chunk);
      transferred += chunk.length;

      if (onProgress != null && totalBytes > 0) {
        final int percent = ((transferred / totalBytes) * 100).floor();
        if (percent != lastPercent) {
          lastPercent = percent;
          onProgress((transferred / totalBytes).clamp(0.0, 1.0).toDouble());
        }
      }
    }

    await sink.flush();
    await sink.close();

    debugPrint("File downloaded to $savePath");
    onProgress?.call(1.0);
    return localFile;
  }
}

/// A simple client that injects the Auth Headers into every request
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}
