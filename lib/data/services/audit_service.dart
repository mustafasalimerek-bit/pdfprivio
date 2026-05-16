import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/audit_entry.dart';

/// Persistent audit log of every tool operation.
///
/// Each call to [record] writes one [AuditEntry] into a Hive box.
/// Compliance-conscious users (lawyers under ABA Model Rule 1.15,
/// CPAs under SOX §404, anyone subject to GDPR Art. 30) can browse
/// the log from Settings and export it as CSV.
///
/// Retention: 90 days OR 5000 entries, whichever hits first. We
/// prune at init time so the worst case (years of cold storage) gets
/// cleaned automatically.
class AuditService {
  AuditService._();
  static final AuditService instance = AuditService._();

  static const String _boxName = 'audit_log';
  static const Duration _retention = Duration(days: 90);
  static const int _maxEntries = 5000;

  Box<AuditEntry>? _box;
  bool _inited = false;
  final _random = Random();
  final _changes = StreamController<void>.broadcast();

  /// Fires every time a record is added / log cleared. Audit log
  /// viewer subscribes so it refreshes without polling.
  Stream<void> get changes => _changes.stream;

  Future<void> init() async {
    if (_inited) return;
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AuditEntryAdapter());
    }
    _box = await Hive.openBox<AuditEntry>(_boxName);
    _inited = true;
    await _prune();
  }

  /// Append one entry. Best-effort — if the box isn't initialised yet
  /// (very early boot) we silently skip rather than holding up the
  /// tool that wanted to log. Hashing reads only the first 1 MB of
  /// the input to stay fast on multi-hundred-MB legal exhibits.
  Future<void> record({
    required String tool,
    File? inputFile,
    File? outputFile,
    Map<String, String>? params,
    bool success = true,
  }) async {
    final box = _box;
    if (!_inited || box == null) return;
    try {
      String? inputName;
      int? inputSize;
      String? inputHash;
      if (inputFile != null && await inputFile.exists()) {
        inputName = p.basename(inputFile.path);
        final stat = await inputFile.stat();
        inputSize = stat.size;
        inputHash = await _hashPrefix(inputFile);
      }
      String? outputName;
      int? outputSize;
      if (outputFile != null && await outputFile.exists()) {
        outputName = p.basename(outputFile.path);
        outputSize = (await outputFile.stat()).size;
      }
      final now = DateTime.now().toUtc();
      final entry = AuditEntry(
        id: '${now.millisecondsSinceEpoch}_${tool}_${_random.nextInt(99999)}',
        timestamp: now,
        tool: tool,
        inputFileName: inputName,
        inputSizeBytes: inputSize,
        inputSha256Prefix: inputHash,
        outputFileName: outputName,
        outputSizeBytes: outputSize,
        params: params ?? const {},
        success: success,
      );
      await box.add(entry);
      _changes.add(null);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AuditService.record failed: $e');
      }
    }
  }

  /// Newest-first iteration. Hive box is insertion-ordered, so we
  /// reverse the value list — cheaper than holding an index.
  Future<List<AuditEntry>> getAll({int? limit}) async {
    final box = _box;
    if (!_inited || box == null) return [];
    final all = box.values.toList().reversed.toList();
    if (limit != null && all.length > limit) {
      return all.sublist(0, limit);
    }
    return all;
  }

  Future<int> get entryCount async => _box?.length ?? 0;

  Future<void> clearAll() async {
    final box = _box;
    if (!_inited || box == null) return;
    await box.clear();
    _changes.add(null);
  }

  /// Drop entries older than [_retention] OR keep only the newest
  /// [_maxEntries]. Runs at init + on demand.
  Future<void> _prune() async {
    final box = _box;
    if (box == null) return;
    final cutoff = DateTime.now().toUtc().subtract(_retention);
    final keysToDelete = <dynamic>[];
    for (final key in box.keys) {
      final entry = box.get(key);
      if (entry == null) continue;
      if (entry.timestamp.isBefore(cutoff)) {
        keysToDelete.add(key);
      }
    }
    if (keysToDelete.isNotEmpty) {
      await box.deleteAll(keysToDelete);
    }
    // Enforce hard cap.
    if (box.length > _maxEntries) {
      final overflow = box.length - _maxEntries;
      final overflowKeys = box.keys.take(overflow).toList();
      await box.deleteAll(overflowKeys);
    }
  }

  /// Build a CSV of the entire audit log and return the file path so
  /// the caller can share / save it via share_plus.
  Future<File> exportCsv() async {
    final entries = await getAll();
    final docs = await getApplicationDocumentsDirectory();
    final exports = Directory(p.join(docs.path, 'AuditExports'));
    if (!await exports.exists()) {
      await exports.create(recursive: true);
    }
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final out = File(p.join(exports.path, 'pdfprivio_audit_$stamp.csv'));
    final buf = StringBuffer();
    buf.writeln('timestamp_utc,tool,success,input_file,input_size,input_sha256_prefix,'
        'output_file,output_size,params');
    for (final e in entries) {
      buf.writeln([
        _csv(e.timestamp.toIso8601String()),
        _csv(e.tool),
        _csv(e.success.toString()),
        _csv(e.inputFileName ?? ''),
        _csv(e.inputSizeBytes?.toString() ?? ''),
        _csv(e.inputSha256Prefix ?? ''),
        _csv(e.outputFileName ?? ''),
        _csv(e.outputSizeBytes?.toString() ?? ''),
        _csv(e.params.entries.map((kv) => '${kv.key}=${kv.value}').join(';')),
      ].join(','));
    }
    await out.writeAsString(buf.toString(), flush: true);
    return out;
  }

  String _csv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Hash the first ~1 MB of the input file. We don't need a full
  /// hash for audit purposes — the prefix is enough to match against
  /// a known document later, and we don't want to spend 8 seconds
  /// hashing a 400 MB exhibit just to log it.
  Future<String?> _hashPrefix(File file) async {
    try {
      final stream = file.openRead(0, 1024 * 1024);
      final digest = await sha256.bind(stream).first;
      return digest.toString().substring(0, 16);
    } catch (_) {
      return null;
    }
  }
}
