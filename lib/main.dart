import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'data/services/app_intent_service.dart';
import 'data/services/audit_service.dart';
import 'data/services/expense_ledger_service.dart';
import 'data/services/promo_code_service.dart';
import 'data/services/purchase_service.dart';
import 'data/services/review_prompt_service.dart';
import 'data/services/share_intent_service.dart';
import 'data/services/usage_limits_service.dart';
import 'data/services/widget_data_service.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // No analytics, no Firebase, no third-party SDKs. Crash reports come
    // through Apple's App Store Connect dashboard (user opt-in via
    // Settings > Privacy > Analytics & Improvements > Share with App
    // Developers), so we don't need to ship a parallel pipeline.
    //
    // FlutterError still gets logged to the iOS console for TestFlight
    // sessionizing — local-only, never leaves the device unless the
    // user explicitly shares diagnostic data with Apple.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };

    // Hive — backs the audit log + recent files entries.
    await Hive.initFlutter();

    // Purchase + usage-limits boot. Init runs StoreKit availability
    // check and silent restore so the home grid renders with the right
    // lock state on the very first frame.
    await PurchaseService.instance.init();
    await PromoCodeService.instance.init();
    await AuditService.instance.init();
    await ExpenseLedgerService.instance.init();
    await UsageLimitsService.instance.pruneOldEntries();
    // Subscribes to AuditService.changes to count successful tool
    // operations; surfaces SKStoreReviewController after 3 successes
    // + 2 days since install, then sleeps for 90 days. Must init
    // AFTER AuditService so the stream subscription has a live
    // broadcaster to bind to.
    await ReviewPromptService.instance.init();
    // Home Screen widget bridge — pushes recent files into the App
    // Group shared store so the iOS WidgetKit extension can render
    // them. No-op on Android (widget arrives in v1.1).
    await WidgetDataService.instance.init();
    // Listen for inbound files handed to us via Share Sheet / Open In
    // / our own Share Extension. Cold-launch payload is drained here;
    // hot stream events are picked up by RootScaffold's listener.
    await ShareIntentService.instance.init();
    // Drain any AppIntent-triggered route ("Hey Siri, sign a PDF with
    // Privio"). Cold-launch route comes through on init; warm
    // resumes re-poll from RootScaffold's lifecycle listener.
    await AppIntentService.instance.init();

    // iPhone stays portrait-locked — the tool screens are vertical
    // forms and rotating them helps nobody. iPad gets all four
    // orientations so Magic-Keyboard-default landscape and Stage
    // Manager rotation work as users expect.
    //
    // `implicitView` can be null when the app is cold-launched via a
    // URL scheme (Share Extension / Quick Sign hand off `pdfprivio://`
    // before the scene attaches), so `.views.first` used to throw and
    // crash main() before runApp ever ran. Treat the no-view case as
    // iPhone-default — RootScaffold can re-evaluate via `View.of`
    // once it has a BuildContext.
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    bool isIPadDevice = false;
    if (Platform.isIOS && view != null) {
      final display = view.display;
      final shortestSidePt =
          display.size.shortestSide / display.devicePixelRatio;
      isIPadDevice = shortestSidePt >= 600;
    }
    await SystemChrome.setPreferredOrientations(
      isIPadDevice
          ? const <DeviceOrientation>[] // [] = all orientations allowed
          : const [DeviceOrientation.portraitUp],
    );

    runApp(
      const ProviderScope(
        child: PdfPrivioApp(),
      ),
    );
  }, (error, stack) {
    // Same posture as FlutterError.onError above — console logging only.
    // Apple's crash pipeline handles aggregation server-side.
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}
