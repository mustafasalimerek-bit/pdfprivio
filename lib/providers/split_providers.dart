import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/pdf_document.dart';

/// Mode chosen by the user on the Split screen.
enum SplitMode {
  /// Extract one inclusive page range to a single new file.
  range,

  /// Chunk the input into N-page slices.
  everyN,

  /// Chunk the input into a fixed number of (roughly) equal parts.
  parts,
}

extension SplitModeLabel on SplitMode {
  String get title {
    switch (this) {
      case SplitMode.range:
        return 'Extract a range';
      case SplitMode.everyN:
        return 'Split every N pages';
      case SplitMode.parts:
        return 'Split into parts';
    }
  }

  String get description {
    switch (this) {
      case SplitMode.range:
        return 'Pull a specific page range into one new PDF';
      case SplitMode.everyN:
        return 'Make a new PDF every N pages (chapters, signatures)';
      case SplitMode.parts:
        return 'Divide into a fixed number of roughly equal PDFs';
    }
  }
}

final splitDocumentProvider = StateProvider<PdfDocument?>((_) => null);
final splitModeProvider =
    StateProvider<SplitMode>((_) => SplitMode.range);
final splitProgressProvider = StateProvider<double?>((_) => null);

/// User input for each mode — kept independent so switching modes doesn't
/// reset the user's last range / N / parts choice.
final splitRangeStartProvider = StateProvider<int>((_) => 1);
final splitRangeEndProvider = StateProvider<int>((_) => 1);
final splitEveryNProvider = StateProvider<int>((_) => 2);
final splitPartsProvider = StateProvider<int>((_) => 2);
