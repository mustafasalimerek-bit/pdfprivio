import 'dart:io';
import 'dart:ui' show Offset;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';
import 'audit_service.dart';

/// Three concrete split strategies — every shipping competitor supports a
/// subset of these and most of them gate them behind different paywalls;
/// we expose all three in the free tier.
class PdfSplitService {
  PdfSplitService._();
  static final PdfSplitService instance = PdfSplitService._();

  /// Extracts a single inclusive page range [startPage, endPage] (1-based)
  /// into one new file.
  Future<Result<File>> extractRange({
    required PdfDocument input,
    required int startPage,
    required int endPage,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  }) async {
    if (startPage < 1 || endPage > input.pageCount || startPage > endPage) {
      return Err(FailureKind.unknown,
          'Range must be between 1 and ${input.pageCount}');
    }

    sf.PdfDocument? src;
    sf.PdfDocument? out;
    try {
      final bytes = await input.file.readAsBytes();
      src = sf.PdfDocument(inputBytes: bytes);
      out = _newEmptyDoc();

      final total = endPage - startPage + 1;
      for (var i = startPage - 1; i < endPage; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }
        _copyPage(out, src.pages[i]);
        onProgress?.call((i - (startPage - 1) + 1) / total);
      }

      final outBytes = await out.save();
      final file = await _writeOutput(
        outBytes,
        '${input.displayName}_p$startPage-$endPage',
      );
      await AuditService.instance.record(
        tool: 'split',
        inputFile: input.file,
        outputFile: file,
        params: {
          'mode': 'extractRange',
          'startPage': '$startPage',
          'endPage': '$endPage',
        },
      );
      return Ok(file);
    } catch (e) {
      return _classify(e);
    } finally {
      src?.dispose();
      out?.dispose();
    }
  }

  /// Splits the input into chunks of [n] pages each. The last chunk may be
  /// shorter if total pages isn't a multiple of n.
  Future<Result<List<File>>> splitEveryNPages({
    required PdfDocument input,
    required int n,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  }) async {
    if (n < 1) return Err(FailureKind.unknown, 'N must be at least 1');
    if (n >= input.pageCount) {
      return Err(FailureKind.unknown,
          'N must be less than the document page count');
    }

    final ranges = <(int, int)>[];
    for (var start = 0; start < input.pageCount; start += n) {
      final end = (start + n - 1).clamp(0, input.pageCount - 1);
      ranges.add((start + 1, end + 1)); // 1-based
    }
    return _splitByRanges(input, ranges, onProgress, cancel);
  }

  /// Splits the input into [count] roughly equal parts. Useful for "I want
  /// this in 4 files" without the user calculating page counts.
  Future<Result<List<File>>> splitIntoNParts({
    required PdfDocument input,
    required int count,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  }) async {
    if (count < 2) {
      return Err(FailureKind.unknown, 'Need at least 2 parts');
    }
    if (count > input.pageCount) {
      return Err(FailureKind.unknown,
          'Cannot split ${input.pageCount} pages into $count parts');
    }

    final base = input.pageCount ~/ count;
    final remainder = input.pageCount % count;
    final ranges = <(int, int)>[];
    var cursor = 1;
    for (var i = 0; i < count; i++) {
      final size = base + (i < remainder ? 1 : 0);
      ranges.add((cursor, cursor + size - 1));
      cursor += size;
    }
    return _splitByRanges(input, ranges, onProgress, cancel);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<Result<List<File>>> _splitByRanges(
    PdfDocument input,
    List<(int, int)> ranges,
    void Function(double)? onProgress,
    CancellationToken? cancel,
  ) async {
    sf.PdfDocument? src;
    try {
      final bytes = await input.file.readAsBytes();
      src = sf.PdfDocument(inputBytes: bytes);

      final outputs = <File>[];
      for (var r = 0; r < ranges.length; r++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }

        final (start, end) = ranges[r];
        final part = _newEmptyDoc();
        try {
          for (var i = start - 1; i < end; i++) {
            _copyPage(part, src.pages[i]);
          }
          final outBytes = await part.save();
          final file = await _writeOutput(
            outBytes,
            '${input.displayName}_part${r + 1}',
          );
          outputs.add(file);
        } finally {
          part.dispose();
        }
        onProgress?.call((r + 1) / ranges.length);
      }
      await AuditService.instance.record(
        tool: 'split',
        inputFile: input.file,
        params: {
          'mode': 'multiRange',
          'partCount': '${outputs.length}',
        },
      );
      return Ok(outputs);
    } catch (e) {
      return _classify(e);
    } finally {
      src?.dispose();
    }
  }

  sf.PdfDocument _newEmptyDoc() {
    final doc = sf.PdfDocument();
    doc.pageSettings.margins.all = 0;
    if (doc.pages.count > 0) doc.pages.removeAt(0);
    return doc;
  }

  void _copyPage(sf.PdfDocument out, sf.PdfPage srcPage) {
    out.pageSettings.size = srcPage.size;
    final dst = out.pages.add();
    dst.graphics.drawPdfTemplate(srcPage.createTemplate(), Offset.zero);
  }

  Future<File> _writeOutput(List<int> bytes, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = baseName.replaceAll(RegExp(r'[\\/]'), '_').trim();
    final path = p.join(dir.path, '$safe.pdf');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Result<T> _classify<T>(Object e) {
    final lower = e.toString().toLowerCase();
    if (lower.contains('password') || lower.contains('encrypt')) {
      return Err(FailureKind.needsPassword, 'PDF is password-protected',
          cause: e);
    }
    return Err(FailureKind.unknown, 'Split failed', cause: e);
  }
}
