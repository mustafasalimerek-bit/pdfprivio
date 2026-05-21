import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import 'audit_service.dart';
import 'ocr_service.dart';

/// One image-page paired with its OCR result.
class OcrComposedPage {
  final File image;
  final OcrPageResult ocr;
  const OcrComposedPage({required this.image, required this.ocr});
}

class OcrComposeOutcome {
  final File outputFile;
  final int pageCount;
  final int totalObservations;
  final Duration elapsed;

  const OcrComposeOutcome({
    required this.outputFile,
    required this.pageCount,
    required this.totalObservations,
    required this.elapsed,
  });
}

/// Composes a "searchable PDF" from a list of (image, OCR result) pairs:
/// each page holds the original image at its native size, plus a text
/// layer placed at the recognized bounding boxes that lives UNDER the
/// image.
///
/// Searchability mechanism: text is drawn into the content stream
/// first, then the opaque image is painted on top — same trick Adobe
/// Acrobat and Tesseract use for "searchable PDF" output. The image
/// visually covers the text, but PDF text extraction (Cmd+F,
/// copy/paste, parsers) reads the content stream order-agnostically
/// and finds the OCR text. Position follows Vision's normalized
/// bottom-left coords, flipped to PDF's top-left convention used by
/// Syncfusion's drawing API.
///
/// Why under-image instead of an alpha-1/255 brush on top: iOS PDFKit
/// (and the Files app preview) do NOT honor 0.4% alpha as truly
/// invisible — the OCR text bled through as faint duplicated glyphs
/// over the original scan, making the output read as "two layers of
/// mixed text." Placing the layer below the image is the only viewer-
/// agnostic way to keep text searchable without visual artifacts.
class PdfOcrComposeService {
  PdfOcrComposeService._();
  static final PdfOcrComposeService instance = PdfOcrComposeService._();

  Future<Result<OcrComposeOutcome>> compose({
    required List<OcrComposedPage> pages,
    String? outputName,
    void Function(double progress, String message)? onProgress,
    CancellationToken? cancel,
  }) async {
    if (pages.isEmpty) {
      return Err(FailureKind.unknown, 'No pages to compose.');
    }

    final stopwatch = Stopwatch()..start();
    final pdf = sf.PdfDocument();
    pdf.pageSettings.margins.all = 0;
    var totalObs = 0;

    try {
      for (var i = 0; i < pages.length; i++) {
        if (cancel?.isCancelled ?? false) {
          pdf.dispose();
          return Err(FailureKind.cancelled, 'Cancelled');
        }
        onProgress?.call(
          i / pages.length,
          'Composing page ${i + 1} of ${pages.length}',
        );

        final p0 = pages[i];
        final imgBytes = await p0.image.readAsBytes();
        final bitmap = sf.PdfBitmap(imgBytes);

        // Page size = image's pixel size in PDF points (1px = 1pt).
        // Keeps OCR bbox mapping trivial. PDF viewers fit-to-window.
        final pageW = p0.ocr.imageWidth > 0
            ? p0.ocr.imageWidth
            : bitmap.width.toDouble();
        final pageH = p0.ocr.imageHeight > 0
            ? p0.ocr.imageHeight
            : bitmap.height.toDouble();

        pdf.pageSettings.size = ui.Size(pageW, pageH);
        final page = pdf.pages.add();

        // Step 1 — text layer FIRST so the image (drawn next) sits on
        // top of it. Color/alpha don't matter visually since the image
        // covers it; using opaque black keeps the brush simple.
        final brush = sf.PdfSolidBrush(sf.PdfColor(0, 0, 0));

        for (final obs in p0.ocr.observations) {
          // Vision: normalized 0..1, origin bottom-left.
          // Syncfusion: points, origin top-left, Y down.
          final w = obs.width * page.size.width;
          final h = obs.height * page.size.height;
          final x = obs.x * page.size.width;
          final y = (1.0 - obs.y - obs.height) * page.size.height;

          // Font size approximating the bbox height; clamped so tiny
          // confidences don't crash the standard font.
          final fontSize = math.max(4.0, h * 0.78);
          final font = sf.PdfStandardFont(
            sf.PdfFontFamily.helvetica,
            fontSize,
          );

          page.graphics.drawString(
            obs.text,
            font,
            brush: brush,
            bounds: ui.Rect.fromLTWH(x, y, w, h),
          );
        }

        // Step 2 — opaque image on top, covering the text layer.
        page.graphics.drawImage(
          bitmap,
          ui.Rect.fromLTWH(0, 0, page.size.width, page.size.height),
        );

        totalObs += p0.ocr.observations.length;
      }

      onProgress?.call(0.97, 'Saving file');
      final bytes = await pdf.save();
      pdf.dispose();
      stopwatch.stop();

      final out = await _writeOutput(bytes, outputName ?? 'searchable_scan');
      onProgress?.call(1.0, 'Done');

      await AuditService.instance.record(
        tool: 'ocr',
        outputFile: out,
        params: {
          'pageCount': '${pages.length}',
          'recognizedObservations': '$totalObs',
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
        },
      );

      return Ok(OcrComposeOutcome(
        outputFile: out,
        pageCount: pages.length,
        totalObservations: totalObs,
        elapsed: stopwatch.elapsed,
      ));
    } catch (e) {
      pdf.dispose();
      stopwatch.stop();
      return Err(FailureKind.unknown,
          'Could not build searchable PDF.', cause: e);
    }
  }

  Future<File> _writeOutput(List<int> bytes, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = baseName.replaceAll(RegExp(r'[\\/]'), '_').trim();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = p.join(dir.path, '${safe}_$stamp.pdf');
    final f = File(path);
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

}
