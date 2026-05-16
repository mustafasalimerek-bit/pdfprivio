import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';
import 'audit_service.dart';

/// Visual layout of the watermark across each page.
enum WatermarkLayout {
  /// Large diagonal banner — the DRAFT / CONFIDENTIAL convention.
  diagonal,

  /// Horizontal text centred mid-page.
  horizontalCenter,

  /// Small repeated tile across the entire page surface.
  tile,
}

extension WatermarkLayoutLabel on WatermarkLayout {
  String get label {
    switch (this) {
      case WatermarkLayout.diagonal:
        return 'Diagonal banner';
      case WatermarkLayout.horizontalCenter:
        return 'Horizontal center';
      case WatermarkLayout.tile:
        return 'Tile across page';
    }
  }
}

enum WatermarkOpacity { faint, medium, bold }

extension WatermarkOpacityValue on WatermarkOpacity {
  double get alpha {
    switch (this) {
      case WatermarkOpacity.faint:
        return 0.12;
      case WatermarkOpacity.medium:
        return 0.22;
      case WatermarkOpacity.bold:
        return 0.40;
    }
  }

  String get label {
    switch (this) {
      case WatermarkOpacity.faint:
        return 'Faint';
      case WatermarkOpacity.medium:
        return 'Medium';
      case WatermarkOpacity.bold:
        return 'Bold';
    }
  }
}

class WatermarkSettings {
  final String text;
  final WatermarkLayout layout;
  final WatermarkOpacity opacity;

  const WatermarkSettings({
    required this.text,
    required this.layout,
    required this.opacity,
  });
}

class PdfWatermarkService {
  PdfWatermarkService._();
  static final PdfWatermarkService instance = PdfWatermarkService._();

  Future<Result<File>> stamp({
    required PdfDocument input,
    required WatermarkSettings settings,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  }) async {
    if (settings.text.trim().isEmpty) {
      return Err(FailureKind.unknown, 'Watermark text cannot be empty');
    }

    sf.PdfDocument? doc;
    try {
      final bytes = await input.file.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      for (var i = 0; i < doc.pages.count; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }

        _stampPage(doc.pages[i], settings);
        onProgress?.call((i + 1) / doc.pages.count);
      }

      final outBytes = await doc.save();
      final outFile = await _writeOutput(
        outBytes,
        '${input.displayName}_watermarked',
      );
      await AuditService.instance.record(
        tool: 'watermark',
        inputFile: input.file,
        outputFile: outFile,
        params: {
          'text': settings.text,
          'layout': settings.layout.name,
          'opacity': settings.opacity.name,
        },
      );
      return Ok(outFile);
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'PDF is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Watermark failed', cause: e);
    } finally {
      doc?.dispose();
    }
  }

  void _stampPage(sf.PdfPage page, WatermarkSettings settings) {
    final size = page.size;
    final text = settings.text.toUpperCase();

    final alpha = (settings.opacity.alpha * 255).round();
    final brush = sf.PdfSolidBrush(sf.PdfColor(80, 80, 80, alpha));

    switch (settings.layout) {
      case WatermarkLayout.diagonal:
        _drawDiagonal(page, text, brush, size);
      case WatermarkLayout.horizontalCenter:
        _drawHorizontalCenter(page, text, brush, size);
      case WatermarkLayout.tile:
        _drawTile(page, text, brush, size);
    }
  }

  void _drawDiagonal(
    sf.PdfPage page,
    String text,
    sf.PdfBrush brush,
    Size size,
  ) {
    final fontSize = (size.width * 0.13).clamp(36.0, 96.0);
    final font = sf.PdfStandardFont(
      sf.PdfFontFamily.helvetica,
      fontSize,
      style: sf.PdfFontStyle.bold,
    );

    final g = page.graphics;
    g.save();
    g.translateTransform(size.width / 2, size.height / 2);
    g.rotateTransform(-30);
    g.drawString(
      text,
      font,
      brush: brush,
      bounds: Rect.fromLTWH(-size.width, -fontSize, size.width * 2,
          fontSize * 2),
      format: sf.PdfStringFormat(
        alignment: sf.PdfTextAlignment.center,
        lineAlignment: sf.PdfVerticalAlignment.middle,
      ),
    );
    g.restore();
  }

  void _drawHorizontalCenter(
    sf.PdfPage page,
    String text,
    sf.PdfBrush brush,
    Size size,
  ) {
    final fontSize = (size.width * 0.08).clamp(24.0, 64.0);
    final font = sf.PdfStandardFont(
      sf.PdfFontFamily.helvetica,
      fontSize,
      style: sf.PdfFontStyle.bold,
    );

    page.graphics.drawString(
      text,
      font,
      brush: brush,
      bounds: Rect.fromLTWH(
        0,
        size.height / 2 - fontSize,
        size.width,
        fontSize * 2,
      ),
      format: sf.PdfStringFormat(
        alignment: sf.PdfTextAlignment.center,
        lineAlignment: sf.PdfVerticalAlignment.middle,
      ),
    );
  }

  void _drawTile(
    sf.PdfPage page,
    String text,
    sf.PdfBrush brush,
    Size size,
  ) {
    const fontSize = 18.0;
    final font = sf.PdfStandardFont(
      sf.PdfFontFamily.helvetica,
      fontSize,
      style: sf.PdfFontStyle.bold,
    );

    final g = page.graphics;
    const horizontalStep = 200.0;
    const verticalStep = 120.0;

    for (var y = -50.0; y < size.height + 50; y += verticalStep) {
      for (var x = -50.0; x < size.width + 50; x += horizontalStep) {
        g.save();
        g.translateTransform(x, y);
        g.rotateTransform(-25);
        g.drawString(
          text,
          font,
          brush: brush,
          bounds: const Rect.fromLTWH(0, 0, 200, 40),
        );
        g.restore();
      }
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
