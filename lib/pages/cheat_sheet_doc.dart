import 'package:path/path.dart' as p;

class CheatSheetDoc {
  final String id;
  final String title;
  final String subtitle;
  final String filePath;
  final String fileType;
  final int createdAtMs;

  const CheatSheetDoc({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.filePath,
    required this.fileType,
    required this.createdAtMs,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'filePath': filePath,
    'fileType': fileType,
    'createdAtMs': createdAtMs,
  };

  static CheatSheetDoc fromJson(Map<String, dynamic> json) {
    final path = (json['filePath'] as String?) ?? '';
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return CheatSheetDoc(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      subtitle: (json['subtitle'] as String?) ?? '',
      filePath: path,
      fileType: ((json['fileType'] as String?) ?? ext).toLowerCase(),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
