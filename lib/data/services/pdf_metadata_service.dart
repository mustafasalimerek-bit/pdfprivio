import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// Inspects a PDF file without loading its full page render stack.
///
/// Fails soft: password-protected and corrupted PDFs return structured `Err`
/// values that the caller can act on (prompt for password, offer repair)
/// instead of throwing.
class PdfMetadataService {
  PdfMetadataService._();
  static final PdfMetadataService instance = PdfMetadataService._();

  Future<Result<PdfDocument>> inspect(File file) async {
    final stat = await file.stat();
    final displayName = _displayNameFor(file);

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      return Err(FailureKind.unknown, 'Could not read file', cause: e);
    }

    sf.PdfDocument? doc;
    try {
      doc = sf.PdfDocument(inputBytes: bytes);
      return Ok(PdfDocument(
        file: file,
        displayName: displayName,
        sizeBytes: stat.size,
        pageCount: doc.pages.count,
        isPasswordProtected: false,
        hasOcrLayer: _hasOcrLayer(doc),
        addedAt: DateTime.now(),
      ));
    } catch (e) {
      // Syncfusion throws either ArgumentError or generic Exception for both
      // password and structural problems; classify by message so the UI can
      // show the right prompt.
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'Password required', cause: e);
      }
      return Err(FailureKind.corrupted, 'File appears damaged', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  String _displayNameFor(File file) {
    final base = file.uri.pathSegments.last;
    return base.toLowerCase().endsWith('.pdf')
        ? base.substring(0, base.length - 4)
        : base;
  }

  bool _hasOcrLayer(sf.PdfDocument doc) {
    // Cheap heuristic: extract text from first page. If anything comes back,
    // there's already a text layer (OCR pass would be redundant).
    if (doc.pages.count == 0) return false;
    try {
      final text = sf.PdfTextExtractor(doc)
          .extractText(startPageIndex: 0, endPageIndex: 0);
      return text.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
