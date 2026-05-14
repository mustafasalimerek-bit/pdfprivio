import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../core/utils/cancellation_token.dart';
import '../../core/utils/result.dart';
import '../models/pdf_document.dart';

/// One contiguous segment of the diff output.
enum DiffOp { equal, insert, delete }

/// A single piece of the diff for a page.
class DiffSegment {
  final DiffOp op;
  final String text;
  const DiffSegment(this.op, this.text);
}

/// Per-page diff for the compare result screen.
class PageDiff {
  final int pageIndex; // 0-based
  final List<DiffSegment> segments;
  final int additions;
  final int deletions;

  const PageDiff({
    required this.pageIndex,
    required this.segments,
    required this.additions,
    required this.deletions,
  });

  bool get isUnchanged => additions == 0 && deletions == 0;
}

/// Outcome of comparing two PDFs.
class CompareOutcome {
  final List<PageDiff> pages;
  final int totalAdditions;
  final int totalDeletions;
  final int changedPages;
  final int leftPageCount;
  final int rightPageCount;
  final Duration elapsed;

  const CompareOutcome({
    required this.pages,
    required this.totalAdditions,
    required this.totalDeletions,
    required this.changedPages,
    required this.leftPageCount,
    required this.rightPageCount,
    required this.elapsed,
  });

  bool get isIdentical =>
      totalAdditions == 0 &&
      totalDeletions == 0 &&
      leftPageCount == rightPageCount;
}

/// Text-based diff between two PDFs.
///
/// We extract each side's text page-by-page, then run Google's
/// diff-match-patch (the same algorithm Google Docs uses) on each pair of
/// pages. The result is a per-page list of segments tagged as
/// equal / insert / delete that the UI renders as inline redline.
///
/// We deliberately stop at text. Visual diff (layout / image changes)
/// requires pixel-level page rendering and false positives from
/// font-rendering antialiasing dominate the signal at the resolutions a
/// phone can render. Text diff is what the lawyer-review use case actually
/// asks for ("what clause changed?") — and image-only PDFs surface as
/// "nothing to compare" with a tip to run OCR first.
class PdfCompareService {
  PdfCompareService._();
  static final PdfCompareService instance = PdfCompareService._();

  Future<Result<CompareOutcome>> compare({
    required PdfDocument left,
    required PdfDocument right,
    void Function(double progress, String message)? onProgress,
    CancellationToken? cancel,
  }) async {
    final stopwatch = Stopwatch()..start();
    sf.PdfDocument? leftDoc;
    sf.PdfDocument? rightDoc;

    try {
      onProgress?.call(0.05, 'Reading left PDF…');
      final leftBytes = await left.file.readAsBytes();
      leftDoc = sf.PdfDocument(inputBytes: leftBytes);
      final leftPages = _extractAllPages(leftDoc);

      if (cancel?.isCancelled ?? false) {
        return Err(FailureKind.cancelled, 'Cancelled by user');
      }

      onProgress?.call(0.35, 'Reading right PDF…');
      final rightBytes = await right.file.readAsBytes();
      rightDoc = sf.PdfDocument(inputBytes: rightBytes);
      final rightPages = _extractAllPages(rightDoc);

      if (cancel?.isCancelled ?? false) {
        return Err(FailureKind.cancelled, 'Cancelled by user');
      }

      onProgress?.call(0.65, 'Diffing pages…');

      final maxPages = leftPages.length > rightPages.length
          ? leftPages.length
          : rightPages.length;

      final pageDiffs = <PageDiff>[];
      var totalAdditions = 0;
      var totalDeletions = 0;
      var changedPages = 0;

      for (var i = 0; i < maxPages; i++) {
        if (cancel?.isCancelled ?? false) {
          return Err(FailureKind.cancelled, 'Cancelled by user');
        }
        onProgress?.call(
          0.65 + (i / maxPages) * 0.30,
          'Diffing page ${i + 1} of $maxPages',
        );

        final l = i < leftPages.length ? leftPages[i] : '';
        final r = i < rightPages.length ? rightPages[i] : '';
        final segments = _diffSegments(l, r);

        var adds = 0;
        var dels = 0;
        for (final s in segments) {
          if (s.op == DiffOp.insert) adds += s.text.length;
          if (s.op == DiffOp.delete) dels += s.text.length;
        }

        if (adds > 0 || dels > 0) changedPages++;
        totalAdditions += adds;
        totalDeletions += dels;

        pageDiffs.add(PageDiff(
          pageIndex: i,
          segments: segments,
          additions: adds,
          deletions: dels,
        ));
      }

      stopwatch.stop();
      onProgress?.call(1.0, 'Done');

      return Ok(CompareOutcome(
        pages: pageDiffs,
        totalAdditions: totalAdditions,
        totalDeletions: totalDeletions,
        changedPages: changedPages,
        leftPageCount: leftPages.length,
        rightPageCount: rightPages.length,
        elapsed: stopwatch.elapsed,
      ));
    } catch (e) {
      stopwatch.stop();
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypt')) {
        return Err(FailureKind.needsPassword,
            'One of the PDFs is password-protected',
            cause: e);
      }
      return Err(FailureKind.unknown, 'Compare failed', cause: e);
    } finally {
      leftDoc?.dispose();
      rightDoc?.dispose();
    }
  }

  List<String> _extractAllPages(sf.PdfDocument doc) {
    final extractor = sf.PdfTextExtractor(doc);
    final out = <String>[];
    for (var i = 0; i < doc.pages.count; i++) {
      try {
        final text = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        out.add(text);
      } catch (_) {
        out.add('');
      }
    }
    return out;
  }

  List<DiffSegment> _diffSegments(String left, String right) {
    final differ = dmp.DiffMatchPatch();
    final raw = differ.diff(left, right);
    differ.diffCleanupSemantic(raw);

    return raw.map((d) {
      final op = switch (d.operation) {
        dmp.DIFF_INSERT => DiffOp.insert,
        dmp.DIFF_DELETE => DiffOp.delete,
        _ => DiffOp.equal,
      };
      return DiffSegment(op, d.text);
    }).toList();
  }
}
