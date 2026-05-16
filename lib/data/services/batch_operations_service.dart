import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/compression_settings.dart';
import '../models/pdf_document.dart';
import 'audit_service.dart';
import 'pdf_compression_service.dart';
import 'pdf_metadata_service.dart';
import 'pdf_rotate_service.dart';
import 'pdf_watermark_service.dart';

/// Which transformation to apply across the batch. v1.0 ships three
/// — the lawyer's most common batch needs (shrink for email, stamp
/// CONFIDENTIAL on a stack of exhibits, fix sideways scans). Page
/// numbers, Bates, sign, redact stay single-file in v1.0 because
/// each file there needs its own per-file config.
enum BatchOperation {
  compress,
  watermark,
  rotate,
}

extension BatchOperationLabel on BatchOperation {
  String get label {
    switch (this) {
      case BatchOperation.compress:
        return 'Compress';
      case BatchOperation.watermark:
        return 'Watermark';
      case BatchOperation.rotate:
        return 'Rotate';
    }
  }

  String get description {
    switch (this) {
      case BatchOperation.compress:
        return 'Shrink every PDF for email — quality preset applies '
            'uniformly across the batch.';
      case BatchOperation.watermark:
        return 'Stamp the same text watermark on every page of every '
            'PDF (CONFIDENTIAL, DRAFT, etc.).';
      case BatchOperation.rotate:
        return 'Rotate every page of every PDF by the same quarter '
            'turn — fix sideways scans in bulk.';
    }
  }
}

/// Bundle of per-operation params. Only the field matching the
/// chosen [BatchOperation] is read.
class BatchParams {
  final CompressionLevel compressionLevel;
  final WatermarkSettings watermarkSettings;
  final PdfRotation rotation;

  const BatchParams({
    this.compressionLevel = CompressionLevel.medium,
    this.watermarkSettings = const WatermarkSettings(
      text: 'CONFIDENTIAL',
      layout: WatermarkLayout.diagonal,
      opacity: WatermarkOpacity.medium,
    ),
    this.rotation = PdfRotation.cw90,
  });
}

/// Result of a single file inside the batch.
class BatchItemResult {
  final File inputFile;
  final File? outputFile;
  final String? error;

  const BatchItemResult({
    required this.inputFile,
    this.outputFile,
    this.error,
  });

  bool get success => outputFile != null && error == null;
}

/// Final batch summary.
class BatchOutcome {
  final BatchOperation operation;
  final Directory outputDirectory;
  final List<BatchItemResult> items;
  final Duration elapsed;

  const BatchOutcome({
    required this.operation,
    required this.outputDirectory,
    required this.items,
    required this.elapsed,
  });

  int get successCount => items.where((i) => i.success).length;
  int get failureCount => items.length - successCount;
}

/// Orchestrator for sequential batch processing. We deliberately do
/// NOT parallelise across files — Syncfusion's PDF engine is single-
/// threaded per document and 30 simultaneous renders OOM-kill the
/// app on a 6 GB iPhone. Sequential keeps memory predictable and
/// progress reporting honest.
class BatchOperationsService {
  BatchOperationsService._();
  static final BatchOperationsService instance = BatchOperationsService._();

  Future<BatchOutcome> runBatch({
    required BatchOperation operation,
    required List<File> files,
    required BatchParams params,
    void Function(int currentIndex, int total, String currentFile)? onProgress,
    CancellationToken? cancel,
  }) async {
    final sw = Stopwatch()..start();
    final outDir = await _createOutputDir(operation);
    final items = <BatchItemResult>[];

    for (var i = 0; i < files.length; i++) {
      if (cancel?.isCancelled ?? false) break;
      final file = files[i];
      onProgress?.call(i, files.length, p.basename(file.path));

      final result = await _runOne(
        operation: operation,
        file: file,
        params: params,
        outDir: outDir,
      );
      items.add(result);
    }

    sw.stop();

    final summary = BatchOutcome(
      operation: operation,
      outputDirectory: outDir,
      items: items,
      elapsed: sw.elapsed,
    );

    await AuditService.instance.record(
      tool: 'batch',
      params: {
        'operation': operation.label,
        'fileCount': '${files.length}',
        'successCount': '${summary.successCount}',
        'failureCount': '${summary.failureCount}',
        'elapsedMs': '${sw.elapsedMilliseconds}',
      },
    );

    return summary;
  }

  Future<BatchItemResult> _runOne({
    required BatchOperation operation,
    required File file,
    required BatchParams params,
    required Directory outDir,
  }) async {
    final inspectOutcome = await PdfMetadataService.instance.inspect(file);
    if (inspectOutcome is Err<PdfDocument>) {
      return BatchItemResult(inputFile: file, error: inspectOutcome.message);
    }
    final doc = (inspectOutcome as Ok<PdfDocument>).value;

    try {
      switch (operation) {
        case BatchOperation.compress:
          final res = await PdfCompressionService.instance.compress(
            input: doc,
            settings: CompressionSettings.preset(params.compressionLevel),
          );
          if (res is Ok<CompressionOutcome>) {
            final relocated = await _relocate(res.value.compressed, outDir);
            return BatchItemResult(inputFile: file, outputFile: relocated);
          }
          return BatchItemResult(
            inputFile: file,
            error: (res as Err<CompressionOutcome>).message,
          );
        case BatchOperation.watermark:
          final res = await PdfWatermarkService.instance.stamp(
            input: doc,
            settings: params.watermarkSettings,
          );
          if (res is Ok<File>) {
            final relocated = await _relocate(res.value, outDir);
            return BatchItemResult(inputFile: file, outputFile: relocated);
          }
          return BatchItemResult(
            inputFile: file,
            error: (res as Err<File>).message,
          );
        case BatchOperation.rotate:
          final res = await PdfRotateService.instance.rotateAll(
            input: doc,
            rotation: params.rotation,
          );
          if (res is Ok<File>) {
            final relocated = await _relocate(res.value, outDir);
            return BatchItemResult(inputFile: file, outputFile: relocated);
          }
          return BatchItemResult(
            inputFile: file,
            error: (res as Err<File>).message,
          );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BatchOperationsService item failure for ${file.path}: $e');
      }
      return BatchItemResult(inputFile: file, error: e.toString());
    }
  }

  /// Move the per-tool output into our batch folder so every file
  /// from one run lives in a single shareable directory.
  Future<File> _relocate(File src, Directory outDir) async {
    final dest = File(p.join(outDir.path, p.basename(src.path)));
    try {
      return await src.rename(dest.path);
    } catch (_) {
      // Cross-device rename can fail in the sandbox — fall back to
      // copy + delete-source.
      await src.copy(dest.path);
      try {
        await src.delete();
      } catch (_) {}
      return dest;
    }
  }

  Future<Directory> _createOutputDir(BatchOperation op) async {
    final docs = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dir = Directory(p.join(docs.path, 'BatchOutputs',
        '${op.label.toLowerCase()}_$stamp'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
