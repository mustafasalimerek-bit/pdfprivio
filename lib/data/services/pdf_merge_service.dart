import 'dart:io';
import 'dart:ui' show Offset;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// Merges multiple PDFs into one, preserving each source page's original
/// trim size (so a Letter page in source #1 stays Letter in the output even
/// when source #2 is A4).
///
/// Designed for the "100 PDFs at once" workload: sources are processed one
/// at a time and immediately disposed, so peak memory stays roughly equal
/// to the largest single source plus the growing output, not the sum of
/// all inputs.
class PdfMergeService {
  PdfMergeService._();
  static final PdfMergeService instance = PdfMergeService._();

  /// Merges [documents] in order. Calls [onProgress] with a value in
  /// [0.0, 1.0] after each source is appended. Returns the path to the
  /// merged file.
  ///
  /// [outputName] is the base name (without extension). If null, we derive
  /// a smart name from the inputs (see `_suggestOutputName`).
  Future<Result<File>> merge({
    required List<PdfDocument> documents,
    String? outputName,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  }) async {
    if (documents.isEmpty) {
      return Err(FailureKind.unknown, 'No documents to merge');
    }
    if (documents.length == 1) {
      return _copyOnly(documents.single, outputName);
    }

    sf.PdfDocument? out;
    try {
      out = sf.PdfDocument();
      // Drop default margins so source page content lands flush in the
      // output canvas; we'll set the size per-source below.
      out.pageSettings.margins.all = 0;

      // Output starts with one default A4 page we don't want; remove it
      // before we begin appending real content.
      if (out.pages.count > 0) {
        out.pages.removeAt(0);
      }

      for (var i = 0; i < documents.length; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }

        await _appendSource(out, documents[i].file);
        onProgress?.call((i + 1) / documents.length);
      }

      final outputBytes = await out.save();
      final outFile = await _writeOutput(
        outputBytes,
        outputName ?? _suggestOutputName(documents),
      );
      return Ok(outFile);
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword,
            'One of the PDFs is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Merge failed', cause: e);
    } finally {
      out?.dispose();
    }
  }

  Future<void> _appendSource(sf.PdfDocument out, File source) async {
    final bytes = await source.readAsBytes();
    sf.PdfDocument? src;
    try {
      src = sf.PdfDocument(inputBytes: bytes);
      for (var p = 0; p < src.pages.count; p++) {
        final srcPage = src.pages[p];
        // Re-create the destination page at the source's trim size so
        // Letter / A4 / custom pages stay visually faithful.
        out.pageSettings.size = srcPage.size;
        final dst = out.pages.add();
        final template = srcPage.createTemplate();
        dst.graphics.drawPdfTemplate(template, Offset.zero);
      }
    } finally {
      src?.dispose();
    }
  }

  Future<Result<File>> _copyOnly(PdfDocument doc, String? outputName) async {
    try {
      final bytes = await doc.file.readAsBytes();
      final file = await _writeOutput(
        bytes,
        outputName ?? '${doc.displayName}_copy',
      );
      return Ok(file);
    } catch (e) {
      return Err(FailureKind.unknown, 'Copy failed', cause: e);
    }
  }

  Future<File> _writeOutput(List<int> bytes, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = _sanitize(baseName);
    final path = p.join(dir.path, '$safe.pdf');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _sanitize(String name) {
    // Filenames written to the app sandbox don't need full POSIX/NTFS
    // escaping but stripping path separators avoids accidental directory
    // creation.
    return name.replaceAll(RegExp(r'[\\/]'), '_').trim();
  }

  /// Derives a merged-document name from the inputs.
  ///
  /// - 2 docs: `<a>_and_<b>`
  /// - 3+ docs: `<a>_and_<n>_more` (keeps filenames scannable)
  String _suggestOutputName(List<PdfDocument> docs) {
    final first = docs.first.displayName;
    if (docs.length == 2) {
      return '${first}_and_${docs[1].displayName}';
    }
    return '${first}_and_${docs.length - 1}_more';
  }
}
