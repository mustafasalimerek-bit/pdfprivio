import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'recent_files_service.dart';

/// Bridge between RecentFilesService and the iOS WidgetKit extension.
///
/// The widget extension is a separate process — it can't import Dart
/// services. The only way it sees app state is through the App Group's
/// shared NSUserDefaults. This service writes the top-3 recent files
/// there as a JSON blob whenever the in-app list changes, then nudges
/// WidgetKit to redraw.
///
/// App Group ID: `group.com.erekstudio.pdfprivio` — must match the
/// capability on both the main app target and the widget extension
/// target in Xcode, and the matching entry in Apple Developer Portal.
class WidgetDataService {
  WidgetDataService._();
  static final WidgetDataService instance = WidgetDataService._();

  static const String _appGroupId = 'group.com.erekstudio.pdfprivio';
  static const String _iosWidgetName = 'PDFPrivioWidget';
  // Android Glance receiver class — matches PrivioWidgetReceiver under
  // android/app/src/main/kotlin/com/erekstudio/pdfprivio/.
  static const String _androidWidgetName = 'PrivioWidgetReceiver';
  static const String _dataKey = 'recent_files_json';
  static const int _maxRows = 3;

  // shared_preferences key for the user-facing toggle. Defaults to
  // true (show file names) so the widget is useful out of the box.
  // Lawyer / privacy-conscious users can disable it from Settings —
  // the widget then displays the tool label + relative time only,
  // hiding any client-identifying filename from the Home Screen.
  static const String _showNamesKey = 'pdfprivio.widget.show_filenames';

  StreamSubscription<void>? _sub;
  bool _inited = false;

  /// Set the App Group (iOS), push the current state once, and subscribe
  /// to future RecentFilesService changes. Safe to call multiple times.
  /// Runs on both iOS (WidgetKit) and Android (Glance) — the platform
  /// branch lives inside [_publishRecents].
  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    if (Platform.isIOS) {
      try {
        await HomeWidget.setAppGroupId(_appGroupId);
      } catch (e) {
        // App Group not configured yet (e.g. running before Xcode target
        // setup is done). Bail silently — widget just won't update.
        if (kDebugMode) {
          debugPrint('WidgetDataService.init: setAppGroupId failed: $e');
        }
        return;
      }
    }

    if (!Platform.isIOS && !Platform.isAndroid) return;

    await _publishRecents(allowEmptyOverwrite: false);
    _sub = RecentFilesService.instance.changes.listen((_) => _publishRecents());
  }

  /// Returns the current "show file names in widget" preference.
  /// Defaults to true so widgets are useful for the median user; lawyer
  /// / privacy-conscious users can flip it off from Settings.
  Future<bool> showFileNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showNamesKey) ?? true;
  }

  /// Persist the toggle and immediately republish so the widget reflects
  /// the new setting without waiting for the next file write.
  Future<void> setShowFileNames(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showNamesKey, value);
    await _publishRecents();
  }

  /// Read up to _maxRows recent files and write them as JSON to the
  /// shared App Group store, then ask WidgetKit to redraw.
  ///
  /// When [allowEmptyOverwrite] is false (default for the boot-time
  /// publish), an empty Recent list is NOT written through — that
  /// avoids a freshly-launched app instantly clobbering whatever the
  /// widget was previously showing before the user has done anything.
  /// Real changes (record / clear) pass `true` so the widget tracks
  /// them faithfully.
  Future<void> _publishRecents({bool allowEmptyOverwrite = true}) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      final files = await RecentFilesService.instance.getAll();
      if (files.isEmpty && !allowEmptyOverwrite) return;

      // Resolve the user's preference once per publish. Storing an empty
      // string for name when names are hidden lets the native widget
      // fall back to a generic "tool · time" row without needing its own
      // copy of the toggle state.
      final showNames = await showFileNames();

      final top = files.take(_maxRows).map((f) {
        return {
          'name': showNames ? f.displayName : '',
          'tool': f.toolLabel,
          'openedAtMs': f.openedAt.millisecondsSinceEpoch,
        };
      }).toList();

      final payload = jsonEncode({
        'files': top,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      });

      await HomeWidget.saveWidgetData<String>(_dataKey, payload);
      await HomeWidget.updateWidget(
        iOSName: _iosWidgetName,
        androidName: _androidWidgetName,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WidgetDataService._publishRecents failed: $e');
      }
    }
  }

  /// For tests / forced refresh.
  Future<void> forceRefresh() => _publishRecents();

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _inited = false;
  }
}
