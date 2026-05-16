import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// A single entry in a parsed PDF outline (table of contents).
///
/// Outline entries form a tree — each entry can hold its own children.
/// We flatten the destination down to a zero-based page index so the
/// UI layer doesn't need to keep the Syncfusion document open after
/// parsing.
class PdfOutlineEntry {
  final String title;
  final int pageIndex;
  final int level;
  final List<PdfOutlineEntry> children;

  const PdfOutlineEntry({
    required this.title,
    required this.pageIndex,
    required this.level,
    required this.children,
  });

  bool get hasChildren => children.isNotEmpty;
}

/// Parses the bookmark / outline tree out of a PDF and returns it as
/// a Dart-side tree. Returns `null` when the file has no outline at
/// all so the UI can show an empty-state message rather than an empty
/// tree.
class PdfOutlineService {
  PdfOutlineService._();
  static final PdfOutlineService instance = PdfOutlineService._();

  Future<List<PdfOutlineEntry>?> parse(File file) async {
    sf.PdfDocument? doc;
    try {
      final bytes = await file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);
      if (doc.bookmarks.count == 0) return null;

      // Cache page → index once instead of walking PdfPageCollection
      // for every bookmark; large docs with deep outlines turn into
      // O(N*M) otherwise.
      final pageIndex = <sf.PdfPage, int>{};
      for (var i = 0; i < doc.pages.count; i++) {
        pageIndex[doc.pages[i]] = i;
      }

      return _collect(doc.bookmarks, pageIndex, level: 0);
    } catch (_) {
      return null;
    } finally {
      doc?.dispose();
    }
  }

  List<PdfOutlineEntry> _collect(
    sf.PdfBookmarkBase parent,
    Map<sf.PdfPage, int> pageIndex, {
    required int level,
  }) {
    final result = <PdfOutlineEntry>[];
    for (var i = 0; i < parent.count; i++) {
      final bookmark = parent[i];
      final page = bookmark.destination?.page;
      result.add(PdfOutlineEntry(
        title: bookmark.title.isEmpty ? '(untitled)' : bookmark.title,
        pageIndex: page == null ? -1 : (pageIndex[page] ?? -1),
        level: level,
        children: _collect(bookmark, pageIndex, level: level + 1),
      ));
    }
    return result;
  }
}
