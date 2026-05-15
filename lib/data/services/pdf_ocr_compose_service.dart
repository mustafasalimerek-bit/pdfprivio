import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
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
/// each page holds the original image at its native size, plus an
/// invisible text layer placed at the recognized bounding boxes.
///
/// Searchability mechanism: the text is drawn with an alpha-1/255 brush
/// (visually invisible to any viewer, but written into the page content
/// stream — so Cmd+F, copy/paste, and PDF parsers find it). Position
/// follows Vision's normalized bottom-left coords, flipped to PDF's
/// top-left convention used by Syncfusion's drawing API.
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

        // Draw the image filling the page.
        page.graphics.drawImage(
          bitmap,
          ui.Rect.fromLTWH(0, 0, page.size.width, page.size.height),
        );

        // Invisible text overlay — alpha 1/255 keeps it searchable but
        // visually undetectable in every PDF viewer we've checked.
        final brush = sf.PdfSolidBrush(sf.PdfColor(0, 0, 0, 1));

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

        totalObs += p0.ocr.observations.length;
      }

      onProgress?.call(0.97, 'Saving file');
      final bytes = await pdf.save();
      pdf.dispose();
      stopwatch.stop();

      final out = await _writeOutput(bytes, outputName ?? 'searchable_scan');
      onProgress?.call(1.0, 'Done');

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
