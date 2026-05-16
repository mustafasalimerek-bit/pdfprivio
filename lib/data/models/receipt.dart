import 'package:hive/hive.dart';

/// A single receipt parsed from OCR, persisted to the on-device
/// expense ledger. Built for the lawyer/CPA/freelancer wedge — pull
/// receipts off the phone and reconcile them at tax time without a
/// trip to a SaaS uploader.
///
/// Field-level heuristics live in [ReceiptExtractionService]. Every
/// value here is editable in the capture sheet before save, so we
/// trust the user, not the extractor, as the source of truth.
class Receipt {
  /// Stable sort key: `<epoch_ms>_<random>` — same pattern as
  /// AuditEntry so chronological iteration is cheap.
  final String id;

  /// When the receipt was captured (not necessarily the receipt date —
  /// that's [date]). UTC.
  final DateTime capturedAt;

  /// The date printed on the receipt. Null if extraction couldn't
  /// find one and the user didn't enter one.
  final DateTime? date;

  /// Vendor / merchant name as printed on the receipt.
  final String? vendor;

  /// Grand total in [currency]. Stored as a string to dodge floating-
  /// point rounding ("12.34", not 12.34d).
  final String? total;

  /// Tax line, if extractor found one. Same string-money convention.
  final String? tax;

  /// ISO-4217-ish currency code derived from the symbol on the
  /// receipt. Default 'USD' when nothing was detected.
  final String currency;

  /// Free-form note the user added (e.g. "client lunch — Smith case").
  final String? note;

  /// Tag the user assigned (e.g. "Travel", "Meals", "Office") so they
  /// can filter the ledger before export.
  final String? category;

  /// Path to the source image/PDF the receipt was OCR'd from. Lives
  /// in the app sandbox.
  final String sourcePath;

  /// Raw OCR text — kept so the user can re-edit fields without
  /// re-scanning, and so a sceptical accountant can audit the
  /// heuristic extraction against the source.
  final String rawText;

  const Receipt({
    required this.id,
    required this.capturedAt,
    this.date,
    this.vendor,
    this.total,
    this.tax,
    this.currency = 'USD',
    this.note,
    this.category,
    required this.sourcePath,
    required this.rawText,
  });

  Receipt copyWith({
    DateTime? date,
    String? vendor,
    String? total,
    String? tax,
    String? currency,
    String? note,
    String? category,
  }) {
    return Receipt(
      id: id,
      capturedAt: capturedAt,
      date: date ?? this.date,
      vendor: vendor ?? this.vendor,
      total: total ?? this.total,
      tax: tax ?? this.tax,
      currency: currency ?? this.currency,
      note: note ?? this.note,
      category: category ?? this.category,
      sourcePath: sourcePath,
      rawText: rawText,
    );
  }
}

/// Hand-written adapter — same convention as AuditEntryAdapter.
/// typeId=2 because AuditEntry holds typeId=1.
class ReceiptAdapter extends TypeAdapter<Receipt> {
  @override
  final int typeId = 2;

  @override
  Receipt read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < fieldCount; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return Receipt(
      id: fields[0] as String,
      capturedAt: fields[1] as DateTime,
      date: fields[2] as DateTime?,
      vendor: fields[3] as String?,
      total: fields[4] as String?,
      tax: fields[5] as String?,
      currency: (fields[6] as String?) ?? 'USD',
      note: fields[7] as String?,
      category: fields[8] as String?,
      sourcePath: fields[9] as String,
      rawText: fields[10] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Receipt obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.capturedAt)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.vendor)
      ..writeByte(4)
      ..write(obj.total)
      ..writeByte(5)
      ..write(obj.tax)
      ..writeByte(6)
      ..write(obj.currency)
      ..writeByte(7)
      ..write(obj.note)
      ..writeByte(8)
      ..write(obj.category)
      ..writeByte(9)
      ..write(obj.sourcePath)
      ..writeByte(10)
      ..write(obj.rawText);
  }
}
