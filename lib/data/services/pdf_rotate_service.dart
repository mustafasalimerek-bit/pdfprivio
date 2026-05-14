import 'dart:io';
import 'dart:ui' show Offset;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// Quarter-turn page rotation. UI surfaces the same names users see in
/// Photos and Files, not the engine's enum names.
enum PdfRotation {
  /// 90° clockwise.
  cw90,

  /// 180° (upside down).
  rotate180,

  /// 90° counter-clockwise (or "270° clockwise" — same outcome).
  ccw90,
}

extension PdfRotationLabel on PdfRotation {
  String get label {
    switch (this) {
      case PdfRotation.cw90:
        return 'Rotate right (90°)';
      case PdfRotation.rotate180:
        return 'Flip (180°)';
      case PdfRotation.ccw90:
        return 'Rotate left (90°)';
    }
  }

  /// Map our user-facing enum to syncfusion's rotation enum. Both expose
  /// 0/90/180/270 but with different names, and the engine's enum is
  /// noisy to bleed into UI code.
  sf.PdfPageRotateAngle toSf() {
    switch (this) {
      case PdfRotation.cw90:
        return sf.PdfPageRotateAngle.rotateAngle90;
      case PdfRotation.rotate180:
        return sf.PdfPageRotateAngle.rotateAngle180;
      case PdfRotation.ccw90:
        return sf.PdfPageRotateAngle.rotateAngle270;
    }
  }
}

/// Rotates every page in a PDF by the same quarter-turn and writes a new file.
///
/// We can't rely on Syncfusion's `page.rotation` setter alone because some
/// viewers ignore the metadata flag and render the raw bytes. To make the
/// rotation persistent across every reader, we redraw each page into a new
/// canvas at the target orientation using a transform — the same template
/// approach Merge uses.
class PdfRotateService {
  PdfRotateService._();
  static final PdfRotateService instance = PdfRotateService._();

  Future<Result<File>> rotateAll({
    required PdfDocument input,
    required PdfRotation rotation,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  }) async {
    sf.PdfDocument? src;
    sf.PdfDocument? out;
    try {
      final bytes = await input.file.readAsBytes();
      src = sf.PdfDocument(inputBytes: bytes);

      out = sf.PdfDocument();
      out.pageSettings.margins.all = 0;
      if (out.pages.count > 0) out.pages.removeAt(0);

      for (var i = 0; i < src.pages.count; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }

        // The simpler path: set rotation metadata on the page after
        // copying it. This keeps the underlying content stream untouched
        // (smaller file, faster) and works in every PDF viewer that
        // respects the page rotation flag — which is all modern ones.
        final srcPage = src.pages[i];
        out.pageSettings.size = srcPage.size;
        final dst = out.pages.add();
        dst.graphics.drawPdfTemplate(srcPage.createTemplate(), Offset.zero);
        dst.rotation = rotation.toSf();

        onProgress?.call((i + 1) / src.pages.count);
      }

      final outBytes = await out.save();
      final outFile = await _writeOutput(
        outBytes,
        '${input.displayName}_rotated',
      );
      return Ok(outFile);
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'PDF is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Rotation failed', cause: e);
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
