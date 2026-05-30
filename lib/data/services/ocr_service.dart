import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;
import 'package:image/image.dart' as img;

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
    if (Platform.isIOS) {
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
    if (Platform.isAndroid) {
      // ML Kit on Android supports Latin/Chinese/Japanese/Korean/Devanagari
      // scripts. We expose a representative ISO-639 language per script so
      // callers can drive UI pickers without dispatching to the native side.
      return const ['en-US', 'zh-Hans', 'ja-JP', 'ko-KR', 'hi-IN'];
    }
    return const ['en-US'];
  }

  Future<Result<OcrPageResult>> recognize({
    required File image,
    List<String> languages = const ['en-US'],
    OcrLevel level = OcrLevel.accurate,
  }) async {
    if (Platform.isIOS) {
      return _recognizeIOS(image, languages, level);
    }
    if (Platform.isAndroid) {
      return _recognizeAndroid(image, languages);
    }
    return Err(FailureKind.unknown, 'OCR requires iOS or Android.');
  }

  Future<Result<OcrPageResult>> _recognizeIOS(
    File image,
    List<String> languages,
    OcrLevel level,
  ) async {
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

  /// Android implementation via Google ML Kit Text Recognition (on-device,
  /// no cloud — same privacy posture as the iOS Apple Vision path).
  ///
  /// Coordinates are normalised to 0..1 with origin top-left to match the
  /// iOS Vision path's `OcrObservation` contract (downstream consumers
  /// flip top/bottom origin themselves when composing the searchable PDF
  /// text layer — see [PdfOcrComposeService]). Confidence is set to 1.0
  /// because ML Kit does not expose per-line confidence on its line API.
  Future<Result<OcrPageResult>> _recognizeAndroid(
    File image,
    List<String> languages,
  ) async {
    final script = _scriptForLanguages(languages);
    final recognizer = mlkit.TextRecognizer(script: script);
    try {
      // ML Kit returns pixel boundingBoxes — we need image dimensions to
      // normalise. Decoding via the `image` package keeps us off the
      // platform channel for this measurement.
      final bytes = await image.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return Err(FailureKind.unknown,
            "Couldn't decode image for OCR.");
      }
      final w = decoded.width.toDouble();
      final h = decoded.height.toDouble();

      final input = mlkit.InputImage.fromFile(image);
      final result = await recognizer.processImage(input);

      final observations = <OcrObservation>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final box = line.boundingBox;
          observations.add(OcrObservation(
            text: line.text,
            confidence: 1.0,
            x: box.left / w,
            y: box.top / h,
            width: box.width / w,
            height: box.height / h,
          ));
        }
      }
      return Ok(OcrPageResult(
        imageWidth: w,
        imageHeight: h,
        observations: observations,
      ));
    } catch (e) {
      return Err(FailureKind.unknown, 'OCR failed.', cause: e);
    } finally {
      await recognizer.close();
    }
  }

  /// Map ISO-639 language hints to the ML Kit script enum. ML Kit ships
  /// five script bundles; the first language whose script matches wins.
  /// Anything not matching falls back to Latin (covers English + most
  /// European languages including Turkish, Spanish, German, etc.).
  mlkit.TextRecognitionScript _scriptForLanguages(List<String> languages) {
    for (final lang in languages) {
      final l = lang.toLowerCase();
      if (l.startsWith('zh')) return mlkit.TextRecognitionScript.chinese;
      if (l.startsWith('ja')) return mlkit.TextRecognitionScript.japanese;
      if (l.startsWith('ko')) return mlkit.TextRecognitionScript.korean;
      if (l.startsWith('hi')) return mlkit.TextRecognitionScript.devanagiri;
    }
    return mlkit.TextRecognitionScript.latin;
  }
}
