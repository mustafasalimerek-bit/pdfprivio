import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import 'audit_service.dart';

/// Page-size preset used when stitching images into a PDF.
///
/// `auto` falls back to "fit a Letter page" but renders the image at the
/// page's full bounds (the image proportions are preserved by `pw.BoxFit`).
/// We could instead emit one custom page per image at its native ratio,
/// but that produces a jumpy PDF when the user mixes phone photos and
/// screenshots — single uniform page size scans better.
enum PdfPaperSize { letter, a4, legal, auto }

extension PdfPaperSizeLabel on PdfPaperSize {
  String get label {
    switch (this) {
      case PdfPaperSize.letter:
        return 'US Letter';
      case PdfPaperSize.a4:
        return 'A4';
      case PdfPaperSize.legal:
        return 'US Legal';
      case PdfPaperSize.auto:
        return 'Auto-fit each image';
    }
  }

  pw_pdf.PdfPageFormat get format {
    switch (this) {
      case PdfPaperSize.letter:
        return pw_pdf.PdfPageFormat.letter;
      case PdfPaperSize.a4:
        return pw_pdf.PdfPageFormat.a4;
      case PdfPaperSize.legal:
        return pw_pdf.PdfPageFormat.legal;
      case PdfPaperSize.auto:
        return pw_pdf.PdfPageFormat.letter; // default canvas, image scales
    }
  }
}

class ImageToPdfService {
  ImageToPdfService._();
  static final ImageToPdfService instance = ImageToPdfService._();

  /// Builds a PDF where each image gets a page sized per [paperSize].
  ///
  /// [paperSize.auto] sizes each page to the image's native aspect ratio
  /// (clamped to a reasonable max), useful for receipts and screenshots
  /// where forcing Letter introduces big margins.
  Future<Result<File>> convert({
    required List<File> images,
    PdfPaperSize paperSize = PdfPaperSize.letter,
    String? outputName,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  }) async {
    if (images.isEmpty) {
      return Err(FailureKind.unknown, 'No images selected');
    }
    try {
      final pdf = pw.Document(compress: true);

      for (var i = 0; i < images.length; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }

        final bytes = await images[i].readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          // Skip silently — better to ship a PDF missing one bad image than
          // to throw the whole batch away on a single un-decodable file.
          continue;
        }

        final memImage = pw.MemoryImage(bytes);
        final pageFormat = paperSize == PdfPaperSize.auto
            ? _autoFormatFor(decoded.width, decoded.height)
            : paperSize.format;

        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: paperSize == PdfPaperSize.auto
                ? pw.EdgeInsets.zero
                : const pw.EdgeInsets.all(24),
            build: (ctx) => pw.Center(
              child: pw.Image(memImage, fit: pw.BoxFit.contain),
            ),
          ),
        );

        onProgress?.call((i + 1) / images.length);
      }

      final outBytes = await pdf.save();
      final file = await _writeOutput(outBytes, outputName ?? 'images');
      await AuditService.instance.record(
        tool: 'image_to_pdf',
        outputFile: file,
        params: {
          'imageCount': '${images.length}',
          'paperSize': paperSize.name,
        },
      );
      return Ok(file);
    } catch (e) {
      return Err(FailureKind.unknown, 'Image conversion failed', cause: e);
    }
  }

  /// Builds a page format scaled to the image's aspect ratio with a sensible
  /// max so a 5000×8000 photo doesn't produce a 70-inch tall PDF page.
  pw_pdf.PdfPageFormat _autoFormatFor(int imgW, int imgH) {
    const maxLong = 1400.0; // PDF points; ~19.5 inches on a 72 DPI canvas
    final wider = imgW >= imgH;
    final long = maxLong;
    final short = (long * (wider ? imgH / imgW : imgW / imgH));
    return wider
        ? pw_pdf.PdfPageFormat(long, short)
        : pw_pdf.PdfPageFormat(short, long);
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
