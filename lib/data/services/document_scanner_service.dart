import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/result.dart';

/// Outcome from a single scanner session.
///
/// The native scanner (custom AVFoundation UI or VisionKit fallback)
/// runs its own multi-page capture + review loop entirely on the iOS
/// side and writes a finished PDF to a temp file. We return that path
/// so the Flutter UI can hand it straight to MergeResultScreen without
/// another assembly pass.
///
/// `pdfFile == null` means the user cancelled — empty, not an error.
class ScanOutcome {
  final File? pdfFile;
  const ScanOutcome({this.pdfFile});

  bool get isEmpty => pdfFile == null;
}

/// Bridges to the native PDFPrivio scanner via MethodChannel.
///
/// Two scanner backends are available:
///   * **Custom** (default) — full AVCaptureSession + Vision rectangle
///     detection + stability tracking + auto-capture + 5 enhancement
///     modes + review screen. iPhone-class UX.
///   * **Apple VisionKit** (debug toggle) — kept as a fallback inside
///     `Settings → DEBUG → Use Apple scanner` so we can isolate bugs
///     between Apple's framework and ours.
///
/// Both backends end the same way: a PDF file path is returned over
/// the channel. Null/empty result == user cancelled.
class DocumentScannerService {
  DocumentScannerService._();
  static final DocumentScannerService instance = DocumentScannerService._();

  static const MethodChannel _channel =
      MethodChannel('com.erekstudio.pdfprivio/scanner');

  /// Pref key for the hidden debug toggle. Treated as `false` when
  /// missing — production users never see the toggle.
  static const String prefsUseAppleScanner =
      'pdfprivio.debug.use_apple_scanner';

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

  /// Opens the native scanner. Returns:
  ///   Ok(ScanOutcome(pdfFile: …)) on success.
  ///   Ok(ScanOutcome(pdfFile: null)) on cancel.
  ///   Err(unknown) on platform / native failure or unsupported device.
  Future<Result<ScanOutcome>> scan() async {
    if (!Platform.isIOS) {
      return Err(FailureKind.unknown,
          'Document Scanner is iOS-only right now — Android scanner is coming.');
    }

    final prefs = await SharedPreferences.getInstance();
    final useAppleVisionKit = prefs.getBool(prefsUseAppleScanner) ?? false;

    try {
      final result = await _channel.invokeMethod<String?>('scan', {
        'useAppleVisionKit': useAppleVisionKit,
      });
      if (result == null || result.isEmpty) {
        return Ok(const ScanOutcome(pdfFile: null));
      }
      return Ok(ScanOutcome(pdfFile: File(result)));
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
