import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/receipt.dart';

/// On-device ledger of captured receipts. Same Hive pattern as
/// AuditService (different box, different adapter). The whole point
/// of this feature is "freelancer scans receipts all year then dumps
/// them into QuickBooks at tax time" — so the ledger must persist
/// forever, never auto-prune.
///
/// Export format is QuickBooks Online's bank-transactions CSV
/// (Date, Description, Amount). Anyone using Xero / FreshBooks /
/// Wave will recognise the same column shape.
class ExpenseLedgerService {
  ExpenseLedgerService._();
  static final ExpenseLedgerService instance = ExpenseLedgerService._();

  static const String _boxName = 'expense_ledger';

  Box<Receipt>? _box;
  bool _inited = false;
  final _random = Random();
  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  Future<void> init() async {
    if (_inited) return;
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ReceiptAdapter());
    }
    _box = await Hive.openBox<Receipt>(_boxName);
    _inited = true;
  }

  String nextId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    return '${ms}_${_random.nextInt(99999)}';
  }

  Future<void> save(Receipt receipt) async {
    final box = _box;
    if (!_inited || box == null) return;
    // Use the stable id as the key so updates are idempotent.
    await box.put(receipt.id, receipt);
    _changes.add(null);
  }

  Future<void> delete(String id) async {
    final box = _box;
    if (!_inited || box == null) return;
    await box.delete(id);
    _changes.add(null);
  }

  Future<List<Receipt>> getAll() async {
    final box = _box;
    if (!_inited || box == null) return [];
    final list = box.values.toList();
    // Newest captured first.
    list.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return list;
  }

  Future<int> get count async => _box?.length ?? 0;

  /// Sum all receipt totals (cast to double for the summary card).
  /// Numbers that fail to parse silently get skipped — better to show
  /// a slight undercount than crash the screen.
  Future<double> totalFor({String? currency}) async {
    final all = await getAll();
    var sum = 0.0;
    for (final r in all) {
      if (currency != null && r.currency != currency) continue;
      final v = double.tryParse(r.total ?? '');
      if (v != null) sum += v;
    }
    return sum;
  }

  /// Export every receipt to CSV. Returns a file the caller can hand
  /// to SharePlus. Columns: Date, Vendor, Total, Currency, Tax,
  /// Category, Note, Source. Header row included.
  Future<File> exportCsv({List<Receipt>? subset}) async {
    final entries = subset ?? await getAll();
    final docs = await getApplicationDocumentsDirectory();
    final exports = Directory(p.join(docs.path, 'ExpenseExports'));
    if (!await exports.exists()) {
      await exports.create(recursive: true);
    }
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final out =
        File(p.join(exports.path, 'pdfprivio_expenses_$stamp.csv'));
    final df = DateFormat('yyyy-MM-dd');
    final buf = StringBuffer();
    buf.writeln('Date,Vendor,Total,Currency,Tax,Category,Note,Source');
    for (final r in entries) {
      buf.writeln([
        _csv(r.date == null ? '' : df.format(r.date!)),
        _csv(r.vendor ?? ''),
        _csv(r.total ?? ''),
        _csv(r.currency),
        _csv(r.tax ?? ''),
        _csv(r.category ?? ''),
        _csv(r.note ?? ''),
        _csv(p.basename(r.sourcePath)),
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

  /// Copy a transient OCR source (scanner temp file, file picker
  /// cache) into the app's permanent receipts dir so the ledger
  /// thumbnail stays valid after the source temp is cleaned up.
  Future<File> archiveSource(File source) async {
    final docs = await getApplicationDocumentsDirectory();
    final archive = Directory(p.join(docs.path, 'ReceiptSources'));
    if (!await archive.exists()) {
      await archive.create(recursive: true);
    }
    final ext = p.extension(source.path);
    final name = '${DateTime.now().millisecondsSinceEpoch}'
        '_${_random.nextInt(99999)}$ext';
    final dest = File(p.join(archive.path, name));
    try {
      return await source.copy(dest.path);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ExpenseLedger.archiveSource failed: $e');
      }
      return source;
    }
  }
}
