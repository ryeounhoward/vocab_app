// import 'dart:io';
// import 'package:google_sign_in/google_sign_in.dart';
// import 'package:googleapis/drive/v3.dart' as drive;
// import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

// class GoogleDriveService {
//   // Scopes required for the app
//   static const _scopes = [drive.DriveApi.driveFileScope];

//   final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

//   // 1. Sign In and Get Authenticated Client
//   Future<drive.DriveApi?> getDriveApi() async {
//     try {
//       final GoogleSignInAccount? account = await _googleSignIn.signIn();
//       if (account == null) {
//         // User canceled the sign-in
//         return null;
//       }
//       final httpClient = await _googleSignIn.authenticatedClient();
//       if (httpClient == null) return null;

//       return drive.DriveApi(httpClient);
//     } catch (e) {
//       print("Google Sign In Error: $e");
//       rethrow;
//     }
//   }

//   // 2. Sign Out
//   Future<void> signOut() async {
//     await _googleSignIn.signOut();
//   }

//   // 3. Upload File (Create or Update)
//   Future<void> uploadFile(File localFile, String fileName) async {
//     final driveApi = await getDriveApi();
//     if (driveApi == null) return;

//     // Check if file already exists to update it instead of creating duplicates
//     final fileList = await driveApi.files.list(
//       q: "name = '$fileName' and trashed = false",
//       $fields: "files(id)",
//     );

//     final driveFile = drive.File();
//     driveFile.name = fileName;

//     final media = drive.Media(localFile.openRead(), localFile.lengthSync());

//     if (fileList.files != null && fileList.files!.isNotEmpty) {
//       // Update existing file
//       final fileId = fileList.files!.first.id!;
//       await driveApi.files.update(driveFile, fileId, uploadMedia: media);
//     } else {
//       // Create new file
//       await driveApi.files.create(driveFile, uploadMedia: media);
//     }
//   }

//   // 4. Restore (Download) File
//   Future<File?> downloadFile(String fileName, String savePath) async {
//     final driveApi = await getDriveApi();
//     if (driveApi == null) return null;

//     // Search for the file
//     final fileList = await driveApi.files.list(
//       q: "name = '$fileName' and trashed = false",
//       $fields: "files(id, size)",
//     );

//     if (fileList.files == null || fileList.files!.isEmpty) {
//       throw Exception("Backup file not found in Google Drive.");
//     }

//     final fileId = fileList.files!.first.id!;
//     final drive.Media file =
//         await driveApi.files.get(
//               fileId,
//               downloadOptions: drive.DownloadOptions.fullMedia,
//             )
//             as drive.Media;

//     final List<int> dataStore = [];
//     await for (final data in file.stream) {
//       dataStore.addAll(data);
//     }

//     final localFile = File(savePath);
//     await localFile.writeAsBytes(dataStore);
//     return localFile;
//   }
// }
