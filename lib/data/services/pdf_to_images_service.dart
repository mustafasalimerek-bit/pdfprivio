import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// Renders every page of an existing PDF to a JPEG file in a session-scoped
/// temp directory. Used as the front of the OCR pipeline so we can feed
/// scanned PDFs to Apple Vision (Vision works on images, not PDFs).
///
/// The render width is the long-edge target in pixels — 2000 is a good
/// balance for OCR accuracy without blowing memory on long documents.
class PdfToImagesService {
  PdfToImagesService._();
  static final PdfToImagesService instance = PdfToImagesService._();

  Future<Result<List<File>>> render({
    required PdfDocument input,
    int longEdge = 2000,
    int jpegQuality = 85,
    void Function(double progress, String message)? onProgress,
    CancellationToken? cancel,
  }) async {
    pdfx.PdfDocument? doc;
    try {
      doc = await pdfx.PdfDocument.openFile(input.path);
      final pageCount = doc.pagesCount;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final tmpRoot = await getTemporaryDirectory();
      final outDir = Directory(p.join(tmpRoot.path, 'pdfwork_render_$stamp'));
      await outDir.create(recursive: true);

      final files = <File>[];
      for (var i = 0; i < pageCount; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled');
        }
        onProgress?.call(
          i / pageCount,
          'Rendering page ${i + 1} of $pageCount',
        );

        final page = await doc.getPage(i + 1);
        try {
          final aspect = page.height / page.width;
          double w, h;
          if (page.width >= page.height) {
            w = longEdge.toDouble();
            h = (longEdge * aspect);
          } else {
            h = longEdge.toDouble();
            w = (longEdge / aspect);
          }
          final image = await page.render(
            width: w,
            height: h,
            format: pdfx.PdfPageImageFormat.jpeg,
            quality: jpegQuality,
          );
          if (image == null) continue;
          final filePath = p.join(
            outDir.path,
            'page_${(i + 1).toString().padLeft(3, '0')}.jpg',
          );
          await File(filePath).writeAsBytes(image.bytes, flush: true);
          files.add(File(filePath));
        } finally {
          await page.close();
        }
      }

      onProgress?.call(1.0, 'Done');
      return Ok(files);
    } catch (e) {
      return Err(FailureKind.unknown, 'Could not render PDF pages.', cause: e);
    } finally {
      await doc?.close();
    }
  }
}
