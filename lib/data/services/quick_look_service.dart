import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the QuickLookBridge native MethodChannel.
///
/// `show` presents the file in Apple's QLPreviewController — the
/// system viewer that ships Live Text (iOS 16+), Visual Look Up
/// (iOS 17+), Markup, signing, sharing, and pixel-perfect PDF
/// rendering. The future returned by show completes when the user
/// dismisses the viewer.
///
/// Android: no-op for now. v1.1 can route through Android's native
/// PdfRenderer-backed viewer.
class QuickLookService {
  QuickLookService._();
  static final QuickLookService instance = QuickLookService._();

  static const MethodChannel _channel =
      MethodChannel('com.erekstudio.pdfprivio/quick_look');

  Future<bool> show(File file) async {
    if (!Platform.isIOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('show', {
        'path': file.path,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('QuickLookService.show error: ${e.code} ${e.message}');
      }
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
