import 'dart:io';

import 'package:flutter/foundation.dart';

/// AdMob ad unit IDs for Privio across iOS and Android.
///
/// Publisher account: pub-7294127185571156 (algoguy AdMob console).
/// Provisioned 2026-05-16, post-rebrand. App IDs live in the platform
/// manifests (Android: `AndroidManifest.xml` meta-data; iOS:
/// `Info.plist` `GADApplicationIdentifier`) so the SDK can self-init —
/// only the per-unit IDs are needed at the Dart layer.
///
/// Format mix: Banner + Interstitial + Rewarded. **No app-open ads**
/// (deliberate — prosumer audience, app-open feels intrusive on a
/// privacy-positioned PDF tool).
///
/// Debug builds substitute Google's official test ad unit IDs so we
/// never accidentally serve real impressions from a developer device
/// (which gets the AdMob account flagged for invalid traffic).
class AdUnitIds {
  AdUnitIds._();

  // Google's official test IDs — safe to ship in debug, never serves
  // a real ad: https://developers.google.com/admob/flutter/test-ads
  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testBannerIOS =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _testInterstitialIOS =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _testRewardedIOS =
      'ca-app-pub-3940256099942544/1712485313';

  // Production unit IDs — Privio AdMob console, registered 2026-05-16.
  static const String _prodBannerAndroid =
      'ca-app-pub-7294127185571156/1038060163';
  static const String _prodInterstitialAndroid =
      'ca-app-pub-7294127185571156/9784962038';
  static const String _prodRewardedAndroid =
      'ca-app-pub-7294127185571156/3271295669';
  static const String _prodBannerIOS =
      'ca-app-pub-7294127185571156/4229154111';
  static const String _prodInterstitialIOS =
      'ca-app-pub-7294127185571156/2916072443';
  static const String _prodRewardedIOS =
      'ca-app-pub-7294127185571156/8878845562';

  static String get banner {
    if (kDebugMode) {
      return Platform.isAndroid ? _testBannerAndroid : _testBannerIOS;
    }
    return Platform.isAndroid ? _prodBannerAndroid : _prodBannerIOS;
  }

  static String get interstitial {
    if (kDebugMode) {
      return Platform.isAndroid
          ? _testInterstitialAndroid
          : _testInterstitialIOS;
    }
    return Platform.isAndroid
        ? _prodInterstitialAndroid
        : _prodInterstitialIOS;
  }

  static String get rewarded {
    if (kDebugMode) {
      return Platform.isAndroid ? _testRewardedAndroid : _testRewardedIOS;
    }
    return Platform.isAndroid ? _prodRewardedAndroid : _prodRewardedIOS;
  }
}
