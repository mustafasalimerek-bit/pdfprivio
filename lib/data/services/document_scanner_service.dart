import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/utils/result.dart';

/// Outcome from a single scanner session.
class ScanOutcome {
  final List<File> pages;
  const ScanOutcome({required this.pages});

  bool get isEmpty => pages.isEmpty;
  int get pageCount => pages.length;
}

/// Bridges to the native `VNDocumentCameraViewController` on iOS via a
/// MethodChannel ("com.erekstudio.pdfwork/scanner").
///
/// VisionKit does edge detection, perspective correction, multi-page
/// capture, and color/black-and-white modes for us. The Swift side
/// writes each scanned page as a JPEG into a session-scoped temp dir and
/// returns the absolute paths — no cloud, all on-device.
class DocumentScannerService {
  DocumentScannerService._();
  static final DocumentScannerService instance = DocumentScannerService._();

  static const MethodChannel _channel =
      MethodChannel('com.erekstudio.pdfwork/scanner');

  /// Returns true on iPhone/iPad with a rear camera. Always false on the
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
  ///   Ok(ScanOutcome) on success (may be empty if the user cancelled).
  ///   Err(needsPermission) if camera permission is denied.
  ///   Err(unsupported) on simulator or unsupported devices.
  ///   Err(unknown) on unexpected native failure.
  Future<Result<ScanOutcome>> scan() async {
    if (!Platform.isIOS) {
      return Err(FailureKind.unknown,
          'Document Scanner is iOS-only right now — Android scanner is coming.');
    }
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('scan');
      final paths = (result ?? const <dynamic>[]).cast<String>();
      final files = paths.map((p) => File(p)).toList();
      return Ok(ScanOutcome(pages: files));
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'unsupported':
          return Err(FailureKind.unknown,
              e.message ?? 'Document Scanner not available on this device.');
        case 'no_presenter':
          return Err(FailureKind.unknown,
              'Could not open the scanner UI — try again.');
        case 'busy':
          return Err(FailureKind.unknown,
              'Scanner is already open.');
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
