import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
