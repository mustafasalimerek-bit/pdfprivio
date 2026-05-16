import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/compression_settings.dart';
import '../models/pdf_document.dart';
import 'audit_service.dart';

/// Outcome of a successful compression — exposes both files so the result
/// screen can show "1.4 MB → 320 KB · 77% saved".
class CompressionOutcome {
  final File original;
  final File compressed;
  final int originalBytes;
  final int compressedBytes;
  final Duration elapsed;

  const CompressionOutcome({
    required this.original,
    required this.compressed,
    required this.originalBytes,
    required this.compressedBytes,
    required this.elapsed,
  });

  double get savingRatio =>
      originalBytes == 0 ? 0.0 : (originalBytes - compressedBytes) / originalBytes;
}

/// Two-pass PDF compression.
///
/// Pass 1 (structural): re-serialize the PDF with Syncfusion's "best"
/// compression. Cheap, preserves text, lossless. Usually gets 5–30% off
/// text-heavy documents and nothing off image-heavy ones.
///
/// Pass 2 (re-render): if pass 1 didn't shrink enough (or the user picked
/// the most aggressive preset), render every page to a JPEG at the chosen
/// DPI and rebuild the PDF from those JPEGs. Image-heavy PDFs lose 60–90%
/// here at the cost of selectable text.
class PdfCompressionService {
  PdfCompressionService._();
  static final PdfCompressionService instance = PdfCompressionService._();

  Future<Result<CompressionOutcome>> compress({
    required PdfDocument input,
    required CompressionSettings settings,
    void Function(double progress, String message)? onProgress,
    CancellationToken? cancel,
  }) async {
    final stopwatch = Stopwatch()..start();
    onProgress?.call(0.02, 'Preparing…');

    final inputFile = input.file;
    final outPath = await _outputPath(input);

    try {
      // --- Pass 1: structural ---------------------------------------------
      onProgress?.call(0.05, 'Optimizing structure…');
      final structuralOk = await _compressStructural(
        inputFile: inputFile,
        outputPath: outPath,
        onProgress: (p, m) => onProgress?.call(0.05 + p * 0.35, m),
      );

      if (cancel?.isCancelled ?? false) {
        return Err(FailureKind.cancelled, 'Cancelled by user');
      }

      final originalSize = input.sizeBytes;
      final structuralSize = await _fileSize(outPath);
      final structuralRatio = structuralSize == 0
          ? 0.0
          : (originalSize - structuralSize) / originalSize;

      // Decide whether to attempt the re-render pass. The lowest preset
      // always re-renders (it exists to be aggressive); otherwise we only
      // re-render if structural pass didn't help much.
      final shouldRerender = settings.level == CompressionLevel.low ||
          structuralRatio < 0.10 ||
          !structuralOk;

      if (shouldRerender) {
        onProgress?.call(0.45, 'Re-encoding pages…');
        await _compressByRerender(
          inputFile: inputFile,
          outputPath: outPath,
          settings: settings,
          cancel: cancel,
          onProgress: (p, m) => onProgress?.call(0.45 + p * 0.53, m),
        );
      }

      if (cancel?.isCancelled ?? false) {
        return Err(FailureKind.cancelled, 'Cancelled by user');
      }

      onProgress?.call(0.99, 'Finalizing…');
      final finalSize = await _fileSize(outPath);
      stopwatch.stop();
      onProgress?.call(1.0, 'Ready');

      await AuditService.instance.record(
        tool: 'compress',
        inputFile: inputFile,
        outputFile: File(outPath),
        params: {
          'level': settings.level.name,
          'originalBytes': '$originalSize',
          'compressedBytes': '$finalSize',
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
        },
      );

      return Ok(CompressionOutcome(
        original: inputFile,
        compressed: File(outPath),
        originalBytes: originalSize,
        compressedBytes: finalSize,
        elapsed: stopwatch.elapsed,
      ));
    } catch (e) {
      stopwatch.stop();
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword, 'PDF is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Compression failed', cause: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Pass 1
  // ---------------------------------------------------------------------------

  Future<bool> _compressStructural({
    required File inputFile,
    required String outputPath,
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      final bytes = await inputFile.readAsBytes();
      onProgress?.call(0.3, 'Analyzing…');

      final document = sf.PdfDocument(inputBytes: bytes);
      document.compressionLevel = sf.PdfCompressionLevel.best;
      onProgress?.call(0.7, 'Writing…');
      final out = await document.save();
      document.dispose();

      await File(outputPath).writeAsBytes(out, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Pass 2
  // ---------------------------------------------------------------------------

  Future<void> _compressByRerender({
    required File inputFile,
    required String outputPath,
    required CompressionSettings settings,
    CancellationToken? cancel,
    void Function(double progress, String message)? onProgress,
  }) async {
    final doc = await pdfx.PdfDocument.openFile(inputFile.path);
    final pageCount = doc.pagesCount;
    final pdf = pw.Document(
      compress: true,
      version: pw_pdf.PdfVersion.pdf_1_5,
    );

    final scale = settings.dpi / 72.0; // PDF default is 72 DPI

    try {
      for (var i = 1; i <= pageCount; i++) {
        if (cancel?.isCancelled ?? false) return;

        final progress = (i - 1) / pageCount;
        onProgress?.call(progress, 'Page $i of $pageCount…');

        final page = await doc.getPage(i);
        try {
          final renderWidth = (page.width * scale).round();
          final renderHeight = (page.height * scale).round();

          final pageImage = await page.render(
            width: renderWidth.toDouble(),
            height: renderHeight.toDouble(),
            format: pdfx.PdfPageImageFormat.jpeg,
            quality: 100,
          );
          if (pageImage == null) continue;

          final jpegBytes = await _recompressJpeg(pageImage.bytes, settings);

          final pdfImage = pw.MemoryImage(jpegBytes);
          pdf.addPage(
            pw.Page(
              pageFormat: pw_pdf.PdfPageFormat(
                page.width.toDouble(),
                page.height.toDouble(),
              ),
              build: (ctx) => pw.Center(
                child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
              ),
            ),
          );
        } finally {
          await page.close();
        }
      }

      onProgress?.call(0.95, 'Writing PDF…');
      final outBytes = await pdf.save();
      await File(outputPath).writeAsBytes(outBytes, flush: true);
    } finally {
      await doc.close();
    }
  }

  Future<Uint8List> _recompressJpeg(
    Uint8List source,
    CompressionSettings settings,
  ) async {
    final decoded = img.decodeJpg(source);
    if (decoded == null) return source;

    img.Image working = decoded;
    if (settings.grayscale) {
      working = img.grayscale(working);
    }

    return Uint8List.fromList(
      img.encodeJpg(working, quality: settings.jpegQuality),
    );
  }

  // ---------------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------------

  Future<String> _outputPath(PdfDocument input) async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, '${input.displayName}_compressed.pdf');
  }

  Future<int> _fileSize(String path) async {
    final f = File(path);
    if (!await f.exists()) return 0;
    final stat = await f.stat();
    return stat.size;
  }
}
