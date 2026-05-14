import 'package:flutter/services.dart';

/// Curated haptic vocabulary so the whole app speaks the same touch language.
///
/// We intentionally avoid using raw `HapticFeedback` calls throughout the UI:
/// without this layer, every dev makes their own choice and the device starts
/// to feel chaotic. Each method here maps to one user-perceivable concept.
class HapticsService {
  HapticsService._();
  static final HapticsService instance = HapticsService._();

  /// Quick acknowledgement of a tap that doesn't change state (e.g. opening
  /// a picker, expanding a section).
  Future<void> tap() => HapticFeedback.selectionClick();

  /// State change confirmation (toggle on/off, item selected, page reordered).
  Future<void> select() => HapticFeedback.lightImpact();

  /// Drop / drag-end. Heavier than `select` so the body confirms the action
  /// landed somewhere it'll persist.
  Future<void> drop() => HapticFeedback.mediumImpact();

  /// Operation completed successfully — used sparingly so it stays meaningful.
  Future<void> success() => HapticFeedback.mediumImpact();

  /// Operation failed or user hit a hard limit.
  Future<void> error() => HapticFeedback.heavyImpact();

  /// Long-press triggered a contextual action.
  Future<void> longPress() => HapticFeedback.mediumImpact();
}
