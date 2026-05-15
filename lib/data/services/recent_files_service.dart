import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recent_file.dart';

/// Stores the user's recent tool *outputs* — the PDFs they produced in
/// the current install. Surfaces them on the home screen so a returning
/// user lands right on top of the work they were doing yesterday instead
/// of re-picking files from the system file browser every time.
///
/// Storage: a JSON-encoded list in shared_preferences (no Hive box for
/// this, since the data is tiny and bounded — we keep at most 30 rows).
class RecentFilesService {
  RecentFilesService._();
  static final RecentFilesService instance = RecentFilesService._();

  static const String _key = 'pdfwork.recent_files.v1';
  static const int _max = 30;

  /// Broadcast so any widget listening (home screen carousel) refreshes
  /// the moment a new file gets recorded, without polling.
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  Future<void> record({
    required File file,
    required String toolLabel,
  }) async {
    if (!await file.exists()) return;
    final prefs = await SharedPreferences.getInstance();
    final entries = await _read(prefs);

    final stat = await file.stat();
    final entry = RecentFile(
      id: file.path,
      path: file.path,
      displayName: _basename(file.path),
      sizeBytes: stat.size,
      toolLabel: toolLabel,
      openedAt: DateTime.now(),
    );

    // Move-to-top semantics: if the same path is already in the list,
    // remove the old row first so we don't end up with duplicates.
    final dedup = entries.where((e) => e.id != entry.id).toList();
    dedup.insert(0, entry);
    if (dedup.length > _max) {
      dedup.removeRange(_max, dedup.length);
    }

    await prefs.setString(_key, _encode(dedup));
    _changes.add(null);
  }

  Future<List<RecentFile>> getAll({bool pruneMissing = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _read(prefs);
    if (!pruneMissing) return entries;

    // Drop rows whose underlying file has been deleted/uninstalled.
    final kept = <RecentFile>[];
    var changed = false;
    for (final e in entries) {
      if (await File(e.path).exists()) {
        kept.add(e);
      } else {
        changed = true;
      }
    }
    if (changed) {
      await prefs.setString(_key, _encode(kept));
    }
    return kept;
  }

  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _read(prefs);
    final next = entries.where((e) => e.id != id).toList();
    await prefs.setString(_key, _encode(next));
    _changes.add(null);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _changes.add(null);
  }

  Future<List<RecentFile>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(RecentFile.fromJson)
          .whereType<RecentFile>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _encode(List<RecentFile> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());

  String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}
