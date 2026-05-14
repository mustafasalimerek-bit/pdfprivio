/// Quality preset for PDF compression.
///
/// Names follow the user's mental model ("how much do you want it shrunk?")
/// rather than internal terms like "DPI 72". The mapping to actual DPI and
/// JPEG quality lives in `CompressionSettings.preset`.
enum CompressionLevel { low, medium, high, custom }

extension CompressionLevelLabel on CompressionLevel {
  String get label {
    switch (this) {
      case CompressionLevel.low:
        return 'Maximum compression';
      case CompressionLevel.medium:
        return 'Balanced';
      case CompressionLevel.high:
        return 'High quality';
      case CompressionLevel.custom:
        return 'Custom';
    }
  }

  String get description {
    switch (this) {
      case CompressionLevel.low:
        return 'Smallest file, ideal for email';
      case CompressionLevel.medium:
        return 'Size/quality balance (recommended)';
      case CompressionLevel.high:
        return 'Best quality, slightly smaller';
      case CompressionLevel.custom:
        return 'Choose your own DPI and JPEG quality';
    }
  }

  /// Rough fraction of original size we expect after compression. Used to
  /// show an immediate "you'll save ~X" before the user commits — purely
  /// indicative; real ratio depends on the source PDF's content.
  double get heuristicRatio {
    switch (this) {
      case CompressionLevel.low:
        return 0.20; // ~80% reduction on image-heavy PDFs
      case CompressionLevel.medium:
        return 0.40; // ~60% reduction
      case CompressionLevel.high:
        return 0.65; // ~35% reduction
      case CompressionLevel.custom:
        return 0.50; // depends on the user's sliders
    }
  }
}

class CompressionSettings {
  final CompressionLevel level;
  final int dpi;
  final int jpegQuality;
  final bool grayscale;

  const CompressionSettings({
    required this.level,
    required this.dpi,
    required this.jpegQuality,
    this.grayscale = false,
  });

  factory CompressionSettings.preset(CompressionLevel level) {
    switch (level) {
      case CompressionLevel.low:
        return const CompressionSettings(
          level: CompressionLevel.low,
          dpi: 72,
          jpegQuality: 35,
        );
      case CompressionLevel.medium:
        return const CompressionSettings(
          level: CompressionLevel.medium,
          dpi: 110,
          jpegQuality: 60,
        );
      case CompressionLevel.high:
        return const CompressionSettings(
          level: CompressionLevel.high,
          dpi: 150,
          jpegQuality: 80,
        );
      case CompressionLevel.custom:
        return const CompressionSettings(
          level: CompressionLevel.custom,
          dpi: 110,
          jpegQuality: 60,
        );
    }
  }

  CompressionSettings copyWith({
    CompressionLevel? level,
    int? dpi,
    int? jpegQuality,
    bool? grayscale,
  }) {
    return CompressionSettings(
      level: level ?? this.level,
      dpi: dpi ?? this.dpi,
      jpegQuality: jpegQuality ?? this.jpegQuality,
      grayscale: grayscale ?? this.grayscale,
    );
  }
}
