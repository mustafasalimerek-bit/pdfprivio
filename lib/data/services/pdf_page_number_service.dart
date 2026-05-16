import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';
import 'audit_service.dart';

/// How the page number text renders.
///
/// We keep the formats short and well-known. Anything more exotic (Roman
/// numerals, lettered pages, section-aware numbering) is firmly post-MVP.
enum PageNumberFormat {
  /// Just the number: "1", "2", "3".
  number,

  /// Number / total: "1/20".
  numberOverTotal,

  /// "Page 1".
  pagePrefix,

  /// "Page 1 of 20".
  pageOfTotal,
}

extension PageNumberFormatLabel on PageNumberFormat {
  String example(int current, int total) {
    switch (this) {
      case PageNumberFormat.number:
        return '$current';
      case PageNumberFormat.numberOverTotal:
        return '$current/$total';
      case PageNumberFormat.pagePrefix:
        return 'Page $current';
      case PageNumberFormat.pageOfTotal:
        return 'Page $current of $total';
    }
  }

  String get label {
    switch (this) {
      case PageNumberFormat.number:
        return 'Number only · 1';
      case PageNumberFormat.numberOverTotal:
        return 'Slash · 1/20';
      case PageNumberFormat.pagePrefix:
        return 'Page N · Page 1';
      case PageNumberFormat.pageOfTotal:
        return 'Page N of M · Page 1 of 20';
    }
  }
}

enum PageNumberPosition {
  bottomRight,
  bottomLeft,
  bottomCenter,
  topRight,
  topLeft,
}

extension PageNumberPositionLabel on PageNumberPosition {
  String get label {
    switch (this) {
      case PageNumberPosition.bottomRight:
        return 'Bottom-right';
      case PageNumberPosition.bottomLeft:
        return 'Bottom-left';
      case PageNumberPosition.bottomCenter:
        return 'Bottom-center';
      case PageNumberPosition.topRight:
        return 'Top-right';
      case PageNumberPosition.topLeft:
        return 'Top-left';
    }
  }
}

class PageNumberSettings {
  final PageNumberFormat format;
  final PageNumberPosition position;
  final int startNumber;

  /// Pages to skip at the beginning before numbering starts (e.g. 1 means
  /// the cover page is left blank, numbering starts on page 2 as "1").
  final int skipFirst;

  const PageNumberSettings({
    required this.format,
    required this.position,
    required this.startNumber,
    required this.skipFirst,
  });
}

class PdfPageNumberService {
  PdfPageNumberService._();
  static final PdfPageNumberService instance = PdfPageNumberService._();

  static const double _fontSize = 10;
  static const double _margin = 28;
  static const double _stampWidth = 200;
  static const double _stampHeight = 14;

  Future<Result<File>> stamp({
    required PdfDocument input,
    required PageNumberSettings settings,
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
      );
      final brush = sf.PdfSolidBrush(sf.PdfColor(70, 70, 70));

      final totalNumberedPages = doc.pages.count - settings.skipFirst;
      var stamped = 0;

      for (var i = 0; i < doc.pages.count; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }

        // Skip the leading cover pages — they keep the visual title page
        // intact while the body of the document still gets clean numbering.
        if (i < settings.skipFirst) {
          continue;
        }

        final logicalIndex = i - settings.skipFirst;
        final current = settings.startNumber + logicalIndex;
        final total = settings.startNumber + totalNumberedPages - 1;

        final text = settings.format.example(current, total);
        final page = doc.pages[i];
        final rect = _rectFor(settings.position, page.size);

        page.graphics.drawString(
          text,
          font,
          brush: brush,
          bounds: rect,
          format: sf.PdfStringFormat(
            alignment: _hAlignFor(settings.position),
            lineAlignment: sf.PdfVerticalAlignment.middle,
          ),
        );

        stamped++;
        onProgress?.call(stamped / totalNumberedPages.clamp(1, 1 << 20));
      }

      final outBytes = await doc.save();
      final outFile = await _writeOutput(
        outBytes,
        '${input.displayName}_numbered',
      );
      await AuditService.instance.record(
        tool: 'page_numbers',
        inputFile: input.file,
        outputFile: outFile,
        params: {
          'format': settings.format.name,
          'position': settings.position.name,
          'startNumber': '${settings.startNumber}',
          'skipFirst': '${settings.skipFirst}',
        },
      );
      return Ok(outFile);
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'PDF is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Page numbering failed', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  Rect _rectFor(PageNumberPosition pos, dynamic pageSize) {
    final w = _stampWidth;
    final h = _stampHeight;
    switch (pos) {
      case PageNumberPosition.bottomRight:
        return Rect.fromLTWH(
          pageSize.width - w - _margin,
          pageSize.height - h - _margin,
          w,
          h,
        );
      case PageNumberPosition.bottomLeft:
        return Rect.fromLTWH(_margin, pageSize.height - h - _margin, w, h);
      case PageNumberPosition.bottomCenter:
        return Rect.fromLTWH(
          (pageSize.width - w) / 2,
          pageSize.height - h - _margin,
          w,
          h,
        );
      case PageNumberPosition.topRight:
        return Rect.fromLTWH(pageSize.width - w - _margin, _margin, w, h);
      case PageNumberPosition.topLeft:
        return Rect.fromLTWH(_margin, _margin, w, h);
    }
  }

  sf.PdfTextAlignment _hAlignFor(PageNumberPosition pos) {
    switch (pos) {
      case PageNumberPosition.bottomLeft:
      case PageNumberPosition.topLeft:
        return sf.PdfTextAlignment.left;
      case PageNumberPosition.bottomCenter:
        return sf.PdfTextAlignment.center;
      case PageNumberPosition.bottomRight:
      case PageNumberPosition.topRight:
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
