import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// Five corner/edge positions where a signature commonly lands on a page.
/// Custom drag-to-place is a Pro feature and added in a later pass.
enum SignaturePosition {
  bottomRight,
  bottomLeft,
  bottomCenter,
  topRight,
  topLeft,
}

extension SignaturePositionLabel on SignaturePosition {
  String get label {
    switch (this) {
      case SignaturePosition.bottomRight:
        return 'Bottom-right';
      case SignaturePosition.bottomLeft:
        return 'Bottom-left';
      case SignaturePosition.bottomCenter:
        return 'Bottom-center';
      case SignaturePosition.topRight:
        return 'Top-right';
      case SignaturePosition.topLeft:
        return 'Top-left';
    }
  }
}

/// Stamps a signature image onto one page of a PDF and writes a new file.
///
/// We never mutate the source — even an in-place "sign and replace" flow
/// goes through a copy on disk first, because there's no scenario where
/// destroying the user's original is the right behaviour.
///
/// The audit footer (timestamp + document hash + "Signed with PDFPrivio")
/// gives us a starting point for the full ESIGN/UETA chain we'll need
/// before this lands in the lawyer-targeted version of the app. The hash
/// commits the signature to the pre-signed contents of the document.
class PdfSignService {
  PdfSignService._();
  static final PdfSignService instance = PdfSignService._();

  static const double _sigWidthPt = 140;
  static const double _sigHeightPt = 60;
  static const double _margin = 36;
  static const double _footerOffsetBelowSig = 6;
  static const double _footerFontSize = 7;

  Future<Result<File>> sign({
    required PdfDocument input,
    required Uint8List signaturePng,
    required int pageIndex,
    required SignaturePosition position,
    String? signerName,
  }) async {
    if (pageIndex < 0 || pageIndex >= input.pageCount) {
      return Err(FailureKind.unknown, 'Page index out of range');
    }

    sf.PdfDocument? doc;
    try {
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      final hashHex = sha256.convert(bytes).toString();
      final page = doc.pages[pageIndex];
      final pageSize = page.size;
      final rect = _rectFor(position, pageSize);

      final bitmap = sf.PdfBitmap(signaturePng);
      page.graphics.drawImage(bitmap, rect);

      _drawAuditFooter(
        page: page,
        rect: rect,
        documentHash: hashHex,
        signerName: signerName,
      );

      final outBytes = await doc.save();
      final outFile = await _writeOutput(
        outBytes,
        '${input.displayName}_signed',
      );
      return Ok(outFile);
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'PDF is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Signing failed', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  Rect _rectFor(SignaturePosition pos, Size pageSize) {
    final w = _sigWidthPt;
    final h = _sigHeightPt;
    switch (pos) {
      case SignaturePosition.bottomRight:
        return Rect.fromLTWH(
          pageSize.width - w - _margin,
          pageSize.height - h - _margin,
          w,
          h,
        );
      case SignaturePosition.bottomLeft:
        return Rect.fromLTWH(_margin, pageSize.height - h - _margin, w, h);
      case SignaturePosition.bottomCenter:
        return Rect.fromLTWH(
          (pageSize.width - w) / 2,
          pageSize.height - h - _margin,
          w,
          h,
        );
      case SignaturePosition.topRight:
        return Rect.fromLTWH(pageSize.width - w - _margin, _margin, w, h);
      case SignaturePosition.topLeft:
        return Rect.fromLTWH(_margin, _margin, w, h);
    }
  }

  void _drawAuditFooter({
    required sf.PdfPage page,
    required Rect rect,
    required String documentHash,
    String? signerName,
  }) {
    final now = DateTime.now().toUtc();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} UTC';

    final hashShort = documentHash.substring(0, 12);
    final signerLine =
        signerName == null || signerName.isEmpty ? '' : '$signerName · ';
    final auditText =
        'Signed $signerLine$timestamp · doc-sha256:$hashShort · PDFPrivio';

    final font = sf.PdfStandardFont(
      sf.PdfFontFamily.helvetica,
      _footerFontSize,
    );
    final brush = sf.PdfSolidBrush(sf.PdfColor(80, 80, 80));

    // Place the footer just below the signature rect, full-width so wrapping
    // is impossible to misread.
    final footerRect = Rect.fromLTWH(
      rect.left,
      rect.bottom + _footerOffsetBelowSig,
      rect.width,
      _footerFontSize * 2.2,
    );

    page.graphics.drawString(
      auditText,
      font,
      brush: brush,
      bounds: footerRect,
      format: sf.PdfStringFormat(
        alignment: sf.PdfTextAlignment.left,
        lineAlignment: sf.PdfVerticalAlignment.top,
        wordWrap: sf.PdfWordWrapType.character,
      ),
    );
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

