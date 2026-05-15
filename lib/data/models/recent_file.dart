/// A row in the user's "recent files" workspace — usually an *output*
/// of a tool (e.g. a redacted PDF, a filled form, a signed contract).
///
/// We don't persist the actual PDF — only its sandbox path and metadata.
/// If the user deletes the file from Files.app the row stays but gets
/// flagged as missing on next read.
class RecentFile {
  /// Stable ID. We use the file path because the sandbox path is
  /// stable for the lifetime of the app install.
  final String id;
  final String path;
  final String displayName;
  final int sizeBytes;
  final String toolLabel; // e.g. "Redacted", "Signed", "OCR'd"
  final DateTime openedAt;

  const RecentFile({
    required this.id,
    required this.path,
    required this.displayName,
    required this.sizeBytes,
    required this.toolLabel,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'displayName': displayName,
        'sizeBytes': sizeBytes,
        'toolLabel': toolLabel,
        'openedAt': openedAt.toIso8601String(),
      };

  static RecentFile? fromJson(Map<String, dynamic> json) {
    try {
      return RecentFile(
        id: json['id'] as String,
        path: json['path'] as String,
        displayName: json['displayName'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        toolLabel: json['toolLabel'] as String,
        openedAt: DateTime.parse(json['openedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
