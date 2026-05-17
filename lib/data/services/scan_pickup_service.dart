import 'dart:io';

import '../../core/utils/result.dart';
import 'document_scanner_service.dart';
import 'image_to_pdf_service.dart';

/// Glue between the native VisionKit scanner and the rest of the PDF
/// tools. Tools' empty-state "Scan" chip calls [scanToPdf]; we open
/// the scanner, render the captured pages into one Letter-format PDF,
/// and hand the resulting [File] back. The tool then routes it
/// through its existing load-from-file path (no per-tool scanner
/// integration needed).
class ScanPickupService {
  ScanPickupService._();
  static final ScanPickupService instance = ScanPickupService._();

  /// Opens the scanner and returns a single PDF combining every
  /// scanned page. Returns:
  ///   Err(cancelled) — user cancelled or scanned no pages.
  ///   Err(unknown) — scanner unavailable (simulator / no camera) or
  ///     PDF assembly failed.
  Future<Result<File>> scanToPdf() async {
    final scanRes = await DocumentScannerService.instance.scan();
    if (scanRes is Err<ScanOutcome>) {
      return Err(scanRes.kind, scanRes.message, cause: scanRes.cause);
    }
    final pages = (scanRes as Ok<ScanOutcome>).value.pages;
    if (pages.isEmpty) {
      // User cancelled mid-scan. Surface as a quiet cancellation so the
      // tool can no-op without a snackbar.
      return Err(FailureKind.cancelled, 'No pages scanned');
    }
    return ImageToPdfService.instance.convert(
      images: pages,
      paperSize: PdfPaperSize.letter,
      outputName: 'scan',
    );
  }
}
