import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_service.dart';

/// One-shot consent orchestrator. Runs once per app launch after
/// `WidgetsFlutterBinding.ensureInitialized()` but before the user can
/// interact with anything that depends on tracking / personalized ads.
///
/// Order matters (per Google's UMP + Apple's ATT guidance):
///   1) UMP: show GDPR/CCPA consent form when the user is in a region
///      that needs one. Sets `canRequestAds`.
///   2) ATT (iOS only): if UMP allowed ads, request IDFA access. Apple
///      requires this prompt before any tracking SDK ingests IDFA — the
///      ATT prompt is rejected at App Review if it's not present.
///   3) Wire the result into Firebase Analytics + MobileAds init.
///
/// In debug builds we still walk the flow so the prompts can be
/// developed/tested, but Analytics stays off (debug builds shouldn't
/// pollute the production property).
class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  bool _initialized = false;
  bool _canRequestAds = false;
  TrackingStatus _trackingStatus = TrackingStatus.notSupported;

  bool get canRequestAds => _canRequestAds;
  TrackingStatus get trackingStatus => _trackingStatus;
  bool get hasInitialized => _initialized;

  Future<void> gather() async {
    if (_initialized) return;
    _initialized = true;

    await _runUmpFlow();
    await _runAttFlow();
    await _applyToServices();
  }

  // ---------- 1) UMP (Google User Messaging Platform) ----------

  Future<void> _runUmpFlow() async {
    try {
      final params = ConsentRequestParameters();
      await _requestUmpInfoUpdate(params);

      final status = await ConsentInformation.instance.getConsentStatus();
      // Only show the form if UMP says one is required (GDPR / GPP region).
      // Outside regulated regions UMP returns 'notRequired' and we skip.
      if (status == ConsentStatus.required) {
        await _loadAndShowFormIfRequired();
      }

      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (e, st) {
      // Never let a UMP failure crash app startup. We default to
      // not-personalized-ads + analytics-off if the SDK errors.
      _canRequestAds = false;
      if (kDebugMode) {
        debugPrint('UMP flow failed: $e\n$st');
      }
    }
  }

  Future<void> _requestUmpInfoUpdate(ConsentRequestParameters params) {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () => completer.complete(),
      (error) => completer.completeError(error),
    );
    return completer.future;
  }

  Future<void> _loadAndShowFormIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) {
        completer.completeError(error);
      } else {
        completer.complete();
      }
    });
    return completer.future;
  }

  // ---------- 2) ATT (Apple App Tracking Transparency) ----------

  Future<void> _runAttFlow() async {
    if (!Platform.isIOS) {
      _trackingStatus = TrackingStatus.notSupported;
      return;
    }
    try {
      final current = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (current == TrackingStatus.notDetermined) {
        // The OS prompt only fires the first time per install. Subsequent
        // launches return the user's earlier choice without re-prompting.
        _trackingStatus =
            await AppTrackingTransparency.requestTrackingAuthorization();
      } else {
        _trackingStatus = current;
      }
    } catch (e, st) {
      _trackingStatus = TrackingStatus.notSupported;
      if (kDebugMode) {
        debugPrint('ATT flow failed: $e\n$st');
      }
    }
  }

  // ---------- 3) Apply consent to Analytics + AdMob ----------

  Future<void> _applyToServices() async {
    final analyticsAllowed = _canRequestAds && !kDebugMode;
    try {
      await FirebaseAnalytics.instance
          .setAnalyticsCollectionEnabled(analyticsAllowed);
    } catch (e) {
      if (kDebugMode) debugPrint('Analytics toggle failed: $e');
    }

    if (_canRequestAds && AdsService.kAdsEnabled) {
      try {
        await MobileAds.instance.initialize();
      } catch (e) {
        if (kDebugMode) debugPrint('MobileAds init failed: $e');
      }
    }
  }

  /// Lets the user reopen the consent form later (e.g. from a Settings
  /// screen). Required by GDPR — the user must be able to withdraw.
  Future<void> resurfaceConsentForm() async {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) {
        completer.completeError(error);
      } else {
        completer.complete();
      }
    });
    try {
      await completer.future;
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      await _applyToServices();
    } catch (e) {
      if (kDebugMode) debugPrint('Resurface form failed: $e');
    }
  }
}
