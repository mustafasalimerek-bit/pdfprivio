import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// Where on each page the Bates stamp lands.
enum BatesPosition {
  bottomRight,
  bottomLeft,
  bottomCenter,
  topRight,
  topLeft,
}

extension BatesPositionLabel on BatesPosition {
  String get label {
    switch (this) {
      case BatesPosition.bottomRight:
        return 'Bottom-right';
      case BatesPosition.bottomLeft:
        return 'Bottom-left';
      case BatesPosition.bottomCenter:
        return 'Bottom-center';
      case BatesPosition.topRight:
        return 'Top-right';
      case BatesPosition.topLeft:
        return 'Top-left';
    }
  }
}

/// Configuration for a Bates stamping run.
///
/// Bates numbering is the legal-industry convention of stamping every page
/// of a document with a unique, sequential identifier so that pages can be
/// referenced unambiguously across discovery, briefs, and depositions.
/// A typical stamp reads "ACME-00012" — prefix + zero-padded counter.
class BatesSettings {
  final String prefix;
  final int startNumber;
  final int padding;
  final String separator;
  final BatesPosition position;

  const BatesSettings({
    required this.prefix,
    required this.startNumber,
    required this.padding,
    required this.separator,
    required this.position,
  });

  String stampFor(int pageIndex) {
    final n = startNumber + pageIndex;
    final padded = n.toString().padLeft(padding, '0');
    if (prefix.isEmpty) return padded;
    return '$prefix$separator$padded';
  }
}

/// Stamps a Bates identifier on every page of a PDF.
///
/// The font size is fixed at 9pt — bigger than a footer note (so it's
/// findable at a glance during deposition) but small enough not to
/// obscure existing page content. The text colour is a near-black grey
/// matching common legal-printing conventions.
class PdfBatesService {
  PdfBatesService._();
  static final PdfBatesService instance = PdfBatesService._();

  static const double _fontSize = 9;
  static const double _margin = 22;
  static const double _stampWidth = 160;
  static const double _stampHeight = 14;

  Future<Result<File>> stamp({
    required PdfDocument input,
    required BatesSettings settings,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  }) async {
    sf.PdfDocument? doc;
    try {
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      final font = sf.PdfStandardFont(
        sf.PdfFontFamily.helvetica,
        _fontSize,
        style: sf.PdfFontStyle.bold,
      );
      final brush = sf.PdfSolidBrush(sf.PdfColor(40, 40, 40));

      for (var i = 0; i < doc.pages.count; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }

        final page = doc.pages[i];
        final rect = _rectFor(settings.position, page.size);
        final stamp = settings.stampFor(i);

        page.graphics.drawString(
          stamp,
          font,
          brush: brush,
          bounds: rect,
          format: sf.PdfStringFormat(
            alignment: _hAlignFor(settings.position),
            lineAlignment: sf.PdfVerticalAlignment.middle,
          ),
        );

        onProgress?.call((i + 1) / doc.pages.count);
      }

      final outBytes = await doc.save();
      final outFile = await _writeOutput(
        outBytes,
        '${input.displayName}_bates',
      );
      return Ok(outFile);
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'PDF is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Bates stamping failed', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  Rect _rectFor(BatesPosition pos, dynamic pageSize) {
    final w = _stampWidth;
    final h = _stampHeight;
    switch (pos) {
      case BatesPosition.bottomRight:
        return Rect.fromLTWH(
          pageSize.width - w - _margin,
          pageSize.height - h - _margin,
          w,
          h,
        );
      case BatesPosition.bottomLeft:
        return Rect.fromLTWH(_margin, pageSize.height - h - _margin, w, h);
      case BatesPosition.bottomCenter:
        return Rect.fromLTWH(
          (pageSize.width - w) / 2,
          pageSize.height - h - _margin,
          w,
          h,
        );
      case BatesPosition.topRight:
        return Rect.fromLTWH(pageSize.width - w - _margin, _margin, w, h);
      case BatesPosition.topLeft:
        return Rect.fromLTWH(_margin, _margin, w, h);
    }
  }

  sf.PdfTextAlignment _hAlignFor(BatesPosition pos) {
    switch (pos) {
      case BatesPosition.bottomLeft:
      case BatesPosition.topLeft:
        return sf.PdfTextAlignment.left;
      case BatesPosition.bottomCenter:
        return sf.PdfTextAlignment.center;
      case BatesPosition.bottomRight:
      case BatesPosition.topRight:
        return sf.PdfTextAlignment.right;
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
