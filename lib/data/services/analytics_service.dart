import 'package:firebase_analytics/firebase_analytics.dart';

/// Type-safe event API for PDFKitsy.
///
/// All UI code goes through this service so:
/// - Event names stay consistent (no typos)
/// - Parameter schema is enforced
/// - Single chokepoint to flip Analytics on/off after UMP consent
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _analytics = FirebaseAnalytics.instance;

  /// Called from UMP consent flow once the user agrees (or country=non-EU).
  Future<void> grantConsent() =>
      _analytics.setAnalyticsCollectionEnabled(true);

  Future<void> revokeConsent() =>
      _analytics.setAnalyticsCollectionEnabled(false);

  // -------- Screen tracking --------

  Future<void> screen(String name) =>
      _analytics.logScreenView(screenName: name);

  // -------- Feature events --------

  /// User opened a tool (e.g. "merge", "split", "compress").
  Future<void> toolOpened(String tool) =>
      _analytics.logEvent(name: 'tool_opened', parameters: {'tool': tool});

  /// User started running a tool with N input files.
  Future<void> toolStarted(String tool, {required int fileCount}) =>
      _analytics.logEvent(name: 'tool_started', parameters: {
        'tool': tool,
        'file_count': fileCount,
      });

  /// Tool completed successfully.
  Future<void> toolCompleted(
    String tool, {
    required int durationMs,
    required int outputBytes,
  }) =>
      _analytics.logEvent(name: 'tool_completed', parameters: {
        'tool': tool,
        'duration_ms': durationMs,
        'output_bytes': outputBytes,
      });

  /// Tool failed (with error category, not full message — PII risk).
  Future<void> toolFailed(String tool, {required String errorCategory}) =>
      _analytics.logEvent(name: 'tool_failed', parameters: {
        'tool': tool,
        'error': errorCategory,
      });

  // -------- Monetization --------

  Future<void> paywallView(String source) =>
      _analytics.logEvent(name: 'paywall_view', parameters: {'source': source});

  Future<void> purchase(String productId, {required double priceUsd}) =>
      _analytics.logEvent(name: 'purchase_completed', parameters: {
        'product_id': productId,
        'price_usd': priceUsd,
      });

  Future<void> restorePurchases() =>
      _analytics.logEvent(name: 'restore_purchases');

  // -------- Sharing / export --------

  Future<void> shareCompleted(String tool) =>
      _analytics.logEvent(name: 'share_completed', parameters: {'tool': tool});
}
