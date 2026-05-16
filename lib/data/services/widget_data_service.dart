import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

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
  static const String _widgetName = 'PDFPrivioWidget';
  static const String _dataKey = 'recent_files_json';
  static const int _maxRows = 3;

  StreamSubscription<void>? _sub;
  bool _inited = false;

  /// Set the App Group, push the current state once, and subscribe to
  /// future RecentFilesService changes. Safe to call multiple times.
  /// On Android this is a no-op for now (Android widget = v1.1+).
  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // Widget extension is iOS-only at this stage.
    if (!Platform.isIOS) return;

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

    await _publishRecents();
    _sub = RecentFilesService.instance.changes.listen((_) => _publishRecents());
  }

  /// Read up to _maxRows recent files and write them as JSON to the
  /// shared App Group store, then ask WidgetKit to redraw.
  Future<void> _publishRecents() async {
    if (!Platform.isIOS) return;

    try {
      final files = await RecentFilesService.instance.getAll();
      final top = files.take(_maxRows).map((f) {
        return {
          'name': f.displayName,
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
        iOSName: _widgetName,
        // androidName would go here once the Android widget ships.
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
