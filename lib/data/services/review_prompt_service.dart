import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audit_service.dart';

/// Surfaces Apple's SKStoreReviewController in-app review prompt at a
/// genuinely happy moment.
///
/// Definition of "happy moment" we shipped with:
///   * The user has successfully completed at least [_minSuccessCount]
///     tool operations (so they've actually felt the product work).
///   * At least [_minDaysSinceInstall] days have passed since first
///     launch (so we don't ambush a power-user blasting through five
///     tools in their first ten minutes — Apple's algorithm wants
///     several days of engagement signal before the prompt converts).
///   * No previous prompt fired in the last [_cooldownDays] days
///     (defensive — iOS already caps at 3/year but we want a longer
///     spacing per-user).
///
/// Signal source is [AuditService.changes] — every tool that records
/// an audit entry counts. We trade a small amount of precision (clear-
/// log and failed records also tick the counter) for not having to
/// hand-wire every result screen.
///
/// The native [`SKStoreReviewController.requestReview(in:)`] is a
/// fire-and-forget API: iOS may decide to render nothing at all if the
/// user has already prompted/rated, if quotas are exhausted, or if it
/// thinks the user is not a reasonable candidate. We treat the silent
/// no-op as success and still bump our own cooldown so we never burn
/// through the OS quota by retrying immediately.
class ReviewPromptService {
  ReviewPromptService._();
  static final ReviewPromptService instance = ReviewPromptService._();

  static const MethodChannel _channel =
      MethodChannel('com.erekstudio.pdfprivio/review');

  static const String _kFirstLaunchAt = 'pdfprivio.review.firstLaunchAt';
  static const String _kSuccessCount = 'pdfprivio.review.successCount';
  static const String _kLastPromptAt = 'pdfprivio.review.lastPromptAt';

  static const int _minSuccessCount = 3;
  static const int _minDaysSinceInstall = 2;
  static const int _cooldownDays = 90;

  StreamSubscription<void>? _auditSub;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kFirstLaunchAt)) {
      await prefs.setInt(
        _kFirstLaunchAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    _auditSub?.cancel();
    _auditSub = AuditService.instance.changes.listen((_) {
      _onSuccessEvent();
    });
  }

  Future<void> _onSuccessEvent() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_kSuccessCount) ?? 0) + 1;
    await prefs.setInt(_kSuccessCount, next);
    await _maybePrompt(prefs);
  }

  Future<void> _maybePrompt(SharedPreferences prefs) async {
    final count = prefs.getInt(_kSuccessCount) ?? 0;
    if (count < _minSuccessCount) return;

    final firstLaunch = prefs.getInt(_kFirstLaunchAt);
    if (firstLaunch == null) return;
    final daysSinceInstall =
        (DateTime.now().millisecondsSinceEpoch - firstLaunch) ~/
            (1000 * 60 * 60 * 24);
    if (daysSinceInstall < _minDaysSinceInstall) return;

    final lastPrompt = prefs.getInt(_kLastPromptAt) ?? 0;
    if (lastPrompt != 0) {
      final daysSinceLast =
          (DateTime.now().millisecondsSinceEpoch - lastPrompt) ~/
              (1000 * 60 * 60 * 24);
      if (daysSinceLast < _cooldownDays) return;
    }

    await prefs.setInt(
      _kLastPromptAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await _channel.invokeMethod<bool>('requestReview');
    } catch (_) {
      // Non-iOS platforms or pre-iOS-14 fallback failure — silent.
    }
  }

  Future<void> dispose() async {
    await _auditSub?.cancel();
    _auditSub = null;
  }
}
