import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

import '../models/pdf_document.dart';
import '../models/pdf_page_ref.dart';

/// Renders page thumbnails on the native PDF engine (PDFKit on iOS,
/// PdfRenderer on Android) and caches them so the grid view stays smooth
/// while scrolling.
///
/// The cache is intentionally bounded — long-running sessions with many
/// large PDFs would otherwise pin gigabytes of bitmap data in memory.
class PdfThumbnailService {
  PdfThumbnailService._();
  static final PdfThumbnailService instance = PdfThumbnailService._();

  static const int _maxCacheEntries = 256;
  final _cache = <String, Uint8List>{};
  final _cacheOrder = <String>[];

  /// Renders the first page of the document for use as a doc-level
  /// thumbnail in lists.
  Future<Uint8List?> firstPage(PdfDocument doc, {int width = 240}) =>
      _renderPage(doc.path, 0, width);

  Future<Uint8List?> page(PdfPageRef ref, {int width = 240}) =>
      _renderPage(ref.document.path, ref.pageIndex, width);

  Future<Uint8List?> _renderPage(String path, int pageIndex, int width) async {
    final key = _cacheKey(path, pageIndex, width);
    final cached = _cache[key];
    if (cached != null) return cached;

    pdfx.PdfDocument? doc;
    pdfx.PdfPage? page;
    try {
      doc = await pdfx.PdfDocument.openFile(path);
      page = await doc.getPage(pageIndex + 1); // pdfx uses 1-based

      final aspect = page.height / page.width;
      final height = (width * aspect).round();
      final image = await page.render(
        width: width.toDouble(),
        height: height.toDouble(),
        format: pdfx.PdfPageImageFormat.jpeg,
        quality: 80,
      );
      if (image == null) return null;

      _put(key, image.bytes);
      return image.bytes;
    } catch (_) {
      return null;
    } finally {
      await page?.close();
      await doc?.close();
    }
  }

  String _cacheKey(String path, int pageIndex, int width) =>
      '$path|$pageIndex|$width';

  void _put(String key, Uint8List bytes) {
    if (_cache.containsKey(key)) {
      _cacheOrder.remove(key);
    } else if (_cache.length >= _maxCacheEntries) {
      final evict = _cacheOrder.removeAt(0);
      _cache.remove(evict);
    }
    _cache[key] = bytes;
    _cacheOrder.add(key);
  }

  /// Drops cached bitmaps for a document — call when the user removes it
  /// from the workspace so we don't pin its memory forever.
  void evict(PdfDocument doc) {
    final prefix = '${doc.path}|';
    _cacheOrder.removeWhere((k) => k.startsWith(prefix));
    _cache.removeWhere((k, _) => k.startsWith(prefix));
  }

  /// Drops everything — used when the user clears the workspace.
  void clear() {
    _cache.clear();
    _cacheOrder.clear();
  }
}
