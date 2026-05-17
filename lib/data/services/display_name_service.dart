import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores the optional display name the user types in
/// Settings → Personalization. Used by _HomeHeader to personalise
/// the greeting ("Good morning, Mustafa").
///
/// Privacy posture: never leaves the device. We store nothing else
/// — no email, no Apple ID, no analytics tag against the name. The
/// audit log explicitly excludes user PII, and this string is
/// excluded from any export too.
class DisplayNameService {
  DisplayNameService._();
  static final DisplayNameService instance = DisplayNameService._();

  static const String _key = 'pdfprivio.display_name.v1';
  static const int _maxLength = 24;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  Future<void> set(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await prefs.remove(_key);
    } else {
      final clipped = trimmed.length > _maxLength
          ? trimmed.substring(0, _maxLength)
          : trimmed;
      await prefs.setString(_key, clipped);
    }
    _changes.add(null);
  }
}
