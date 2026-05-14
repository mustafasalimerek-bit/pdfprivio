import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/compression_settings.dart';
import '../data/models/pdf_document.dart';
import '../data/services/pdf_compression_service.dart';

/// Single-file workspace for the Compress tool. Null = nothing picked yet.
final compressDocumentProvider = StateProvider<PdfDocument?>((_) => null);

/// Active compression progress (0.0–1.0). Null = idle.
final compressProgressProvider = StateProvider<double?>((_) => null);

/// Human-readable status line shown under the progress bar
/// ("Re-encoding page 4 of 12…").
final compressStatusProvider = StateProvider<String?>((_) => null);

/// The chosen preset for this run. Defaults to balanced; the UI swaps in a
/// smart recommendation based on file size once a doc is picked.
final compressLevelProvider =
    StateProvider<CompressionLevel>((_) => CompressionLevel.medium);

/// Custom-mode tweaks. Only consulted when the chosen level is `custom`.
final compressSettingsProvider = StateProvider<CompressionSettings>(
  (_) => CompressionSettings.preset(CompressionLevel.medium),
);

/// Last completed run, shown on the result screen.
final compressOutcomeProvider = StateProvider<CompressionOutcome?>((_) => null);

/// Recommends a preset based on input file size.
///
/// The thresholds reflect typical email + cloud upload pain points:
/// 25MB is the Gmail attachment ceiling; 10MB is the comfort zone for
/// most consumer-facing flows.
CompressionLevel recommendedLevelForSize(int sizeBytes) {
  final mb = sizeBytes / (1024 * 1024);
  if (mb < 1) return CompressionLevel.high;
  if (mb < 10) return CompressionLevel.medium;
  return CompressionLevel.low;
}
