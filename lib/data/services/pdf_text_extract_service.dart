import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// Outcome of a text-extraction run on a PDF.
class TextExtractOutcome {
  final List<String> pagesText;
  final String fullText;
  final int charCount;
  final Duration elapsed;
  final bool wasMostlyEmpty;

  const TextExtractOutcome({
    required this.pagesText,
    required this.fullText,
    required this.charCount,
    required this.elapsed,
    required this.wasMostlyEmpty,
  });
}

/// Pulls plain text out of a PDF's existing text layer.
///
/// For born-digital PDFs (Word/Pages export, web "Print to PDF", any
/// machine-generated document) this is instant and lossless: the text is
/// already in the PDF, we're just collecting it. For scanned PDFs that
/// were never OCR'd the result is empty per page — the UI should suggest
/// the OCR tool in that case (coming when we wire up the Apple Vision
/// bridge; ML Kit is currently blocked on Apple-Silicon-sim linker bugs).
class PdfTextExtractService {
  PdfTextExtractService._();
  static final PdfTextExtractService instance = PdfTextExtractService._();

  /// We treat the file as "mostly empty" when the per-page average is under
  /// this many printable characters — typical for vector cover pages or
  /// pure-scan PDFs.
  static const int _mostlyEmptyThreshold = 8;

  Future<Result<TextExtractOutcome>> extract({
    required PdfDocument input,
    void Function(double progress, String message)? onProgress,
    CancellationToken? cancel,
  }) async {
    final stopwatch = Stopwatch()..start();
    sf.PdfDocument? doc;
    try {
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      final extractor = sf.PdfTextExtractor(doc);
      final pageCount = doc.pages.count;
      final pagesText = <String>[];

      for (var i = 0; i < pageCount; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }
        onProgress?.call(
          i / pageCount,
          'Reading page ${i + 1} of $pageCount',
        );

        // Syncfusion's per-page extraction; safe on pages with no text layer
        // (returns empty string rather than throwing).
        final text = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        pagesText.add(text);
      }

      stopwatch.stop();
      onProgress?.call(1.0, 'Done');

      final fullText = _join(pagesText);
      final avg = pageCount == 0 ? 0 : fullText.length / pageCount;

      return Ok(TextExtractOutcome(
        pagesText: pagesText,
        fullText: fullText,
        charCount: fullText.length,
        elapsed: stopwatch.elapsed,
        wasMostlyEmpty: avg < _mostlyEmptyThreshold,
      ));
    } catch (e) {
      stopwatch.stop();
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'PDF is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Text extraction failed', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  String _join(List<String> pagesText) {
    final buf = StringBuffer();
    for (var i = 0; i < pagesText.length; i++) {
      if (i > 0) buf.write('\n\n--- Page ${i + 1} ---\n\n');
      buf.write(pagesText[i].trim());
    }
    return buf.toString().trim();
  }

  Future<File> writeAsTextFile({
    required String baseName,
    required String text,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = baseName.replaceAll(RegExp(r'[\\/]'), '_').trim();
    final path = p.join(dir.path, '${safe}_text.txt');
    final file = File(path);
    await file.writeAsString(text, flush: true);
    return file;
  }
}
