import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/utils/result.dart';

/// One recognized line/block from Apple Vision.
///
/// Bounding box is in **normalized PDF coordinates** (0..1, origin
/// bottom-left) — matches Vision's native space, which we flip to PDF
/// when laying down the text layer.
class OcrObservation {
  final String text;
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;

  const OcrObservation({
    required this.text,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class OcrPageResult {
  final double imageWidth;
  final double imageHeight;
  final List<OcrObservation> observations;
  const OcrPageResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.observations,
  });

  String get plainText {
    final buf = StringBuffer();
    for (final o in observations) {
      buf.writeln(o.text);
    }
    return buf.toString().trim();
  }

  int get wordCount =>
      observations.fold(0, (a, o) => a + o.text.split(RegExp(r'\s+')).length);
}

enum OcrLevel { fast, accurate }

class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  static const MethodChannel _channel =
      MethodChannel('com.erekstudio.pdfprivio/text_recognizer');

  Future<List<String>> supportedLanguages({
    OcrLevel level = OcrLevel.accurate,
  }) async {
    if (!Platform.isIOS) return const ['en-US'];
    try {
      final res = await _channel.invokeMethod<List<dynamic>>(
        'supportedLanguages',
        {'level': level.name},
      );
      return (res ?? const []).cast<String>();
    } catch (_) {
      return const ['en-US'];
    }
  }

  Future<Result<OcrPageResult>> recognize({
    required File image,
    List<String> languages = const ['en-US'],
    OcrLevel level = OcrLevel.accurate,
  }) async {
    if (!Platform.isIOS) {
      return Err(FailureKind.unknown,
          'OCR is iOS-only right now — Android coming with ML Kit later.');
    }
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'recognize',
        {
          'imagePath': image.path,
          'languages': languages,
          'level': level.name,
        },
      );
      if (result == null) {
        return Err(FailureKind.unknown, 'No OCR result.');
      }
      final width = (result['width'] as num).toDouble();
      final height = (result['height'] as num).toDouble();
      final rawObs = result['observations'] as List<dynamic>? ?? const [];
      final obs = rawObs.map((e) {
        final m = e as Map<dynamic, dynamic>;
        return OcrObservation(
          text: m['text'] as String,
          confidence: (m['confidence'] as num).toDouble(),
          x: (m['x'] as num).toDouble(),
          y: (m['y'] as num).toDouble(),
          width: (m['w'] as num).toDouble(),
          height: (m['h'] as num).toDouble(),
        );
      }).toList();
      return Ok(OcrPageResult(
        imageWidth: width,
        imageHeight: height,
        observations: obs,
      ));
    } on PlatformException catch (e) {
      return Err(FailureKind.unknown,
          e.message ?? 'OCR failed.', cause: e);
    } catch (e) {
      return Err(FailureKind.unknown, 'OCR failed.', cause: e);
    }
  }
}
