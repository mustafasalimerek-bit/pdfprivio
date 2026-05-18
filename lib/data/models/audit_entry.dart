import 'package:hive/hive.dart';

/// A single row in Privio's audit log — one persisted record of a
/// completed tool operation.
///
/// What we record:
///   * when it happened (UTC timestamp)
///   * which tool ran (string id like 'sign', 'redact', 'ocr')
///   * input + output file metadata (name, size, SHA-256 prefix) —
///     enough to defensibly tie the entry back to a specific
///     document later
///   * operation-specific params (string-keyed string map for Hive
///     compatibility — e.g. signer name, redacted-term count, OCR
///     language)
///
/// What we deliberately do NOT record:
///   * the file contents themselves — only metadata
///   * the actual redacted text or PII matches — the audit log lives
///     on-device but lawyer-client privilege still applies to the
///     log; we capture COUNTS, not content
///   * any user PII (no Apple ID, no IDFA, no email) — the log only
///     describes what was DONE, not who did it
///
/// Defensibly fills the role compliance-conscious lawyers / CPAs
/// expect under ABA Model Rule 1.15, SOX §404 controls, GDPR Art. 30
/// record-of-processing, etc.: "show me what I did to this PDF, when,
/// with what settings."
class AuditEntry {
  /// Stable, sortable id: `<epoch_ms>_<tool>_<random>`. Used as the
  /// Hive box key so chronological iteration is cheap and entries
  /// stay unique even when two operations land in the same millisecond.
  final String id;
  final DateTime timestamp;
  final String tool;
  final String? inputFileName;
  final int? inputSizeBytes;
  final String? inputSha256Prefix;
  final String? outputFileName;
  final int? outputSizeBytes;
  final Map<String, String> params;
  final bool success;

  const AuditEntry({
    required this.id,
    required this.timestamp,
    required this.tool,
    this.inputFileName,
    this.inputSizeBytes,
    this.inputSha256Prefix,
    this.outputFileName,
    this.outputSizeBytes,
    this.params = const {},
    this.success = true,
  });
}

/// Hand-written Hive adapter — no build_runner / codegen step in this
/// project, and a single 10-field model doesn't justify pulling that
/// rig in. typeId=1 is reserved for AuditEntry; if you add another
/// Hive-stored type, pick typeId=2+ to keep the wire format stable.
class AuditEntryAdapter extends TypeAdapter<AuditEntry> {
  @override
  final int typeId = 1;

  @override
  AuditEntry read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < fieldCount; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return AuditEntry(
      id: fields[0] as String,
      timestamp: fields[1] as DateTime,
      tool: fields[2] as String,
      inputFileName: fields[3] as String?,
      inputSizeBytes: fields[4] as int?,
      inputSha256Prefix: fields[5] as String?,
      outputFileName: fields[6] as String?,
      outputSizeBytes: fields[7] as int?,
      params: (fields[8] as Map?)?.cast<String, String>() ?? const {},
      success: (fields[9] as bool?) ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, AuditEntry obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.tool)
      ..writeByte(3)
      ..write(obj.inputFileName)
      ..writeByte(4)
      ..write(obj.inputSizeBytes)
      ..writeByte(5)
      ..write(obj.inputSha256Prefix)
      ..writeByte(6)
      ..write(obj.outputFileName)
      ..writeByte(7)
      ..write(obj.outputSizeBytes)
      ..writeByte(8)
      ..write(obj.params)
      ..writeByte(9)
      ..write(obj.success);
  }
}
