import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class GoogleDriveService {
  // Scopes required for the app
  static const _scopes = [drive.DriveApi.driveFileScope];

  static Future<void>? _initFuture;

  static Future<void> _ensureInitialized() {
    return _initFuture ??= GoogleSignIn.instance.initialize();
  }

  // 1. Sign In and Get Authenticated Client
  Future<drive.DriveApi?> getDriveApi() async {
    await _ensureInitialized();
    try {
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate(scopeHint: _scopes);

      final headers = await account.authorizationClient.authorizationHeaders(
        _scopes,
        promptIfNecessary: true,
      );

      if (headers == null) return null;

      return drive.DriveApi(GoogleAuthClient(headers));
    } catch (e) {
      print("Google Sign In Error: $e");
      rethrow;
    }
  }

  // 2. Sign Out
  Future<void> signOut() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
  }

  // 3. Upload File
  Future<void> uploadFile(File localFile, String fileName) async {
    final driveApi = await getDriveApi();
    if (driveApi == null) return;

    final fileList = await driveApi.files.list(
      q: "name = '$fileName' and trashed = false",
      $fields: "files(id)",
    );

    final driveFile = drive.File();
    driveFile.name = fileName;

    // Use a stream for efficient memory usage with large files
    final media = drive.Media(localFile.openRead(), localFile.lengthSync());

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      final fileId = fileList.files!.first.id!;
      await driveApi.files.update(driveFile, fileId, uploadMedia: media);
    } else {
      await driveApi.files.create(driveFile, uploadMedia: media);
    }
  }

  // 4. Download File
  Future<File?> downloadFile(String fileName, String savePath) async {
    final driveApi = await getDriveApi();
    if (driveApi == null) return null;

    final fileList = await driveApi.files.list(
      q: "name = '$fileName' and trashed = false",
      $fields: "files(id, size)",
    );

    if (fileList.files == null || fileList.files!.isEmpty) {
      throw Exception("Backup file not found in Google Drive.");
    }

    final fileId = fileList.files!.first.id!;

    final drive.Media file =
        await driveApi.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;

    final localFile = File(savePath);

    // Efficiently pipe stream to file
    final sink = localFile.openWrite();
    await file.stream.pipe(sink);

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
