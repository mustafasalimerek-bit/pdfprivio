import 'pdf_document.dart';

/// Reference to a single page inside a document.
///
/// Used for page-level operations (merge across documents, signature
/// placement, search results) where we need (document, page_index) tuples
/// without holding the full document binary in memory.
class PdfPageRef {
  final PdfDocument document;
  final int pageIndex; // 0-based

  const PdfPageRef({
    required this.document,
    required this.pageIndex,
  });

  /// 1-based page number for UI display ("Page 3 of 50").
  int get pageNumber => pageIndex + 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfPageRef &&
          runtimeType == other.runtimeType &&
          document == other.document &&
          pageIndex == other.pageIndex;

  @override
  int get hashCode => Object.hash(document, pageIndex);
}
