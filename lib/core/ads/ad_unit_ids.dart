import 'dart:io';

import 'package:flutter/foundation.dart';

/// Centralised AdMob unit identifiers. Always go through this class —
/// inlining a unit ID at the call site risks shipping a debug-test ID
/// (which we can click freely during development) into a release build
/// where clicking your own units gets the AdMob account suspended.
///
/// In `kDebugMode` we always return Google's published sandbox IDs so
/// development clicks are safe. In release builds we return the real
/// PDFWork unit IDs from the AdMob console (publisher
/// `pub-7294127185571156`, registered 2026-05-15).
class AdUnitIds {
  AdUnitIds._();

  // ---- Banner ----

  static String get banner =>
      kDebugMode ? _testBanner : (Platform.isIOS ? _iosBanner : _androidBanner);

  // ---- Interstitial ----

  static String get interstitial => kDebugMode
      ? _testInterstitial
      : (Platform.isIOS ? _iosInterstitial : _androidInterstitial);

  // ---- Rewarded ----
  // Reward config (both platforms): amount=1, type="unlock". The app
  // decides what gets granted by looking at its own context — usually
  // a one-shot pass for a Pro-gated operation (see PaywallSheet).

  static String get rewarded => kDebugMode
      ? _testRewarded
      : (Platform.isIOS ? _iosRewarded : _androidRewarded);

  // ---- Google test units (debug only) ----
  // https://developers.google.com/admob/ios/test-ads
  // https://developers.google.com/admob/android/test-ads

  static const _testBanner = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewarded = 'ca-app-pub-3940256099942544/1712485313';

  // ---- Real units (release) ----

  static const _iosBanner = 'ca-app-pub-7294127185571156/9557430009';
  static const _iosInterstitial = 'ca-app-pub-7294127185571156/8244348331';
  static const _iosRewarded = 'ca-app-pub-7294127185571156/9152052582';

  static const _androidBanner = 'ca-app-pub-7294127185571156/5753916366';
  static const _androidInterstitial = 'ca-app-pub-7294127185571156/1311879566';
  static const _androidRewarded = 'ca-app-pub-7294127185571156/8497446468';
}
