import 'dart:io';

/// A user-selected PDF file with cached metadata.
///
/// We deliberately model this as immutable so providers can detect changes
/// via equality and so undo/redo stacks don't accidentally mutate history.
class PdfDocument {
  final File file;
  final String displayName;
  final int sizeBytes;
  final int pageCount;
  final bool isPasswordProtected;
  final bool hasOcrLayer;
  final DateTime addedAt;

  const PdfDocument({
    required this.file,
    required this.displayName,
    required this.sizeBytes,
    required this.pageCount,
    required this.isPasswordProtected,
    required this.hasOcrLayer,
    required this.addedAt,
  });

  String get path => file.path;

  PdfDocument copyWith({
    File? file,
    String? displayName,
    int? sizeBytes,
    int? pageCount,
    bool? isPasswordProtected,
    bool? hasOcrLayer,
  }) {
    return PdfDocument(
      file: file ?? this.file,
      displayName: displayName ?? this.displayName,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      pageCount: pageCount ?? this.pageCount,
      isPasswordProtected: isPasswordProtected ?? this.isPasswordProtected,
      hasOcrLayer: hasOcrLayer ?? this.hasOcrLayer,
      addedAt: addedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfDocument &&
          runtimeType == other.runtimeType &&
          file.path == other.file.path;

  @override
  int get hashCode => file.path.hashCode;
}
