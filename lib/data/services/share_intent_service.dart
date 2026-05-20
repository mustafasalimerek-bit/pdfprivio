import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Listens for inbound files (PDF / image) handed to us by other apps
/// via the iOS Share Sheet, the "Open In…" picker, or our own Share
/// Extension. Surfaces them through a single broadcast stream so the
/// UI layer can decide what to do (route to Sign, Redact, Image to
/// PDF, etc.).
///
/// Two entry points to watch:
///   * `getInitialMedia()` — fires once when the app was COLD-LAUNCHED
///     from a share action. iOS passes the payload in the launch args.
///   * `getMediaStream()` — fires whenever a share lands while the
///     app is already running (foreground or background).
///
/// We multiplex both into [intents] and let the listener (typically the
/// root scaffold) bring up an action sheet so the user picks a tool.
class ShareIntentService {
  ShareIntentService._();
  static final ShareIntentService instance = ShareIntentService._();

  static const MethodChannel _shareExtChannel =
      MethodChannel('com.erekstudio.pdfprivio/share_extension');

  final _controller = StreamController<List<SharedMediaFile>>.broadcast();
  StreamSubscription<List<SharedMediaFile>>? _streamSub;
  bool _inited = false;

  /// Fires every time iOS hands us one or more files. Empty lists are
  /// filtered out so listeners only see real payloads.
  Stream<List<SharedMediaFile>> get intents => _controller.stream;

  /// Wire the package's two entry points. Safe to call multiple times.
  ///
  /// init() only wires the **hot** path — the live media stream and the
  /// method-channel ping handler — both of which need to be hooked up
  /// early in main() so foreground shares arriving moments after launch
  /// are not lost.
  ///
  /// The **cold-launch backlog** (`getInitialMedia()` payload + any files
  /// our PDFPrivioShare / PDFPrivioQuickSign extensions dropped before
  /// the app started) is pulled separately via [consumeInitial] — the
  /// listener (RootScaffold post-frame) calls it after subscribing to
  /// [intents], because broadcast streams do not replay emissions made
  /// before a listener subscribes.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // Hot path — app already running, new share lands.
    _streamSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        if (files.isNotEmpty) {
          _controller.add(files);
        }
      },
      onError: (Object error) {
        if (kDebugMode) {
          debugPrint('ShareIntentService stream error: $error');
        }
      },
    );

    // Listen for the AppDelegate-fired "shareExtensionPending" pings
    // — these fire when the user shares while the app is already
    // running so we don't have to wait for the next AppLifecycle
    // resume tick.
    _shareExtChannel.setMethodCallHandler((call) async {
      if (call.method == 'shareExtensionPending') {
        await drainExtensionDrop();
      }
    });
  }

  /// Pull every share payload that landed before listeners were
  /// subscribed. Called once from RootScaffold's post-frame callback,
  /// **after** the [intents] stream is being listened to. Returns the
  /// combined backlog so the caller can fire the action sheet directly
  /// (the stream itself is not used for cold-launch delivery — events
  /// added before any listener subscribes are dropped by broadcast
  /// streams). Hot shares continue to flow through [intents].
  Future<List<SharedMediaFile>> consumeInitial() async {
    if (!Platform.isIOS) return const [];
    final results = <SharedMediaFile>[];
    // 1. receive_sharing_intent's cached cold-launch payload.
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        results.addAll(initial);
        // The package keeps the cold-launch payload cached until reset,
        // which would re-emit the same file the next time we read it.
        ReceiveSharingIntent.instance.reset();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ShareIntentService.consumeInitial getInitialMedia '
            'failed: $e');
      }
    }
    // 2. Files our PDFPrivioShare / PDFPrivioQuickSign extensions
    //    dropped before launch into the App Group's
    //    SharedExtensionDrop folder.
    results.addAll(await _drainSilent());
    return results;
  }

  /// Last preferred-action string the QuickSign / Quick* Action
  /// Extensions wrote into App Group UserDefaults. Read once per drain
  /// and cleared so the next share starts clean.
  String? _preferredAction;

  /// True when the most recent drained share was triggered by an
  /// Action Extension that already chose a tool (e.g. Quick Sign).
  /// SharedFileActionSheet checks this to decide whether to bypass
  /// the action chooser sheet entirely.
  String? get pendingPreferredAction => _preferredAction;

  void clearPreferredAction() {
    _preferredAction = null;
  }

  /// Drain + emit. Used by the hot paths (AppLifecycleState.resumed
  /// and the `shareExtensionPending` method-channel ping) when
  /// listeners are guaranteed to already be subscribed.
  Future<void> drainExtensionDrop() async {
    final imported = await _drainSilent();
    if (imported.isNotEmpty) {
      _controller.add(imported);
    }
  }

  /// Core drain — moves every file the PDFPrivioShare / PDFPrivioQuickSign
  /// extensions dumped into the App Group's SharedExtensionDrop folder
  /// into our own Documents/Inbox, pulls the preferred-action hint, and
  /// **returns** the imported list without touching the stream. Stream
  /// emission is the caller's call: hot paths use [drainExtensionDrop]
  /// (which wraps this + emits); the cold-launch caller pulls the list
  /// via [consumeInitial] and dispatches it directly so it doesn't fire
  /// before listeners subscribe.
  Future<List<SharedMediaFile>> _drainSilent() async {
    if (!Platform.isIOS) return const [];
    final imported = <SharedMediaFile>[];
    try {
      final paths = await _shareExtChannel.invokeListMethod<String>('drain');
      if (paths == null || paths.isEmpty) return imported;

      final docs = await getApplicationDocumentsDirectory();
      final inbox = Directory(p.join(docs.path, 'Inbox'));
      if (!await inbox.exists()) {
        await inbox.create(recursive: true);
      }

      for (final path in paths) {
        final src = File(path);
        if (!await src.exists()) continue;
        final dest = File(p.join(inbox.path, p.basename(src.path)));
        try {
          await src.copy(dest.path);
          await src.delete(); // drain — don't re-import next time.
          final type = dest.path.toLowerCase().endsWith('.pdf')
              ? SharedMediaType.file
              : SharedMediaType.image;
          imported.add(SharedMediaFile(path: dest.path, type: type));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('drainExtensionDrop import failed for $path: $e');
          }
        }
      }

      await _shareExtChannel.invokeMethod('clearPendingFlag');

      // Quick Sign / other Action Extensions write the picked tool
      // into App Group UserDefaults so the chooser sheet can be
      // skipped. Pulled here so SharedFileActionSheet has it ready
      // before deciding whether to show.
      try {
        _preferredAction = await _shareExtChannel
            .invokeMethod<String>('consumePreferredAction');
      } on PlatformException {
        _preferredAction = null;
      } on MissingPluginException {
        _preferredAction = null;
      }
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('drainExtensionDrop platform error: $e');
      }
    } on MissingPluginException {
      // Bridge not registered yet (very early boot). Will be picked
      // up on the next resume tick.
    }
    return imported;
  }

  /// Copy the iOS-supplied file path into the app's Documents/Inbox
  /// so it persists past the share callback (iOS may purge the original
  /// temp file as soon as the extension finishes) and so the user can
  /// also see it in the Files app under "On My iPhone / Privio /
  /// Inbox" if they ever need it again.
  static Future<File?> importToInbox(SharedMediaFile shared) async {
    try {
      final src = File(shared.path);
      if (!await src.exists()) return null;
      final docs = await getApplicationDocumentsDirectory();
      final inbox = Directory(p.join(docs.path, 'Inbox'));
      if (!await inbox.exists()) {
        await inbox.create(recursive: true);
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final basename = p.basename(shared.path);
      final dest = File(p.join(inbox.path, '${stamp}_$basename'));
      await src.copy(dest.path);
      return dest;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ShareIntentService.importToInbox failed: $e');
      }
      return null;
    }
  }

  Future<void> dispose() async {
    await _streamSub?.cancel();
    _streamSub = null;
    _inited = false;
  }
}

/// Hand-off between the share-intent listener and a tool screen. The
/// action sheet copies the inbound file into Inbox, sets it here, and
/// pushes the user to the tool they picked. The tool's initState pulls
/// the file out via [consume] (which returns AND clears) — guaranteeing
/// the same file isn't re-applied to the next screen the user opens.
class PendingSharedFile {
  PendingSharedFile._();

  static File? _pending;

  static void set(File file) {
    _pending = file;
  }

  static File? consume() {
    final f = _pending;
    _pending = null;
    return f;
  }

  static bool get hasPending => _pending != null;
}
