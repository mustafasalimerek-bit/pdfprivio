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
  ///
  /// Uses an `is RenderBox` check rather than an `as RenderBox?` cast
  /// because tile items inside a ListView resolve their render object
  /// to a `RenderSliverList`, and the cast would throw — which used to
  /// be the actual root cause of "Share button does nothing" in Build
  /// 37: the silent throw bubbled out of the ShareParams constructor
  /// before reaching the try/catch around SharePlus.
  static Rect? originFromContext(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  /// Calls SharePlus with the given params; on any throw OR on a
  /// non-success ShareResult (share_plus completes without throwing
  /// when the OS can't present a sheet — e.g. iOS Simulator has no
  /// Share Extensions registered, so the sheet just doesn't appear),
  /// posts a SnackBar so the user knows the action didn't open instead
  /// of assuming the button is broken.
  static Future<void> shareWithFeedback(
    BuildContext context,
    ShareParams params, {
    String fallbackMessage = "Couldn't open the share sheet.",
  }) async {
    try {
      final result = await SharePlus.instance.share(params);
      if (!context.mounted) return;
      if (result.status == ShareResultStatus.unavailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$fallbackMessage Share Sheet is unavailable on this device '
              '(common in the iOS Simulator — try a real iPhone).',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
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
