import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/utils/result.dart';

/// Scanner mode — selects the native side's post-processing branch and
/// the PDF assembler's page geometry (A4, tall receipt, CR80 card).
///
/// Wire string values stay stable: passed over MethodChannel to the
/// native scanner, which decodes them back into its own ScanMode enum.
/// Adding a case here also requires a matching case on the Swift side.
enum ScanMode {
  /// Standard documents: contracts, invoices, multi-page docs.
  /// Aspect 0.4-1.0, color document enhancement, OCR optional.
  doc,

  /// Receipts and thermal paper. Aggressive B&W, multi-page stitch
  /// for long receipts, OCR + date/amount extraction so the Expense
  /// Ledger can pre-fill on the way out.
  receipt,

  /// Business cards, credit cards, insurance cards. Two-side capture
  /// flow (front → flip prompt → back), side-by-side CR80 PDF layout.
  card,

  /// IDs, driver's licenses, passports. Auto-detects sensitive fields
  /// (SSN, card number, DOB, license #) and offers to redact them
  /// before saving.
  id,
}

/// Metadata returned alongside the PDF for modes that extract structure.
class ScanMetadata {
  /// Receipt mode: extracted purchase date.
  final DateTime? extractedDate;

  /// Receipt mode: extracted total amount.
  final double? extractedAmount;

  /// Receipt mode: extracted currency code (USD, EUR, TRY, GBP, …).
  final String? extractedCurrency;

  /// Receipt mode: detected merchant name.
  final String? extractedMerchant;

  /// ID mode: list of redacted field types ('ssn', 'card', 'dob',
  /// 'license'). Empty if user declined redaction or none were found.
  final List<String> redactedFields;

  /// All modes when OCR ran: raw recognised text. Useful for search
  /// indexing later.
  final String? ocrText;

  const ScanMetadata({
    this.extractedDate,
    this.extractedAmount,
    this.extractedCurrency,
    this.extractedMerchant,
    this.redactedFields = const [],
    this.ocrText,
  });
}

/// Outcome from a single scanner session.
///
/// The native scanner runs its own capture + review + PDF assembly
/// pipeline and returns the finished PDF path. `pdfFile == null` means
/// the user cancelled — empty, not an error. Mode + metadata travel
/// alongside so the caller can branch (e.g. receipt → Expense Ledger
/// prompt) without re-deriving from the PDF.
class ScanOutcome {
  final File? pdfFile;
  final ScanMode? mode;
  final ScanMetadata? metadata;

  const ScanOutcome({this.pdfFile, this.mode, this.metadata});

  bool get isEmpty => pdfFile == null;
}

/// Bridges to the native PDFPrivio scanner via MethodChannel.
///
/// The native side opens `VNDocumentCameraViewController` — the same
/// widget Apple Notes uses. ML-backed edge detection, perspective
/// correction, multi-page, and enhancement all run inside Apple's
/// framework. Mode-specific post-processing (Receipt OCR + parse, ID
/// redaction) runs on the captured UIImages before the PDF is written.
class DocumentScannerService {
  DocumentScannerService._();
  static final DocumentScannerService instance = DocumentScannerService._();

  static const MethodChannel _channel =
      MethodChannel('com.erekstudio.pdfprivio/scanner');

  /// True on iPhone/iPad with a rear camera. Always false on the
  /// iOS Simulator (no camera) and on iPads without a usable camera.
  Future<bool> isAvailable() async {
    if (!Platform.isIOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the native scanner in [mode]. Defaults to [ScanMode.doc].
  ///
  /// Returns:
  ///   Ok(ScanOutcome(pdfFile: …)) on success — metadata populated for
  ///     receipt / id modes.
  ///   Ok(ScanOutcome(pdfFile: null)) on cancel.
  ///   Err(unknown) on platform / native failure.
  Future<Result<ScanOutcome>> scan({
    ScanMode mode = ScanMode.doc,
  }) async {
    if (!Platform.isIOS) {
      return Err(FailureKind.unknown,
          'Document Scanner is iOS-only right now — Android scanner is coming.');
    }

    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('scan', {
        'mode': mode.name,
      });

      if (result == null) {
        return Ok(ScanOutcome(pdfFile: null, mode: mode));
      }
      final path = result['pdfPath'] as String?;
      if (path == null || path.isEmpty) {
        return Ok(ScanOutcome(pdfFile: null, mode: mode));
      }

      final meta = result['metadata'] as Map?;
      final metadata = meta == null
          ? null
          : ScanMetadata(
              extractedDate: meta['date'] is int
                  ? DateTime.fromMillisecondsSinceEpoch(meta['date'] as int)
                  : null,
              extractedAmount: (meta['amount'] as num?)?.toDouble(),
              extractedCurrency: meta['currency'] as String?,
              extractedMerchant: meta['merchant'] as String?,
              redactedFields:
                  (meta['redactedFields'] as List?)?.cast<String>() ?? const [],
              ocrText: meta['ocrText'] as String?,
            );

      return Ok(ScanOutcome(
        pdfFile: File(path),
        mode: mode,
        metadata: metadata,
      ));
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'unsupported':
          return Err(FailureKind.unknown,
              e.message ?? 'Document Scanner not available on this device.');
        case 'no_presenter':
          return Err(FailureKind.unknown,
              'Could not open the scanner UI — try again.');
        case 'busy':
          return Err(FailureKind.unknown, 'Scanner is already open.');
        case 'pdf_failed':
          return Err(FailureKind.unknown,
              e.message ?? 'Failed to write the scanned PDF.');
        case 'mode_unsupported':
          return Err(FailureKind.unknown,
              "This scan mode isn't supported yet.");
        default:
          return Err(FailureKind.unknown,
              e.message ?? 'Scanning failed.',
              cause: e);
      }
    } catch (e) {
      return Err(FailureKind.unknown, 'Scanning failed.', cause: e);
    }
  }
}
