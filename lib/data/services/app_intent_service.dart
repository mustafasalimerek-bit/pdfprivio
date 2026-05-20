import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Drains pending AppIntent routes set by the iOS Swift side.
///
/// Each AppIntent (Sign / Redact / OCR / Find sensitive data / Scan /
/// Open recent) writes its target route into UserDefaults under
/// `pdfprivio.pendingIntentRoute` and asks iOS to open the app.
/// Once the app is in the foreground we ask AppIntentBridge to hand
/// us that route, clear the slot, and emit it on [routes] so the
/// navigator can push the matching screen.
///
/// We poll on init (cold launch) AND on every `AppLifecycleState.resumed`
/// transition so a Siri trigger fired while the app is in the
/// background also gets honoured.
class AppIntentService {
  AppIntentService._();
  static final AppIntentService instance = AppIntentService._();

  static const MethodChannel _channel =
      MethodChannel('com.erekstudio.pdfprivio/app_intent');

  final _controller = StreamController<String>.broadcast();

  /// Emitted route strings — either a navigator path (`/tool/sign`) or
  /// a tab descriptor (`tab:recent`). Listeners decide which to
  /// honour; root scaffold handles both. The stream is **hot-path only**
  /// — cold-launch routes must be pulled via [consumePending] after the
  /// listener has subscribed, otherwise the emit lands before anyone is
  /// listening and broadcast streams don't replay.
  Stream<String> get routes => _controller.stream;

  bool _inited = false;

  /// No-op shell — kept so the rest of the boot chain stays symmetrical
  /// across services. Cold-launch route is pulled by RootScaffold via
  /// [consumePending]; warm-resume routes are emitted via [onResume].
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
  }

  /// Pull the pending intent route written by an AppIntent + clear it.
  /// Returns null if no route is pending. Caller is responsible for
  /// dispatching — used by RootScaffold's post-frame to handle the
  /// cold-launch case where the [routes] stream has no subscriber yet.
  Future<String?> consumePending() async {
    if (!Platform.isIOS) return null;
    try {
      final route = await _channel.invokeMethod<String>('consume');
      if (route != null && route.isNotEmpty) return route;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('AppIntentService.consume failed: $e');
      }
    } on MissingPluginException {
      // Plugin not yet registered (e.g. very early in boot). Harmless,
      // the next resume tick will catch it.
    }
    return null;
  }

  /// Called from a Flutter `AppLifecycleListener.onResume` so an intent
  /// fired while we were in the background still wakes a navigation.
  /// Listeners are already subscribed at this point, so we emit via
  /// the stream.
  Future<void> onResume() async {
    final route = await consumePending();
    if (route != null) {
      _controller.add(route);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
