import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Thin wrapper around [SharePlus.instance.share] that surfaces errors
/// to the user via a SnackBar instead of swallowing them.
///
/// Every call site in the app used to do:
/// ```dart
/// await SharePlus.instance.share(ShareParams(...));
/// ```
/// without a try/catch. When share_plus threw — file sandbox issue,
/// simulator share-sheet quirk, or any internal exception — the user
/// saw nothing. Tap → no animation → no sheet → "the button is
/// broken." 11 share sites carried this risk; this helper closes the
/// pattern.
///
/// Usage:
/// ```dart
/// await ShareService.shareWithFeedback(
///   context,
///   ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
/// );
/// ```
class ShareService {
  ShareService._();

  /// Computes a [Rect] suitable for `sharePositionOrigin` from the
  /// given context's render box. Returns null if the render box isn't
  /// available yet (which is fine on iPhone — sharePositionOrigin is
  /// only required for iPad popover positioning).
  static Rect? originFromContext(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Calls SharePlus with the given params; on any throw, posts a
  /// SnackBar so the user knows the action failed instead of assuming
  /// the button is broken.
  static Future<void> shareWithFeedback(
    BuildContext context,
    ShareParams params, {
    String fallbackMessage = "Couldn't open the share sheet.",
  }) async {
    try {
      await SharePlus.instance.share(params);
    } catch (e) {
      if (!context.mounted) return;
      // Trim the prefix Dart adds to thrown messages so the SnackBar
      // doesn't show "Exception: blah blah" — just the useful tail.
      final raw = e.toString();
      final tail = raw.contains(':') ? raw.split(':').last.trim() : raw;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tail.isEmpty ? fallbackMessage : '$fallbackMessage $tail'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}
