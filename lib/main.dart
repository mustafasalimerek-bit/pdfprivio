import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
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

    // Service boot. Wrapped in a defensive shell — one throw inside
    // any init() used to take down main() before runApp ever ran,
    // leaving the user with a black screen and no diagnostic. Each
    // service is isolated now; a failure logs and the rest proceeds.
    //
    // ReviewPromptService must run AFTER AuditService because it
    // subscribes to AuditService.changes; order in this list is
    // therefore meaningful even though failures don't propagate.
    //
    // ShareIntentService + AppIntentService only wire their hot paths
    // here — cold-launch payloads (initial share / pending Siri route)
    // are pulled by RootScaffold once its listeners are subscribed,
    // since broadcast streams don't replay emissions made before a
    // listener attaches.
    Future<void> safe(String name, Future<void> Function() init) async {
      try {
        await init();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Init failed for $name: $e\n$st');
        }
      }
    }

    // Hive — backs the audit log + recent files entries.
    await safe('Hive', () async => await Hive.initFlutter());
    await safe('PurchaseService', PurchaseService.instance.init);
    await safe('PromoCodeService', PromoCodeService.instance.init);
    await safe('AuditService', AuditService.instance.init);
    await safe('ExpenseLedgerService', ExpenseLedgerService.instance.init);
    await safe('UsageLimitsService.prune',
        UsageLimitsService.instance.pruneOldEntries);
    await safe('ReviewPromptService', ReviewPromptService.instance.init);
    await safe('WidgetDataService', WidgetDataService.instance.init);
    await safe('ShareIntentService', ShareIntentService.instance.init);
    await safe('AppIntentService', AppIntentService.instance.init);

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
