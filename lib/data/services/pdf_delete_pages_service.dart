import 'dart:io';
import 'dart:ui' show Offset;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';
import 'audit_service.dart';

/// Drops the chosen pages from a PDF and writes a new file with everything
/// that wasn't selected.
///
/// We always write a new file rather than mutating the source so the user
/// can undo by going back to their original — none of our tools should ever
/// destroy the input.
class PdfDeletePagesService {
  PdfDeletePagesService._();
  static final PdfDeletePagesService instance = PdfDeletePagesService._();

  Future<Result<File>> deletePages({
    required PdfDocument input,
    required Set<int> pageIndicesToDelete,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  }) async {
    if (pageIndicesToDelete.isEmpty) {
      return Err(FailureKind.unknown, 'No pages selected to delete');
    }
    if (pageIndicesToDelete.length >= input.pageCount) {
      return Err(FailureKind.unknown,
          "Can't delete every page — at least one has to stay");
    }

    sf.PdfDocument? src;
    sf.PdfDocument? out;
    try {
      final bytes = await input.file.readAsBytes();
      src = sf.PdfDocument(inputBytes: bytes);

      out = sf.PdfDocument();
      out.pageSettings.margins.all = 0;
      if (out.pages.count > 0) out.pages.removeAt(0);

      final keptCount = input.pageCount - pageIndicesToDelete.length;
      var written = 0;

      for (var i = 0; i < src.pages.count; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }
        if (pageIndicesToDelete.contains(i)) continue;

        final srcPage = src.pages[i];
        out.pageSettings.size = srcPage.size;
        final dst = out.pages.add();
        dst.graphics.drawPdfTemplate(srcPage.createTemplate(), Offset.zero);

        written++;
        onProgress?.call(written / keptCount);
      }

      final outBytes = await out.save();
      final outFile = await _writeOutput(
        outBytes,
        '${input.displayName}_trimmed',
      );
      await AuditService.instance.record(
        tool: 'delete_pages',
        inputFile: input.file,
        outputFile: outFile,
        params: {
          'deletedCount': '${pageIndicesToDelete.length}',
          'keptCount': '$keptCount',
        },
      );
      return Ok(outFile);
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'PDF is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Delete failed', cause: e);
    } finally {
      src?.dispose();
      out?.dispose();
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
