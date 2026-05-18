import 'dart:async';

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

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

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
