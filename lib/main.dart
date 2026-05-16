import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/services/ads_service.dart';
import 'data/services/promo_code_service.dart';
import 'data/services/purchase_service.dart';
import 'data/services/share_intent_service.dart';
import 'data/services/usage_limits_service.dart';
import 'data/services/widget_data_service.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Firebase Core — must initialize before Crashlytics or Analytics.
    await Firebase.initializeApp();

    // Crashlytics: legitimate interest (app stability). Disabled in debug to
    // avoid polluting production crash dashboards with developer runs.
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // Analytics off until consent flow says otherwise. Consent gathering
    // (UMP + ATT) runs inside the UI's _BootGate after onboarding so the
    // user sees a welcome explanation BEFORE being asked to accept ads
    // or tracking — Apple's recommended UX and a better conversion rate
    // than launching straight into prompts.
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);

    // Purchase + usage-limits boot. Init runs StoreKit availability
    // check and silent restore so the home grid renders with the right
    // lock state on the very first frame.
    await PurchaseService.instance.init();
    await PromoCodeService.instance.init();
    await UsageLimitsService.instance.pruneOldEntries();
    // Home Screen widget bridge — pushes recent files into the App
    // Group shared store so the iOS WidgetKit extension can render
    // them. No-op on Android (widget arrives in v1.1).
    await WidgetDataService.instance.init();
    // Listen for inbound files handed to us via Share Sheet / Open In
    // / our own Share Extension. Cold-launch payload is drained here;
    // hot stream events are picked up by RootScaffold's listener.
    await ShareIntentService.instance.init();
    // AdsService.init() pre-loads the first interstitial and wires the
    // Pro-purchase listener that drops cached ads when users upgrade.
    // Safe to call before consent — internal calls are silent no-ops
    // until MobileAds.initialize() succeeds inside ConsentService.gather().
    await AdsService.instance.init();

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    runApp(
      const ProviderScope(
        child: PdfPrivioApp(),
      ),
    );
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}
