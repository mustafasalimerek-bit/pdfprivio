import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart'
    as mlkit;

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

/// Bridges to the native Privio scanner via MethodChannel.
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

  /// True on iPhone/iPad with a rear camera (Apple VisionKit) or on
  /// Android devices with Google Play Services + camera support
  /// (ML Kit Document Scanner). Always false on iOS Simulator (no
  /// camera) and on Android emulators without Play Services.
  Future<bool> isAvailable() async {
    if (Platform.isIOS) {
      try {
        final result = await _channel.invokeMethod<bool>('isAvailable');
        return result ?? false;
      } catch (_) {
        return false;
      }
    }
    // ML Kit Document Scanner has no static "isAvailable" check — Google
    // Play Services availability is checked at scan() time. Optimistically
    // return true here; scan() will return the appropriate error if the
    // device cannot present the scanner.
    if (Platform.isAndroid) return true;
    return false;
  }

  /// Opens the native scanner in [mode]. Defaults to [ScanMode.doc].
  ///
  /// [extractMetadata] toggles the post-capture OCR + parse step on the
  /// native side. Default true — Receipt mode pulls date/amount/merchant
  /// for the Expense Ledger prompt; ID mode runs sensitive-field
  /// detection + redaction. Set to false when the caller will run its
  /// own (higher-fidelity) OCR pipeline anyway — receipt_capture_screen
  /// uses Dart-side `ReceiptExtractionService`, which is bounding-box
  /// aware, so native OCR there is wasted cycles.
  ///
  /// Returns:
  ///   Ok(ScanOutcome(pdfFile: …)) on success — metadata populated for
  ///     receipt / id modes when [extractMetadata] is true.
  ///   Ok(ScanOutcome(pdfFile: null)) on cancel.
  ///   Err(unknown) on platform / native failure.
  Future<Result<ScanOutcome>> scan({
    ScanMode mode = ScanMode.doc,
    bool extractMetadata = true,
  }) async {
    if (Platform.isIOS) {
      return _scanIOS(mode, extractMetadata);
    }
    if (Platform.isAndroid) {
      return _scanAndroid(mode);
    }
    return Err(FailureKind.unknown,
        'Document Scanner requires iOS or Android.');
  }

  Future<Result<ScanOutcome>> _scanIOS(
    ScanMode mode,
    bool extractMetadata,
  ) async {
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('scan', {
        'mode': mode.name,
        'extractMetadata': extractMetadata,
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

  /// Android implementation via Google ML Kit Document Scanner v2 — the
  /// same on-device pipeline Google Drive uses for "Scan a document".
  /// Edge detection, perspective correction, multi-page capture, and
  /// PDF assembly all run inside Google Play Services.
  ///
  /// ScanMode caveat: ML Kit's scanner only ships a single capture mode
  /// (full document scan). Receipt / Card / ID mode-specific post-
  /// processing (date+amount parse, two-side capture flow, sensitive-
  /// field detection) is not wired on Android in v1 — we accept the
  /// mode hint but the result is a plain multi-page PDF. Phase 2.5 can
  /// layer Dart-side ReceiptExtractionService + OcrService on top of
  /// the scan output to recover the metadata Apple's pipeline returns
  /// natively.
  Future<Result<ScanOutcome>> _scanAndroid(ScanMode mode) async {
    try {
      final options = mlkit.DocumentScannerOptions(
        documentFormats: const {mlkit.DocumentFormat.pdf},
        // 50-page cap matches Apple VisionKit's practical session limit
        // — long enough for a contract or multi-page lease, short enough
        // to avoid runaway memory on cheap mid-range devices.
        pageLimit: 50,
        mode: mlkit.ScannerMode.full,
        isGalleryImport: false,
      );
      final scanner = mlkit.DocumentScanner(options: options);
      final result = await scanner.scanDocument();
      await scanner.close();

      final pdfUri = result.pdf?.uri;
      if (pdfUri == null || pdfUri.isEmpty) {
        return Ok(ScanOutcome(pdfFile: null, mode: mode));
      }

      // ML Kit returns a file:// URI. Strip the scheme so we get a
      // plain absolute path the rest of the app's File-based pipeline
      // can consume.
      final path =
          pdfUri.startsWith('file://') ? pdfUri.substring(7) : pdfUri;

      return Ok(ScanOutcome(
        pdfFile: File(path),
        mode: mode,
        metadata: null,
      ));
    } on PlatformException catch (e) {
      return Err(FailureKind.unknown,
          e.message ?? 'Scanning failed.',
          cause: e);
    } catch (e) {
      return Err(FailureKind.unknown, 'Scanning failed.', cause: e);
    }
  }
}
