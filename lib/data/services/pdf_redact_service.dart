import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';
import 'ocr_service.dart';
import 'pdf_ocr_compose_service.dart';

/// Outcome of a redaction run.
class RedactOutcome {
  final File file;
  final int matchesFound;
  final int pagesAffected;
  final int totalPages;

  const RedactOutcome({
    required this.file,
    required this.matchesFound,
    required this.pagesAffected,
    required this.totalPages,
  });
}

/// Real, content-destructive redaction.
///
/// Strategy ("render-and-flatten"):
///   1. Syncfusion's text extractor gives us per-word bounding boxes for
///      every search-term hit, in PDF point space.
///   2. We rasterize each page to a high-resolution JPEG via pdfx (native
///      PDFKit on iOS, PdfRenderer on Android).
///   3. For pages that had hits, we burn opaque black rectangles into the
///      JPEG pixels at the matched word bounds (scaled point→pixel).
///   4. We rebuild a brand-new PDF where every page is the (possibly
///      redacted) raster image at its native PDF size.
///
/// Trade-off: pages that originally had a text layer lose it (the whole
/// page is now an image). That's the *correct* behaviour for a redaction
/// tool: Adobe Acrobat Pro's "Apply Redactions" does the same flatten,
/// because *any* surviving text in the data stream is a leak waiting to
/// happen. Lawyers preparing a doc for disclosure trade Cmd+F for
/// bulletproof protection; we offer an OCR pass downstream if they want
/// search back for the *non-redacted* parts.
class PdfRedactService {
  PdfRedactService._();
  static final PdfRedactService instance = PdfRedactService._();

  /// Long-edge in pixels used when rasterizing pages. 2000 gives crisp
  /// output at typical viewing zoom without blowing up output size.
  static const int _rasterLongEdge = 2000;
  static const int _jpegQuality = 88;

  Future<Result<RedactOutcome>> redact({
    required PdfDocument input,
    required List<String> searchTexts,
    bool caseSensitive = false,
    bool makeSearchable = true,
    List<String> ocrLanguages = const ['en-US', 'tr-TR'],
    void Function(double progress, String message)? onProgress,
    CancellationToken? cancel,
  }) async {
    final cleanSearches = searchTexts
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (cleanSearches.isEmpty) {
      return Err(FailureKind.unknown, 'No search texts provided.');
    }

    sf.PdfDocument? sourceDoc;
    pdfx.PdfDocument? pdfxDoc;
    try {
      // ---------- Phase 1: find word bounds for every match ----------
      onProgress?.call(0.02, 'Finding matches…');
      final bytes = await input.file.readAsBytes();
      sourceDoc = sf.PdfDocument(inputBytes: bytes);
      final extractor = sf.PdfTextExtractor(sourceDoc);
      final totalPages = sourceDoc.pages.count;

      // page index → list of word-level redaction rects in PDF point space
      final hitsByPage = <int, List<ui.Rect>>{};
      // page index → page size in PDF points (so we can map to pixels later)
      final pageSizes = <int, ui.Size>{};
      var matchCount = 0;

      for (var i = 0; i < totalPages; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled');
        }
        onProgress?.call(
          0.02 + 0.18 * (i / totalPages),
          'Scanning page ${i + 1} of $totalPages',
        );

        pageSizes[i] = sourceDoc.pages[i].size;
        final lines = _safeExtractLines(extractor, i);
        for (final line in lines) {
          final rects = _matchRectsForLine(
            line: line,
            terms: cleanSearches,
            caseSensitive: caseSensitive,
          );
          if (rects.isEmpty) continue;
          hitsByPage.putIfAbsent(i, () => []).addAll(rects);
          matchCount += rects.length;
        }
      }

      sourceDoc.dispose();
      sourceDoc = null;

      if (matchCount == 0) {
        return Err(
          FailureKind.unknown,
          'No matches found. Try different search terms or check '
          'case-sensitivity.',
        );
      }

      // ---------- Phase 2: render every page to JPEG ----------
      onProgress?.call(0.22, 'Rasterizing pages…');
      pdfxDoc = await pdfx.PdfDocument.openFile(input.path);
      final renderedPages = <_RenderedPage>[];
      final tmpDir = await _makeTempDir();

      for (var i = 0; i < totalPages; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled');
        }
        onProgress?.call(
          0.22 + 0.45 * (i / totalPages),
          'Rendering page ${i + 1} of $totalPages',
        );

        final page = await pdfxDoc.getPage(i + 1);
        try {
          final pageSize = pageSizes[i]!;
          final aspect = pageSize.height / pageSize.width;
          double w, h;
          if (pageSize.width >= pageSize.height) {
            w = _rasterLongEdge.toDouble();
            h = w * aspect;
          } else {
            h = _rasterLongEdge.toDouble();
            w = h / aspect;
          }
          final image = await page.render(
            width: w,
            height: h,
            format: pdfx.PdfPageImageFormat.jpeg,
            quality: _jpegQuality,
          );
          if (image == null) continue;

          Uint8List bytes = image.bytes;
          final hits = hitsByPage[i];
          if (hits != null && hits.isNotEmpty) {
            bytes = _burnRedactions(
              jpegBytes: bytes,
              pixelWidth: w.round(),
              pixelHeight: h.round(),
              hits: hits,
              pdfPageSize: pageSize,
            );
          }

          final filePath = p.join(
            tmpDir.path,
            'p_${(i + 1).toString().padLeft(4, '0')}.jpg',
          );
          await File(filePath).writeAsBytes(bytes, flush: true);
          renderedPages.add(_RenderedPage(
            filePath: filePath,
            pageSize: pageSize,
            wasRedacted: hits != null && hits.isNotEmpty,
          ));
        } finally {
          await page.close();
        }
      }

      await pdfxDoc.close();
      pdfxDoc = null;

      // ---------- Phase 3: build output PDF ----------
      final File outFile;
      if (makeSearchable) {
        // 3a) OCR each (redacted) image so the non-redacted text becomes
        //     selectable/searchable again. Apple Vision can't read the
        //     black rectangles, so the redacted strings never enter the
        //     output text layer — redaction stays bulletproof while the
        //     rest of the page becomes Cmd+F-friendly.
        final composedPages = <OcrComposedPage>[];
        for (var i = 0; i < renderedPages.length; i++) {
          if (cancel?.isCancelled ?? false) {
            return Err(FailureKind.cancelled, 'Cancelled');
          }
          onProgress?.call(
            0.7 + 0.18 * (i / renderedPages.length),
            'OCR page ${i + 1} of ${renderedPages.length}',
          );
          final r = renderedPages[i];
          final file = File(r.filePath);
          final ocrRes = await OcrService.instance.recognize(
            image: file,
            languages: ocrLanguages,
          );
          if (ocrRes is Err<OcrPageResult>) {
            return Err(ocrRes.kind, ocrRes.message);
          }
          composedPages.add(OcrComposedPage(
            image: file,
            ocr: (ocrRes as Ok<OcrPageResult>).value,
          ));
        }

        onProgress?.call(0.88, 'Building searchable PDF…');
        final composeRes = await PdfOcrComposeService.instance.compose(
          pages: composedPages,
          outputName: '${_safeBase(input.displayName)}_redacted',
          onProgress: (cp, msg) {
            onProgress?.call(0.88 + 0.10 * cp, msg);
          },
          cancel: cancel,
        );
        switch (composeRes) {
          case Ok(:final value):
            outFile = value.outputFile;
          case Err(:final kind, :final message):
            return Err(kind, message);
        }
      } else {
        onProgress?.call(0.7, 'Building redacted PDF…');
        final outDoc = sf.PdfDocument();
        outDoc.pageSettings.margins.all = 0;

        for (var i = 0; i < renderedPages.length; i++) {
          if (cancel?.isCancelled ?? false) {
            outDoc.dispose();
            return Err(FailureKind.cancelled, 'Cancelled');
          }
          onProgress?.call(
            0.7 + 0.25 * (i / renderedPages.length),
            'Composing page ${i + 1} of ${renderedPages.length}',
          );

          final r = renderedPages[i];
          outDoc.pageSettings.size = r.pageSize;
          final page = outDoc.pages.add();
          final imgBytes = await File(r.filePath).readAsBytes();
          final bitmap = sf.PdfBitmap(imgBytes);
          page.graphics.drawImage(
            bitmap,
            ui.Rect.fromLTWH(0, 0, page.size.width, page.size.height),
          );
        }

        onProgress?.call(0.97, 'Writing file…');
        final outBytes = await outDoc.save();
        outDoc.dispose();
        outFile = await _writeOutput(
          outBytes,
          '${_safeBase(input.displayName)}_redacted',
        );
      }

      onProgress?.call(1.0, 'Done');

      return Ok(RedactOutcome(
        file: outFile,
        matchesFound: matchCount,
        pagesAffected: hitsByPage.length,
        totalPages: totalPages,
      ));
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword,
            'PDF is password-protected — unlock it first.', cause: e);
      }
      return Err(FailureKind.unknown, 'Redaction failed.', cause: e);
    } finally {
      sourceDoc?.dispose();
      await pdfxDoc?.close();
    }
  }

  List<sf.TextLine> _safeExtractLines(
      sf.PdfTextExtractor extractor, int pageIndex) {
    try {
      return extractor.extractTextLines(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Returns one `Rect` per term hit on the line. Bounds tightly cover
  /// the actual word(s) the term spans — not the whole line — so the
  /// black bar in the rendered output is precise and doesn't blot out
  /// neighbouring (non-sensitive) content.
  List<ui.Rect> _matchRectsForLine({
    required sf.TextLine line,
    required List<String> terms,
    required bool caseSensitive,
  }) {
    final out = <ui.Rect>[];
    final lineHaystack =
        caseSensitive ? line.text : line.text.toLowerCase();
    for (final term in terms) {
      final needle = caseSensitive ? term : term.toLowerCase();
      var start = 0;
      while (true) {
        final hit = lineHaystack.indexOf(needle, start);
        if (hit < 0) break;
        final end = hit + needle.length;
        out.add(_boundsForCharRange(line, hit, end));
        start = end;
      }
    }
    return out;
  }

  /// Approximates a tight bbox for chars [start, end) inside the line by
  /// expanding the bounds of every word that overlaps that range.
  ui.Rect _boundsForCharRange(sf.TextLine line, int start, int end) {
    var cursor = 0;
    final picked = <sf.TextWord>[];
    for (final word in line.wordCollection) {
      final wordLen = word.text.length;
      // Walk past one leading space if the line text has it.
      while (cursor < line.text.length && line.text[cursor] == ' ') {
        cursor++;
      }
      final wStart = cursor;
      final wEnd = cursor + wordLen;
      if (wEnd > start && wStart < end) picked.add(word);
      cursor = wEnd;
    }
    if (picked.isEmpty) {
      // Fallback: redact the whole line. Conservative but safe.
      return line.bounds;
    }
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final w in picked) {
      final b = w.bounds;
      if (b.left < left) left = b.left;
      if (b.top < top) top = b.top;
      if (b.right > right) right = b.right;
      if (b.bottom > bottom) bottom = b.bottom;
    }
    // Pad a hair vertically so descenders (g, p, y) don't peek out.
    return ui.Rect.fromLTRB(left, top - 1, right, bottom + 2);
  }

  /// Decodes the JPEG, draws filled black rectangles at the (PDF-space)
  /// hits scaled to image pixel coords, re-encodes as JPEG.
  Uint8List _burnRedactions({
    required Uint8List jpegBytes,
    required int pixelWidth,
    required int pixelHeight,
    required List<ui.Rect> hits,
    required ui.Size pdfPageSize,
  }) {
    final image = img.decodeJpg(jpegBytes);
    if (image == null) return jpegBytes;

    final sx = pixelWidth / pdfPageSize.width;
    final sy = pixelHeight / pdfPageSize.height;
    final black = img.ColorRgb8(0, 0, 0);

    for (final r in hits) {
      final x1 = (r.left * sx).round().clamp(0, pixelWidth - 1);
      final y1 = (r.top * sy).round().clamp(0, pixelHeight - 1);
      final x2 = (r.right * sx).round().clamp(0, pixelWidth - 1);
      final y2 = (r.bottom * sy).round().clamp(0, pixelHeight - 1);
      img.fillRect(
        image,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: black,
      );
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: _jpegQuality));
  }

  Future<Directory> _makeTempDir() async {
    final root = await getTemporaryDirectory();
    final dir = Directory(p.join(
      root.path,
      'pdfprivio_redact_${DateTime.now().millisecondsSinceEpoch}',
    ));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _writeOutput(List<int> bytes, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = _safeBase(baseName);
    final path = p.join(dir.path, '$safe.pdf');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _safeBase(String s) =>
      s.replaceAll('.pdf', '').replaceAll(RegExp(r'[\\/]'), '_').trim();
}

class _RenderedPage {
  final String filePath;
  final ui.Size pageSize;
  final bool wasRedacted;
  const _RenderedPage({
    required this.filePath,
    required this.pageSize,
    required this.wasRedacted,
  });
}
