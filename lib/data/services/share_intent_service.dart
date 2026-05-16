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
  /// Call this AFTER runApp so a listener is already subscribed when
  /// the initial-launch payload arrives.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    try {
      // Cold-launch payload.
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        _controller.add(initial);
        // The package keeps the cold-launch payload cached until reset,
        // which would re-emit the same file the next time we read it.
        ReceiveSharingIntent.instance.reset();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ShareIntentService.getInitialMedia failed: $e');
      }
    }

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

    // Also drain whatever our custom PDFPrivioShare extension dropped
    // before launch (Share-Sheet cold-launch path).
    await drainExtensionDrop();

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

  /// Move every file the PDFPrivioShare Share Extension dumped into
  /// the App Group's SharedExtensionDrop folder into our own
  /// Documents/Inbox, then emit them on [intents] so the action sheet
  /// gets the same treatment as a CFBundleDocumentTypes-routed file.
  /// Called by RootScaffold on every AppLifecycleState.resumed plus
  /// once during init().
  Future<void> drainExtensionDrop() async {
    if (!Platform.isIOS) return;
    try {
      final paths = await _shareExtChannel.invokeListMethod<String>('drain');
      if (paths == null || paths.isEmpty) return;

      final imported = <SharedMediaFile>[];
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

      if (imported.isNotEmpty) {
        _controller.add(imported);
      }
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('drainExtensionDrop platform error: $e');
      }
    } on MissingPluginException {
      // Bridge not registered yet (very early boot). Will be picked
      // up on the next resume tick.
    }
  }

  /// Copy the iOS-supplied file path into the app's Documents/Inbox
  /// so it persists past the share callback (iOS may purge the original
  /// temp file as soon as the extension finishes) and so the user can
  /// also see it in the Files app under "On My iPhone / PDFPrivio /
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
