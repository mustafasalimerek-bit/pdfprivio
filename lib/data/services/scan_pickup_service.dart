import 'dart:io';

import '../../core/utils/result.dart';
import 'document_scanner_service.dart';

/// Glue between the native scanner and the rest of the PDF tools.
///
/// Tools' empty-state "Scan" chip calls [scanToPdf]; the native scanner
/// captures the pages, runs perspective correction + the chosen
/// enhancement, and writes a finished PDF to a tmp path. We just unwrap
/// that file and hand it back — the tool then routes it through its
/// existing load-from-file path.
class ScanPickupService {
  ScanPickupService._();
  static final ScanPickupService instance = ScanPickupService._();

  /// Opens the scanner and returns the assembled PDF. Returns:
  ///   Err(cancelled) — user cancelled or scanned no pages.
  ///   Err(unknown)   — scanner unavailable (simulator / no camera) or
  ///                    native PDF assembly failed.
  Future<Result<File>> scanToPdf() async {
    final scanRes = await DocumentScannerService.instance.scan();
    if (scanRes is Err<ScanOutcome>) {
      return Err(scanRes.kind, scanRes.message, cause: scanRes.cause);
    }
    final outcome = (scanRes as Ok<ScanOutcome>).value;
    final pdf = outcome.pdfFile;
    if (pdf == null) {
      // User cancelled. Surface as a quiet cancellation so the tool can
      // no-op without a snackbar.
      return Err(FailureKind.cancelled, 'No pages scanned');
    }
    return Ok(pdf);
  }
}
