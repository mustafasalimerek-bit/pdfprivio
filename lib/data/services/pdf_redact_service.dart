import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// Outcome of a redaction run.
class RedactOutcome {
  final File file;
  final int matchesFound;
  final int pagesAffected;

  const RedactOutcome({
    required this.file,
    required this.matchesFound,
    required this.pagesAffected,
  });
}

/// Search-and-redact: the user gives one or more strings, we find every
/// line that contains any of those strings on any page, and draw an opaque
/// black rectangle over each match.
///
/// Caveat we're honest about in the UI: the source text remains in the PDF
/// data stream — a determined user could still extract it by parsing the
/// raw PDF, so this isn't legally-binding cryptographic redaction. For
/// most consumer/prosumer "hide my account number" use cases that's fine
/// and matches what Smallpdf/iLovePDF "redact" tools do. True content-
/// removal redaction is a Pro feature for v1.x once Syncfusion's
/// PdfRedaction API is wired in.
class PdfRedactService {
  PdfRedactService._();
  static final PdfRedactService instance = PdfRedactService._();

  /// Search texts are lowercased + trimmed at the call site so an empty
  /// or whitespace-only entry doesn't redact every line by accident.
  Future<Result<RedactOutcome>> redact({
    required PdfDocument input,
    required List<String> searchTexts,
    bool caseSensitive = false,
    void Function(double progress, String message)? onProgress,
    CancellationToken? cancel,
  }) async {
    final cleanSearches = searchTexts
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (cleanSearches.isEmpty) {
      return Err(FailureKind.unknown, 'No search texts provided');
    }

    sf.PdfDocument? doc;
    try {
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      final extractor = sf.PdfTextExtractor(doc);
      final brush = sf.PdfSolidBrush(sf.PdfColor(0, 0, 0));

      var matchesFound = 0;
      final affectedPages = <int>{};

      for (var i = 0; i < doc.pages.count; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }
        onProgress?.call(
          i / doc.pages.count,
          'Scanning page ${i + 1} of ${doc.pages.count}',
        );

        // Pull line-level bounds so we can blot out the rectangle the
        // matched text lives inside. Word-level bounds (extractTextLines
        // exposes wordCollection per line) would let us target only the
        // matching word — that's a Pro upgrade once Pro tier lands.
        List<sf.TextLine> lines;
        try {
          lines = extractor.extractTextLines(
            startPageIndex: i,
            endPageIndex: i,
          );
        } catch (_) {
          continue;
        }

        for (final line in lines) {
          final haystack =
              caseSensitive ? line.text : line.text.toLowerCase();
          var hit = false;
          for (final needle in cleanSearches) {
            final query = caseSensitive ? needle : needle.toLowerCase();
            if (haystack.contains(query)) {
              hit = true;
              matchesFound++;
              break;
            }
          }
          if (!hit) continue;

          affectedPages.add(i);
          // line.bounds is the on-page bounding box. We pad vertically a
          // touch so descenders (g, p, y) don't peek out of the redaction.
          final b = line.bounds;
          final rect = Rect.fromLTWH(
            b.left,
            b.top - 1,
            b.width,
            b.height + 2,
          );
          doc.pages[i].graphics.drawRectangle(
            brush: brush,
            bounds: rect,
          );
        }
      }

      onProgress?.call(0.95, 'Writing…');
      final outBytes = await doc.save();
      final outFile = await _writeOutput(
        outBytes,
        '${input.displayName}_redacted',
      );
      onProgress?.call(1.0, 'Done');

      return Ok(RedactOutcome(
        file: outFile,
        matchesFound: matchesFound,
        pagesAffected: affectedPages.length,
      ));
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'PDF is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Redaction failed', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  Future<File> _writeOutput(List<int> bytes, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = baseName.replaceAll(RegExp(r'[\\/]'), '_').trim();
    final path = p.join(dir.path, '$safe.pdf');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
