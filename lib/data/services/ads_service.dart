import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/ads/ad_unit_ids.dart';
import 'purchase_service.dart';

/// Centralised banner + interstitial coordinator.
///
/// Design notes:
///   * Every ad request is Pro-gated — if `PurchaseService.instance.hasPro`
///     is true, we never load, never show, never even spend a network
///     round-trip. Paying users see zero ads.
///   * Banner widgets are lightweight and live for the host screen's
///     lifetime; they are owned by `BannerAdWidget`, not by this service.
///   * The interstitial is **pre-loaded** so the perceived latency at
///     trigger time is zero. After every show or failure we kick off the
///     next pre-load.
///   * Cooldown of 3 minutes between interstitial shows is enforced
///     in-memory. Apple HIG and AdMob policy both push back on more
///     aggressive frequency; the lawyer/CPA wedge is rage-uninstall
///     sensitive (`project_pdfwork_launch_checklist.md` item #4).
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  static const Duration interstitialCooldown = Duration(minutes: 3);

  InterstitialAd? _interstitial;
  DateTime? _lastInterstitialShown;
  bool _interstitialLoadInFlight = false;
  bool _initialized = false;

  bool get _adsAllowed => !PurchaseService.instance.hasPro;

  /// Called once during app bootstrap, AFTER MobileAds.instance.initialize()
  /// (which `ConsentService` already handles). Kicks off the first
  /// interstitial pre-load and wires the Pro-change listener to drop
  /// in-flight ads when the user upgrades.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    PurchaseService.instance.entitlementChanges.listen((tier) {
      if (tier == EntitlementTier.pro) {
        // User just unlocked Pro — drop any cached interstitial so we
        // don't accidentally show one right after they paid.
        _interstitial?.dispose();
        _interstitial = null;
      }
    });

    // Best-effort pre-load. If the network isn't ready or AdMob hasn't
    // finished initializing yet, _loadInterstitial() retries lazily on
    // the next maybeShow() call.
    unawaited(_loadInterstitial());
  }

  /// Builds (but does not load) a fresh banner ad. Caller owns the
  /// returned object and must dispose it when the host widget unmounts.
  /// Returns null for Pro users so banner widgets render as empty boxes.
  BannerAd? createBanner({
    AdSize size = AdSize.banner,
    void Function()? onLoaded,
    void Function(LoadAdError error)? onFailed,
  }) {
    if (!_adsAllowed) return null;
    return BannerAd(
      adUnitId: AdUnitIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded?.call(),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) {
            debugPrint('Banner failed: ${error.code} ${error.message}');
          }
          onFailed?.call(error);
        },
      ),
    );
  }

  /// Trigger after a successful, "earned" user moment — typically the
  /// close of a result screen. Honors cooldown + Pro state silently.
  /// Returns true if an ad was actually shown.
  Future<bool> maybeShowInterstitial() async {
    if (!_adsAllowed) return false;

    if (_lastInterstitialShown != null &&
        DateTime.now().difference(_lastInterstitialShown!) <
            interstitialCooldown) {
      return false;
    }

    final ad = _interstitial;
    if (ad == null) {
      // Not loaded yet — kick off a load so the next attempt has one.
      unawaited(_loadInterstitial());
      return false;
    }

    _interstitial = null; // Consume the cached instance now.

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        unawaited(_loadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        if (kDebugMode) {
          debugPrint(
            'Interstitial show failed: ${error.code} ${error.message}',
          );
        }
        unawaited(_loadInterstitial());
      },
    );

    try {
      await ad.show();
      _lastInterstitialShown = DateTime.now();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Interstitial show threw: $e');
      ad.dispose();
      unawaited(_loadInterstitial());
      return false;
    }
  }

  Future<void> _loadInterstitial() async {
    if (!_adsAllowed) return;
    if (_interstitial != null) return;
    if (_interstitialLoadInFlight) return;
    _interstitialLoadInFlight = true;

    try {
      await InterstitialAd.load(
        adUnitId: AdUnitIds.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitial = ad;
            _interstitialLoadInFlight = false;
          },
          onAdFailedToLoad: (error) {
            _interstitialLoadInFlight = false;
            if (kDebugMode) {
              debugPrint(
                'Interstitial load failed: ${error.code} ${error.message}',
              );
            }
          },
        ),
      );
    } catch (e) {
      _interstitialLoadInFlight = false;
      if (kDebugMode) debugPrint('Interstitial load threw: $e');
    }
  }
}
