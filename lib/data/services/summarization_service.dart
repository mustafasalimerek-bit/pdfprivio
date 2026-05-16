import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// Result of an availability check. The UI uses the [reason] string
/// to show an actionable message (e.g. "Enable Apple Intelligence in
/// Settings to summarise documents on-device").
enum SummarizationAvailability {
  available,
  deviceNotEligible,
  notEnabled,
  modelNotReady,
  osTooOld,
  unknown,
}

extension SummarizationAvailabilityX on SummarizationAvailability {
  /// Friendly explanation surfaced in the empty / unavailable states.
  String get message {
    switch (this) {
      case SummarizationAvailability.available:
        return 'Ready';
      case SummarizationAvailability.deviceNotEligible:
        return 'This iPhone does not support Apple Intelligence. AI '
            'summarisation requires iPhone 15 Pro / 16 / 17 series.';
      case SummarizationAvailability.notEnabled:
        return 'Apple Intelligence is turned off. Enable it in '
            'Settings → Apple Intelligence & Siri.';
      case SummarizationAvailability.modelNotReady:
        return 'Apple Intelligence is still downloading its model. '
            'Try again in a few minutes.';
      case SummarizationAvailability.osTooOld:
        return 'AI summarisation requires iOS 26 or later. Text '
            'extraction still works on older iOS.';
      case SummarizationAvailability.unknown:
        return 'Apple Intelligence is unavailable. Text extraction '
            'still works as a fallback.';
    }
  }

  bool get isReady => this == SummarizationAvailability.available;
}

/// Result of a summarisation request.
class SummarizationResult {
  /// Full summary text (combined chunks if the document was split).
  final String summary;

  /// True when the input was split into multiple chunks and each was
  /// summarised separately before being combined. Power-user
  /// information surfaced in the result screen.
  final bool wasChunked;
  final int chunkCount;
  final int charactersIn;
  final Duration elapsed;

  const SummarizationResult({
    required this.summary,
    required this.wasChunked,
    required this.chunkCount,
    required this.charactersIn,
    required this.elapsed,
  });
}

/// Apple Intelligence (FoundationModels)-backed PDF summarisation.
///
/// Map-reduce strategy:
///   * if the PDF text fits in a single chunk (~12 K chars ≈ 3 K
///     tokens), one round-trip → return the summary
///   * otherwise: split into overlapping chunks, summarise each in
///     "chunk" style, concatenate the partials, then run a second
///     pass in "concise" style over the concatenated result
///
/// Pure text in, summary out. The bridge handles all the Apple
/// Intelligence specifics; this layer just chunks, sequences, and
/// reports progress.
class SummarizationService {
  SummarizationService._();
  static final SummarizationService instance = SummarizationService._();

  static const MethodChannel _channel =
      MethodChannel('com.erekstudio.pdfprivio/summarization');

  static const int _chunkSize = 12000;
  static const int _chunkOverlap = 500;

  Future<SummarizationAvailability> availability() async {
    if (!Platform.isIOS) return SummarizationAvailability.osTooOld;
    try {
      final raw = await _channel.invokeMethod<String>('availability');
      switch (raw) {
        case 'available':
          return SummarizationAvailability.available;
        case 'device_not_eligible':
          return SummarizationAvailability.deviceNotEligible;
        case 'not_enabled':
          return SummarizationAvailability.notEnabled;
        case 'model_not_ready':
          return SummarizationAvailability.modelNotReady;
        case 'os_too_old':
          return SummarizationAvailability.osTooOld;
        default:
          return SummarizationAvailability.unknown;
      }
    } on MissingPluginException {
      return SummarizationAvailability.osTooOld;
    } catch (_) {
      return SummarizationAvailability.unknown;
    }
  }

  /// Extract text from the PDF (born-digital — Syncfusion text
  /// extractor). Scanned PDFs return empty / very short text; the
  /// caller is expected to route those through the OCR tool first.
  Future<String> extractText(File pdf) async {
    sf.PdfDocument? doc;
    try {
      final bytes = await pdf.readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);
      final extractor = sf.PdfTextExtractor(doc);
      return extractor.extractText();
    } catch (e) {
      if (kDebugMode) debugPrint('extractText failed: $e');
      return '';
    } finally {
      doc?.dispose();
    }
  }

  /// Map-reduce summarise. [onProgress] fires with values in [0, 1].
  Future<SummarizationResult?> summarize({
    required String text,
    void Function(double progress, String message)? onProgress,
  }) async {
    if (text.trim().isEmpty) return null;
    final sw = Stopwatch()..start();

    if (text.length <= _chunkSize) {
      onProgress?.call(0.3, 'Summarising…');
      final summary = await _callBridge(text: text, style: 'concise');
      sw.stop();
      if (summary == null) return null;
      onProgress?.call(1.0, 'Done');
      return SummarizationResult(
        summary: summary,
        wasChunked: false,
        chunkCount: 1,
        charactersIn: text.length,
        elapsed: sw.elapsed,
      );
    }

    final chunks = _splitChunks(text);
    final partials = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      onProgress?.call(
        (i / chunks.length) * 0.75,
        'Summarising chunk ${i + 1} of ${chunks.length}…',
      );
      final partial = await _callBridge(text: chunks[i], style: 'chunk');
      if (partial != null && partial.trim().isNotEmpty) {
        partials.add(partial.trim());
      }
    }

    if (partials.isEmpty) {
      sw.stop();
      return null;
    }

    final combined = partials.join('\n\n');
    onProgress?.call(0.85, 'Combining…');

    String finalSummary;
    if (combined.length <= _chunkSize) {
      final reduced = await _callBridge(text: combined, style: 'concise');
      finalSummary = reduced ?? combined;
    } else {
      // Very long document — keep the partials as-is to avoid losing
      // detail in a second-pass reduction that would re-truncate.
      finalSummary = combined;
    }
    sw.stop();
    onProgress?.call(1.0, 'Done');

    return SummarizationResult(
      summary: finalSummary,
      wasChunked: true,
      chunkCount: chunks.length,
      charactersIn: text.length,
      elapsed: sw.elapsed,
    );
  }

  Future<String?> _callBridge({
    required String text,
    required String style,
  }) async {
    try {
      return await _channel.invokeMethod<String>('summarize', {
        'text': text,
        'style': style,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('summarize bridge error: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Split text into overlapping char-based chunks. Tries to break on
  /// paragraph boundaries (double newline) within the last 1 K chars
  /// of each chunk so we don't slice mid-sentence and confuse the
  /// model.
  List<String> _splitChunks(String text) {
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = start + _chunkSize;
      if (end >= text.length) {
        chunks.add(text.substring(start));
        break;
      }
      // Look back up to 1 K chars for a natural break.
      final searchFrom = end - 1000;
      var splitAt = text.lastIndexOf('\n\n', end);
      if (splitAt < searchFrom) {
        splitAt = text.lastIndexOf('. ', end);
      }
      if (splitAt < searchFrom) splitAt = end;
      chunks.add(text.substring(start, splitAt));
      start = (splitAt - _chunkOverlap).clamp(0, text.length);
    }
    return chunks;
  }
}
