import Flutter
import UIKit
import Vision

/// Bridges Apple Vision's `VNRecognizeTextRequest` to Flutter so we can do
/// on-device OCR with no model downloads and no cloud calls.
///
/// MethodChannel: `com.erekstudio.pdfwork/text_recognizer`
///
/// Methods:
///   `recognize` — args: { imagePath: String, languages: [String], level: "fast"|"accurate" }
///     Returns: {
///       width: Double,   // image pixel width
///       height: Double,  // image pixel height
///       observations: [
///         {
///           text: String,
///           confidence: Double,
///           // bbox is normalized (0..1), origin bottom-left (Vision convention,
///           // which happens to match PDF user space).
///           x: Double, y: Double, w: Double, h: Double
///         }, ...
///       ]
///     }
///   `supportedLanguages` — args: { level: "fast"|"accurate" } → [String]
class TextRecognizerBridge: NSObject, FlutterPlugin {
  static let channelName = "com.erekstudio.pdfwork/text_recognizer"

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = TextRecognizerBridge()
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "recognize":
      handleRecognize(call: call, result: result)
    case "supportedLanguages":
      handleSupportedLanguages(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleRecognize(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let imagePath = args["imagePath"] as? String else {
      result(FlutterError(code: "bad_args",
                          message: "imagePath is required.",
                          details: nil))
      return
    }
    let languages = (args["languages"] as? [String]) ?? ["en-US"]
    let level = (args["level"] as? String) ?? "accurate"

    DispatchQueue.global(qos: .userInitiated).async {
      self.recognize(
        imagePath: imagePath,
        languages: languages,
        level: level
      ) { response in
        DispatchQueue.main.async {
          result(response)
        }
      }
    }
  }

  private func handleSupportedLanguages(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let level = (args?["level"] as? String) ?? "accurate"
    let recognitionLevel: VNRequestTextRecognitionLevel =
      (level == "fast") ? .fast : .accurate
    do {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = recognitionLevel
      if #available(iOS 15.0, *) {
        let langs = try request.supportedRecognitionLanguages()
        result(langs)
      } else {
        result(["en-US"])
      }
    } catch {
      result(FlutterError(code: "lang_query_failed",
                          message: error.localizedDescription,
                          details: nil))
    }
  }

  private func recognize(
    imagePath: String,
    languages: [String],
    level: String,
    completion: @escaping (Any) -> Void
  ) {
    guard let uiImage = UIImage(contentsOfFile: imagePath),
          let cgImage = uiImage.cgImage else {
      completion(FlutterError(
        code: "image_load_failed",
        message: "Could not load image at \(imagePath).",
        details: nil
      ))
      return
    }

    let width = Double(cgImage.width)
    let height = Double(cgImage.height)

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = (level == "fast") ? .fast : .accurate
    request.usesLanguageCorrection = true
    if #available(iOS 14.0, *) {
      request.recognitionLanguages = languages
    }

    do {
      let handler = VNImageRequestHandler(cgImage: cgImage,
                                          orientation: imageOrientation(uiImage),
                                          options: [:])
      try handler.perform([request])
    } catch {
      completion(FlutterError(
        code: "ocr_failed",
        message: error.localizedDescription,
        details: nil
      ))
      return
    }

    var observations: [[String: Any]] = []
    if let results = request.results {
      for obs in results {
        guard let candidate = obs.topCandidates(1).first else { continue }
        let bbox = obs.boundingBox
        observations.append([
          "text": candidate.string,
          "confidence": Double(candidate.confidence),
          "x": Double(bbox.origin.x),
          "y": Double(bbox.origin.y),
          "w": Double(bbox.size.width),
          "h": Double(bbox.size.height),
        ])
      }
    }

    completion([
      "width": width,
      "height": height,
      "observations": observations,
    ])
  }

  private func imageOrientation(_ image: UIImage) -> CGImagePropertyOrientation {
    switch image.imageOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
