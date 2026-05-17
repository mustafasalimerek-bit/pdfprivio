import AVFoundation
import CoreImage
import Flutter
import PDFKit
import SwiftUI
import UIKit
import Vision
import VisionKit

// =============================================================================
// MARK: - Brand Colors
// =============================================================================

extension Color {
  // Mirrors lib/core/theme/colors.dart so the native scanner reads as
  // part of PDFPrivio, not a generic Apple sample. Keep in sync with
  // AppColors when palette changes.
  static let brandTeal = Color(red: 0x0F / 255.0,
                               green: 0x76 / 255.0,
                               blue: 0x6E / 255.0)
  static let brandTealDark = Color(red: 0x0B / 255.0,
                                   green: 0x56 / 255.0,
                                   blue: 0x50 / 255.0)
  static let brandTealLight = Color(red: 0x14 / 255.0,
                                    green: 0xB8 / 255.0,
                                    blue: 0xA6 / 255.0)
  static let brandTealBg = Color(red: 0xDD / 255.0,
                                 green: 0xEA / 255.0,
                                 blue: 0xE6 / 255.0)
  static let brandCream = Color(red: 0xF5 / 255.0,
                                green: 0xF1 / 255.0,
                                blue: 0xEA / 255.0)
  static let brandBorder = Color(red: 0xE7 / 255.0,
                                 green: 0xE0 / 255.0,
                                 blue: 0xD2 / 255.0)
  static let brandTextPrimary = Color(red: 0x0F / 255.0,
                                      green: 0x17 / 255.0,
                                      blue: 0x2A / 255.0)
  static let brandTextSecondary = Color(red: 0x64 / 255.0,
                                        green: 0x74 / 255.0,
                                        blue: 0x8B / 255.0)
  static let brandTextTertiary = Color(red: 0x94 / 255.0,
                                       green: 0xA3 / 255.0,
                                       blue: 0xB8 / 255.0)
  static let brandSuccess = Color(red: 0x10 / 255.0,
                                  green: 0xB9 / 255.0,
                                  blue: 0x81 / 255.0)
  static let brandWarning = Color(red: 0xF5 / 255.0,
                                  green: 0x9E / 255.0,
                                  blue: 0x0B / 255.0)
  static let brandError = Color(red: 0xEF / 255.0,
                                green: 0x44 / 255.0,
                                blue: 0x44 / 255.0)
}

// =============================================================================
// MARK: - Scanner Models
// =============================================================================

/// Capture flavor. Tunes edge detection, default enhancement, OCR
/// requirement, and post-capture flow (single page vs. flip vs. multi).
/// Raw values are the wire string sent over MethodChannel from Dart.
enum ScanMode: String {
  case doc
  case receipt
  case card
  case id

  var displayName: String {
    switch self {
    case .doc: return "Document"
    case .receipt: return "Receipt"
    case .card: return "Card"
    case .id: return "ID"
    }
  }

  var shortLabel: String {
    switch self {
    case .doc: return "Doc"
    case .receipt: return "Receipt"
    case .card: return "Card"
    case .id: return "ID"
    }
  }

  var iconName: String {
    switch self {
    case .doc: return "doc.text"
    case .receipt: return "receipt"
    case .card: return "creditcard"
    case .id: return "person.text.rectangle"
    }
  }

  /// VNDetectRectanglesRequest tuning per mode. A receipt is tall +
  /// narrow; a credit card is closer to a 1.6:1 landscape; a passport
  /// page is a tight portrait. Doc is the loose default.
  var rectangleDetectionConfig: (
    aspectMin: Float, aspectMax: Float, sizeMin: Float, quadTolerance: Float
  ) {
    switch self {
    case .doc:
      return (0.4, 1.0, 0.3, 25)
    case .receipt:
      return (0.15, 0.6, 0.2, 30)
    case .card:
      return (0.55, 0.7, 0.35, 15)
    case .id:
      return (0.6, 0.72, 0.35, 18)
    }
  }

  var defaultEnhancement: EnhancementMode {
    switch self {
    case .doc: return .colorDocument
    case .receipt: return .blackAndWhite
    case .card: return .magicColor
    case .id: return .colorDocument
    }
  }

  var requiresOCR: Bool {
    switch self {
    case .receipt, .id: return true
    case .doc, .card: return false
    }
  }

  var supportsMultiPage: Bool {
    switch self {
    case .doc, .receipt: return true
    case .card, .id: return false
    }
  }

  /// Card always wants front+back. Other modes are single-side.
  var requiresTwoSides: Bool {
    switch self {
    case .card: return true
    case .doc, .receipt, .id: return false
    }
  }
}

/// Which face of a card a captured page represents. Only meaningful
/// for `.card` mode; nil for everything else.
enum CardSide {
  case front, back
}

/// Structured output for modes that extract content (receipt parsing,
/// ID redaction). Marshals over MethodChannel as `[String: Any]`.
struct ScanMetadata {
  var extractedDate: Date?
  var extractedAmount: Double?
  var extractedCurrency: String?
  var extractedMerchant: String?
  var redactedFields: [String] = []
  var ocrText: String?
}

enum ScannerGuidance: Equatable {
  case searching
  case moveCloser
  case moveFurther
  case holdSteady
  case improveLight
  case detected(quality: CGFloat)
  case readyToCapture
  case capturing
  /// Card mode only — fired after the front side capture so the user
  /// flips the card while the coordinator resets for the back side.
  case flipCard

  var userMessage: String {
    switch self {
    case .searching: return "Looking for document"
    case .moveCloser: return "Move closer"
    case .moveFurther: return "Move further away"
    case .holdSteady: return "Hold steady"
    case .improveLight: return "Move to better light"
    case .detected: return "Detected"
    case .readyToCapture: return "Capturing in 1s…"
    case .capturing: return "Captured"
    case .flipCard: return "Now flip the card"
    }
  }

  var iconName: String? {
    switch self {
    case .searching: return nil
    case .moveCloser: return "arrow.up.right.and.arrow.down.left"
    case .moveFurther: return "arrow.down.left.and.arrow.up.right"
    case .holdSteady: return "hand.raised.fill"
    case .improveLight: return "lightbulb.fill"
    case .detected, .readyToCapture: return "checkmark.circle.fill"
    case .capturing: return "camera.fill"
    case .flipCard: return "arrow.triangle.2.circlepath"
    }
  }

  var isReady: Bool {
    switch self {
    case .detected, .readyToCapture, .capturing: return true
    default: return false
    }
  }
}

enum EnhancementMode: String, CaseIterable, Identifiable {
  case original = "Original"
  case colorDocument = "Color"
  case grayscale = "Grayscale"
  case blackAndWhite = "B&W"
  case magicColor = "Magic"

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .original: return "photo"
    case .colorDocument: return "doc.text"
    case .grayscale: return "circle.lefthalf.filled"
    case .blackAndWhite: return "circle.fill"
    case .magicColor: return "wand.and.stars"
    }
  }
}

struct ScannedPage: Identifiable {
  let id = UUID()
  let originalImage: UIImage
  var correctedImage: UIImage
  var enhancedImage: UIImage
  var quad: [CGPoint]
  var enhancementMode: EnhancementMode = .colorDocument
  var blurScore: Double
  /// Card mode tags pages as `.front` or `.back` so [PDFAssembler]
  /// can lay them out side-by-side. nil for every other mode.
  var side: CardSide?

  /// Whether the sharpness score is low enough to suggest a retake.
  /// Card / ID get a looser threshold because users naturally hold
  /// the subject closer than the device can quickly lock focus on —
  /// 0.3 was rejecting otherwise fine captures.
  func needsRetake(forMode mode: ScanMode) -> Bool {
    let threshold: Double
    switch mode {
    case .card, .id: threshold = 0.18
    case .receipt: threshold = 0.22
    case .doc: threshold = 0.30
    }
    return blurScore < threshold
  }
}

// =============================================================================
// MARK: - Blur Detector (Laplacian variance)
// =============================================================================

enum BlurDetector {
  private static let context = CIContext(options: [.useSoftwareRenderer: false])

  /// 0.0 (blurry) — 1.0 (sharp). Threshold < 0.3 → flag for retake.
  static func calculateSharpness(of image: UIImage) -> Double {
    guard let cgImage = image.cgImage else { return 0 }

    let target = CGSize(width: 256, height: 256)
    guard let downscaled = downscale(cgImage: cgImage, to: target) else { return 0 }

    let ciImage = CIImage(cgImage: downscaled)

    guard let grayscale = CIFilter(name: "CIColorControls") else { return 0 }
    grayscale.setValue(ciImage, forKey: kCIInputImageKey)
    grayscale.setValue(0.0, forKey: kCIInputSaturationKey)

    guard let grayImage = grayscale.outputImage,
          let laplacian = CIFilter(name: "CIConvolution3X3") else { return 0 }

    laplacian.setValue(grayImage, forKey: kCIInputImageKey)
    laplacian.setValue(CIVector(values: [0, 1, 0,
                                         1, -4, 1,
                                         0, 1, 0], count: 9),
                       forKey: kCIInputWeightsKey)
    laplacian.setValue(0.0, forKey: kCIInputBiasKey)

    guard let output = laplacian.outputImage else { return 0 }

    let extent = output.extent
    var bitmap = [UInt8](repeating: 0,
                         count: Int(extent.width * extent.height * 4))

    context.render(
      output,
      toBitmap: &bitmap,
      rowBytes: Int(extent.width * 4),
      bounds: extent,
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )

    let pixels = stride(from: 0, to: bitmap.count, by: 4).map { Double(bitmap[$0]) }
    guard !pixels.isEmpty else { return 0 }

    let mean = pixels.reduce(0, +) / Double(pixels.count)
    let variance = pixels
      .map { ($0 - mean) * ($0 - mean) }
      .reduce(0, +) / Double(pixels.count)

    // Typical sharp scenes: 1500-3000, blurry: 50-200.
    return min(1.0, variance / 1500.0)
  }

  private static func downscale(cgImage: CGImage, to size: CGSize) -> CGImage? {
    let ctx = CGContext(
      data: nil,
      width: Int(size.width),
      height: Int(size.height),
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    ctx?.interpolationQuality = .low
    ctx?.draw(cgImage, in: CGRect(origin: .zero, size: size))
    return ctx?.makeImage()
  }
}

// =============================================================================
// MARK: - Image Processor (perspective + enhancement)
// =============================================================================

enum ImageProcessor {
  private static let context = CIContext(options: [
    .useSoftwareRenderer: false,
    .cacheIntermediates: false
  ])

  /// Applies CIPerspectiveCorrection using a Vision-style 4-point quad
  /// in normalised image coordinates (origin bottom-left, like Vision).
  static func correctPerspective(image: UIImage, quad: [CGPoint]) -> UIImage? {
    guard quad.count == 4, let ciImage = CIImage(image: image) else { return nil }

    let size = ciImage.extent.size
    func denormalize(_ p: CGPoint) -> CGPoint {
      CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    let topLeft = denormalize(quad[0])
    let topRight = denormalize(quad[1])
    let bottomRight = denormalize(quad[2])
    let bottomLeft = denormalize(quad[3])

    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
    filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

    guard let output = filter.outputImage,
          let cgImage = context.createCGImage(output, from: output.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }

  static func applyEnhancement(_ mode: EnhancementMode, to image: UIImage) -> UIImage? {
    guard let ciImage = CIImage(image: image) else { return nil }

    let output: CIImage
    switch mode {
    case .original:
      output = ciImage

    case .colorDocument:
      output = ciImage
        .applyingFilter("CIColorControls", parameters: [
          kCIInputContrastKey: 1.15,
          kCIInputSaturationKey: 1.1,
          kCIInputBrightnessKey: 0.05
        ])
        .applyingFilter("CIUnsharpMask", parameters: [
          kCIInputRadiusKey: 2.5,
          kCIInputIntensityKey: 0.5
        ])

    case .grayscale:
      output = ciImage
        .applyingFilter("CIPhotoEffectMono")
        .applyingFilter("CIColorControls", parameters: [
          kCIInputContrastKey: 1.2,
          kCIInputBrightnessKey: 0.05
        ])

    case .blackAndWhite:
      output = ciImage
        .applyingFilter("CIPhotoEffectMono")
        .applyingFilter("CIColorControls", parameters: [
          kCIInputContrastKey: 2.5,
          kCIInputBrightnessKey: 0.2
        ])
        .applyingFilter("CIColorThreshold", parameters: [
          "inputThreshold": 0.55
        ])

    case .magicColor:
      output = ciImage
        .applyingFilter("CIHighlightShadowAdjust", parameters: [
          "inputHighlightAmount": 0.7,
          "inputShadowAmount": 0.5
        ])
        .applyingFilter("CIColorControls", parameters: [
          kCIInputContrastKey: 1.25,
          kCIInputSaturationKey: 1.2,
          kCIInputBrightnessKey: 0.08
        ])
        .applyingFilter("CIUnsharpMask", parameters: [
          kCIInputRadiusKey: 3.0,
          kCIInputIntensityKey: 0.7
        ])
        .applyingFilter("CIVibrance", parameters: [
          "inputAmount": 0.3
        ])
    }

    guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
    return UIImage(cgImage: cg)
  }
}

extension ImageProcessor {
  /// Card mode helper — composites a front and a back side onto a single
  /// landscape canvas with a small gap. Both inputs are normalised to a
  /// target height (~CR80 proportion) before drawing.
  static func combineCardSides(front: UIImage, back: UIImage) -> UIImage? {
    let targetHeight: CGFloat = 800
    guard let fScaled = scaleImage(front, toHeight: targetHeight),
          let bScaled = scaleImage(back, toHeight: targetHeight) else {
      return nil
    }

    let gap: CGFloat = 40
    let totalWidth = fScaled.size.width + bScaled.size.width + gap
    let canvasSize = CGSize(width: totalWidth, height: targetHeight)

    UIGraphicsBeginImageContextWithOptions(canvasSize, true, 0)
    defer { UIGraphicsEndImageContext() }

    UIColor.white.setFill()
    UIRectFill(CGRect(origin: .zero, size: canvasSize))

    fScaled.draw(in: CGRect(x: 0, y: 0,
                            width: fScaled.size.width,
                            height: targetHeight))
    bScaled.draw(in: CGRect(x: fScaled.size.width + gap, y: 0,
                            width: bScaled.size.width,
                            height: targetHeight))

    return UIGraphicsGetImageFromCurrentImageContext()
  }

  private static func scaleImage(_ image: UIImage, toHeight height: CGFloat) -> UIImage? {
    let ratio = height / image.size.height
    let newWidth = image.size.width * ratio
    let newSize = CGSize(width: newWidth, height: height)
    UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
    defer { UIGraphicsEndImageContext() }
    image.draw(in: CGRect(origin: .zero, size: newSize))
    return UIGraphicsGetImageFromCurrentImageContext()
  }
}

// =============================================================================
// MARK: - OCR Processor
// =============================================================================

/// Wraps `VNRecognizeTextRequest`. Two entry points: `recognizeText`
/// returns the joined text body (for receipt parsing / search index),
/// `detectTextRegions` returns each observation's bounding box (for
/// targeted redaction).
enum OCRProcessor {
  /// Accurate level, language correction on, supports the languages
  /// PDFPrivio's other OCR paths support. Runs ~1-2s per image on
  /// iPhone 17 Pro Max — acceptable for post-capture, not realtime.
  static func recognizeText(in image: UIImage) async -> String {
    guard let cgImage = image.cgImage else { return "" }
    return await withCheckedContinuation { continuation in
      let request = VNRecognizeTextRequest { request, _ in
        guard let observations =
                request.results as? [VNRecognizedTextObservation] else {
          continuation.resume(returning: "")
          return
        }
        let text = observations
          .compactMap { $0.topCandidates(1).first?.string }
          .joined(separator: "\n")
        continuation.resume(returning: text)
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = [
        "en-US", "tr-TR", "es-ES", "de-DE", "fr-FR"
      ]
      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
      try? handler.perform([request])
    }
  }

  /// For ID redaction: returns each observed text + its normalised
  /// bounding box (Vision-style, origin bottom-left, 0..1 each axis).
  /// Language correction is OFF so digit-heavy numbers (SSNs, card
  /// numbers, license #) come through unaltered.
  static func detectTextRegions(in image: UIImage) async
    -> [(text: String, bounds: CGRect)] {
    guard let cgImage = image.cgImage else { return [] }
    return await withCheckedContinuation { continuation in
      let request = VNRecognizeTextRequest { request, _ in
        guard let observations =
                request.results as? [VNRecognizedTextObservation] else {
          continuation.resume(returning: [])
          return
        }
        let regions = observations.compactMap {
          obs -> (String, CGRect)? in
          guard let candidate = obs.topCandidates(1).first else { return nil }
          return (candidate.string, obs.boundingBox)
        }
        continuation.resume(returning: regions)
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = false
      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
      try? handler.perform([request])
    }
  }
}

// =============================================================================
// MARK: - Receipt Parser
// =============================================================================

/// Heuristic extraction of merchant / total / date / currency from a
/// receipt's OCR output. Designed for thermal-printer fast food / café
/// receipts in the en/tr/eu/uk patterns we see most. Output feeds the
/// Expense Ledger pre-fill flow.
enum ReceiptParser {
  static func parse(_ text: String) -> ScanMetadata {
    var meta = ScanMetadata()
    meta.extractedDate = extractDate(from: text)
    if let amountResult = extractAmount(from: text) {
      meta.extractedAmount = amountResult.amount
      meta.extractedCurrency = amountResult.currency
    }
    meta.extractedMerchant = extractMerchant(from: text)
    meta.ocrText = text
    return meta
  }

  private static func extractDate(from text: String) -> Date? {
    guard let detector = try? NSDataDetector(
      types: NSTextCheckingResult.CheckingType.date.rawValue
    ) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    let matches = detector.matches(in: text, options: [], range: range)
    // Take the last date found — receipts typically print the total /
    // settlement date near the footer, not in the header banner.
    return matches.compactMap { $0.date }.last
  }

  /// Tries currency-prefixed and currency-suffixed patterns in five
  /// languages. Returns the first hit. The list is intentionally
  /// short — a more robust pipeline would learn per-merchant formats.
  private static func extractAmount(from text: String)
    -> (amount: Double, currency: String)? {
    let patterns: [(currency: String, regex: String)] = [
      ("USD", #"(?:total|amount|due|grand total)\s*:?\s*\$?\s*(\d+[\.,]\d{2})"#),
      ("EUR", #"(?:total|gesamt|montant)\s*:?\s*€?\s*(\d+[\.,]\d{2})\s*€?"#),
      ("GBP", #"(?:total|amount due)\s*:?\s*£\s*(\d+[\.,]\d{2})"#),
      ("TRY", #"(?:toplam|tutar|genel toplam)\s*:?\s*₺?\s*(\d+[\.,]\d{2})\s*₺?"#),
      ("USD", #"\$\s*(\d+\.\d{2})\s*$"#),
      ("EUR", #"(\d+[\.,]\d{2})\s*€\s*$"#),
      ("TRY", #"(\d+[\.,]\d{2})\s*(?:TL|₺)\s*$"#),
    ]

    let lowered = text.lowercased()
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(
        pattern: pattern.regex,
        options: [.caseInsensitive, .anchorsMatchLines]
      ) else { continue }
      let range = NSRange(lowered.startIndex..., in: lowered)
      guard let match = regex.firstMatch(in: lowered, options: [], range: range),
            match.numberOfRanges >= 2 else { continue }
      let amountRange = match.range(at: 1)
      guard let r = Range(amountRange, in: lowered) else { continue }
      let raw = String(lowered[r]).replacingOccurrences(of: ",", with: ".")
      if let amount = Double(raw) {
        return (amount, pattern.currency)
      }
    }
    return nil
  }

  /// Heuristic: most receipts print the merchant name as an
  /// ALL-CAPS line near the top, before the address / item lines.
  /// Falls back to the first non-empty line if the heuristic misses.
  private static func extractMerchant(from text: String) -> String? {
    let lines = text.split(separator: "\n").prefix(5)
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.count >= 3 && trimmed.count <= 40 else { continue }
      let uppercaseCount = trimmed.filter { $0.isUppercase }.count
      let digitCount = trimmed.filter { $0.isNumber }.count
      if uppercaseCount > trimmed.count / 2 &&
         digitCount < trimmed.count / 3 {
        return trimmed
      }
    }
    return lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
  }
}

// =============================================================================
// MARK: - ID Redactor
// =============================================================================

/// Scans for sensitive patterns (SSN, card number, DOB, license #) in
/// OCR observations and overlays black rectangles before the PDF is
/// written. Operates on Vision-style normalised bounding boxes.
enum IDRedactor {
  enum RedactField: String, CaseIterable {
    case ssn = "ssn"
    case cardNumber = "card"
    case dateOfBirth = "dob"
    case licenseNumber = "license"

    var displayName: String {
      switch self {
      case .ssn: return "Social Security Number"
      case .cardNumber: return "Card Number"
      case .dateOfBirth: return "Date of Birth"
      case .licenseNumber: return "License Number"
      }
    }

    var pattern: String {
      switch self {
      case .ssn:
        return #"\b\d{3}[-\s]?\d{2}[-\s]?\d{4}\b"#
      case .cardNumber:
        return #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#
      case .dateOfBirth:
        return #"\b(?:0?[1-9]|1[0-2])[/.-](?:0?[1-9]|[12]\d|3[01])[/.-](?:19|20)\d{2}\b"#
      case .licenseNumber:
        return #"\b[A-Z]\d{7,8}\b"#
      }
    }
  }

  /// Scans OCR regions for each redact pattern. Returns one entry per
  /// region that matched (a single region only contributes once even
  /// if multiple patterns overlap).
  static func findSensitiveRegions(
    in regions: [(text: String, bounds: CGRect)]
  ) -> [(field: RedactField, bounds: CGRect)] {
    var found: [(RedactField, CGRect)] = []
    for region in regions {
      for field in RedactField.allCases {
        guard let regex = try? NSRegularExpression(
          pattern: field.pattern, options: [.caseInsensitive]
        ) else { continue }
        let range = NSRange(region.text.startIndex..., in: region.text)
        if regex.firstMatch(in: region.text, options: [], range: range) != nil {
          found.append((field, region.bounds))
          break
        }
      }
    }
    return found
  }

  /// Draws solid-black rectangles over the regions on a fresh copy of
  /// the image. Vision boxes are normalised + bottom-left; UIKit is
  /// pixel + top-left, so we flip Y before fill. A small inset is
  /// added because text bounding boxes hug too tight to look opaque.
  static func redact(
    image: UIImage,
    regions: [(field: RedactField, bounds: CGRect)]
  ) -> UIImage {
    let size = image.size
    UIGraphicsBeginImageContextWithOptions(size, true, image.scale)
    defer { UIGraphicsEndImageContext() }
    image.draw(in: CGRect(origin: .zero, size: size))
    guard let context = UIGraphicsGetCurrentContext() else { return image }
    context.setFillColor(UIColor.black.cgColor)

    for region in regions {
      let bounds = region.bounds
      let rect = CGRect(
        x: bounds.minX * size.width,
        y: (1 - bounds.maxY) * size.height,
        width: bounds.width * size.width,
        height: bounds.height * size.height
      )
      let padded = rect.insetBy(dx: -4, dy: -2)
      context.fill(padded)
    }
    return UIGraphicsGetImageFromCurrentImageContext() ?? image
  }
}

// =============================================================================
// MARK: - PDF Assembler
// =============================================================================

enum PDFAssembler {
  /// Mode-aware top-level entry. Per-mode page geometry:
  ///   * doc:     each page laid out on A4 portrait with a 24pt margin
  ///   * receipt: tight custom page; multi-page receipts stitch
  ///              vertically so they look like one printout
  ///   * card:    front + back composited side-by-side on a landscape
  ///              CR80-ratio page
  ///   * id:      A4 portrait, same as doc (redaction already baked
  ///              into the enhancedImage)
  static func assemble(pages: [ScannedPage], mode: ScanMode) -> Data? {
    guard !pages.isEmpty else { return nil }
    let pdf = PDFDocument()

    switch mode {
    case .doc, .id:
      for (idx, page) in pages.enumerated() {
        if let pdfPage = makeA4Page(image: page.enhancedImage) {
          pdf.insert(pdfPage, at: idx)
        }
      }

    case .receipt:
      if pages.count == 1,
         let pdfPage = makeReceiptPage(image: pages[0].enhancedImage) {
        pdf.insert(pdfPage, at: 0)
      } else if let stitched =
                  combineImagesVertically(pages.map { $0.enhancedImage }),
                let pdfPage = makeReceiptPage(image: stitched) {
        pdf.insert(pdfPage, at: 0)
      }

    case .card:
      if pages.count >= 2,
         let combined = ImageProcessor.combineCardSides(
           front: pages[0].enhancedImage,
           back: pages[1].enhancedImage
         ),
         let pdfPage = makeCR80LandscapePage(image: combined) {
        pdf.insert(pdfPage, at: 0)
      } else if let only = pages.first,
                let pdfPage = makeCR80LandscapePage(image: only.enhancedImage) {
        pdf.insert(pdfPage, at: 0)
      }
    }

    return pdf.dataRepresentation()
  }

  /// Legacy entry — writes one PDF page per enhancedImage with no
  /// custom layout. Kept because the VisionKit fallback path didn't
  /// know about ScanMode; both VisionKit and the custom path now
  /// route through `assemble(pages:mode:)`.
  static func writePDF(pages: [ScannedPage], to destination: URL) -> Bool {
    let pdf = PDFDocument()
    for (idx, page) in pages.enumerated() {
      guard let pdfPage = PDFPage(image: page.enhancedImage) else { continue }
      pdf.insert(pdfPage, at: idx)
    }
    return pdf.write(to: destination)
  }

  static func writePDF(images: [UIImage], to destination: URL) -> Bool {
    let pdf = PDFDocument()
    for (idx, image) in images.enumerated() {
      guard let pdfPage = PDFPage(image: image) else { continue }
      pdf.insert(pdfPage, at: idx)
    }
    return pdf.write(to: destination)
  }

  /// A4 portrait at 72 DPI: 595 × 842 points. Image is aspect-fit
  /// inside a 24pt-margin content rect on a white background.
  private static func makeA4Page(image: UIImage) -> PDFPage? {
    let a4Size = CGSize(width: 595, height: 842)
    let renderer = UIGraphicsImageRenderer(size: a4Size)
    let pageImage = renderer.image { _ in
      UIColor.white.setFill()
      UIRectFill(CGRect(origin: .zero, size: a4Size))
      let margin: CGFloat = 24
      let contentRect = CGRect(
        x: margin, y: margin,
        width: a4Size.width - margin * 2,
        height: a4Size.height - margin * 2
      )
      image.draw(in: aspectFitRect(image: image, in: contentRect))
    }
    return PDFPage(image: pageImage)
  }

  /// Receipt page width is fixed at ~280pt; the page height grows
  /// with the image aspect so a long stitched receipt becomes one
  /// long PDF page instead of being chopped into A4-sized slices.
  private static func makeReceiptPage(image: UIImage) -> PDFPage? {
    let contentWidth: CGFloat = 280
    let aspect = image.size.height / image.size.width
    let pageSize = CGSize(
      width: contentWidth + 40,
      height: contentWidth * aspect + 40
    )
    let renderer = UIGraphicsImageRenderer(size: pageSize)
    let pageImage = renderer.image { _ in
      UIColor.white.setFill()
      UIRectFill(CGRect(origin: .zero, size: pageSize))
      image.draw(in: CGRect(
        x: 20, y: 20,
        width: contentWidth,
        height: contentWidth * aspect
      ))
    }
    return PDFPage(image: pageImage)
  }

  /// CR80 landscape — A4-landscape-ish (595 × 420) so the combined
  /// front+back card image lands at a credit-card aspect ratio with
  /// generous margins.
  private static func makeCR80LandscapePage(image: UIImage) -> PDFPage? {
    let pageSize = CGSize(width: 595, height: 420)
    let renderer = UIGraphicsImageRenderer(size: pageSize)
    let pageImage = renderer.image { _ in
      UIColor.white.setFill()
      UIRectFill(CGRect(origin: .zero, size: pageSize))
      let margin: CGFloat = 30
      let contentRect = CGRect(
        x: margin, y: margin,
        width: pageSize.width - margin * 2,
        height: pageSize.height - margin * 2
      )
      image.draw(in: aspectFitRect(image: image, in: contentRect))
    }
    return PDFPage(image: pageImage)
  }

  /// Aspect-fit math shared between A4 + CR80 helpers.
  private static func aspectFitRect(
    image: UIImage, in contentRect: CGRect
  ) -> CGRect {
    let imageAspect = image.size.width / image.size.height
    let contentAspect = contentRect.width / contentRect.height
    if imageAspect > contentAspect {
      let h = contentRect.width / imageAspect
      return CGRect(
        x: contentRect.minX,
        y: contentRect.midY - h / 2,
        width: contentRect.width,
        height: h
      )
    } else {
      let w = contentRect.height * imageAspect
      return CGRect(
        x: contentRect.midX - w / 2,
        y: contentRect.minY,
        width: w,
        height: contentRect.height
      )
    }
  }

  private static func combineImagesVertically(_ images: [UIImage])
    -> UIImage? {
    guard !images.isEmpty else { return nil }
    let targetWidth = images.map { $0.size.width }.max() ?? 0
    let totalHeight = images.reduce(0) {
      $0 + ($1.size.height * (targetWidth / $1.size.width))
    }
    let canvasSize = CGSize(width: targetWidth, height: totalHeight)
    UIGraphicsBeginImageContextWithOptions(canvasSize, true, 0)
    defer { UIGraphicsEndImageContext() }
    UIColor.white.setFill()
    UIRectFill(CGRect(origin: .zero, size: canvasSize))
    var yOffset: CGFloat = 0
    for image in images {
      let scaledHeight = image.size.height * (targetWidth / image.size.width)
      image.draw(in: CGRect(
        x: 0, y: yOffset,
        width: targetWidth,
        height: scaledHeight
      ))
      yOffset += scaledHeight
    }
    return UIGraphicsGetImageFromCurrentImageContext()
  }

  /// Writes [data] to a tmp file and returns its path. Used by the
  /// bridge to hand a fresh PDF off to Flutter.
  static func writeToTemp(data: Data, fileName: String? = nil) throws -> String {
    let tempDir = FileManager.default.temporaryDirectory
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let name = fileName ?? "pdfprivio_scan_\(timestamp).pdf"
    let url = tempDir.appendingPathComponent(name)
    try data.write(to: url)
    return url.path
  }

  static func makeTemporaryDestination() -> URL {
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    return FileManager.default.temporaryDirectory
      .appendingPathComponent("pdfprivio_scan_\(stamp).pdf")
  }
}

// =============================================================================
// MARK: - Scanner Coordinator
// =============================================================================

@MainActor
final class ScannerCoordinator: NSObject, ObservableObject {
  @Published var guidance: ScannerGuidance = .searching
  @Published var detectedQuad: [CGPoint] = []
  @Published var capturedPages: [ScannedPage] = []
  @Published var isAutoCapture: Bool = true
  @Published var captureCountdown: Int? = nil
  @Published var blurWarningPage: ScannedPage? = nil

  /// Active capture mode. Drives the Vision rectangle detector tuning,
  /// the default enhancement applied per capture, and the card flip
  /// state machine. Writing to this resets transient detection state
  /// so the new mode's geometry takes effect immediately.
  @Published var currentMode: ScanMode = .doc

  /// Card mode only — once the front side is captured we stash it
  /// here and switch guidance to .flipCard. The next successful
  /// capture pairs with it and ends the session (preview).
  @Published var capturedFrontSide: ScannedPage?

  /// Set to true after the second card side is captured so the host
  /// view can transition to the preview screen automatically.
  @Published var shouldShowPreview: Bool = false

  let captureSession = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private let videoOutput = AVCaptureVideoDataOutput()

  private var lastStableDetection: Date?
  private var rectangleHistory: [VNRectangleObservation] = []
  private var frameCount = 0

  private let stabilityThreshold: TimeInterval = 0.6
  private let autoCaptureDelay: TimeInterval = 1.0

  private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
  private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
  private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

  private var lastGuidance: ScannerGuidance = .searching

  override init() {
    super.init()
    lightHaptic.prepare()
    mediumHaptic.prepare()
    heavyHaptic.prepare()
  }

  /// Switch capture flavor. Resets transient detection state so the
  /// new mode's rectangle tuning applies on the next frame and so the
  /// user doesn't see a half-confirmed bracket from the previous mode.
  func setMode(_ mode: ScanMode) {
    guard mode != currentMode else { return }
    currentMode = mode
    capturedFrontSide = nil
    rectangleHistory.removeAll()
    lastStableDetection = nil
    captureCountdown = nil
    guidance = .searching
  }

  func setupCamera() async throws {
    guard await checkCameraPermission() else {
      throw NSError(domain: "Scanner", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Camera permission denied"])
    }

    captureSession.beginConfiguration()
    captureSession.sessionPreset = .photo

    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                               for: .video,
                                               position: .back),
          let input = try? AVCaptureDeviceInput(device: device) else {
      captureSession.commitConfiguration()
      throw NSError(domain: "Scanner", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No back camera"])
    }

    if captureSession.canAddInput(input) {
      captureSession.addInput(input)
    }

    try? device.lockForConfiguration()
    if device.isFocusModeSupported(.continuousAutoFocus) {
      device.focusMode = .continuousAutoFocus
    }
    if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    }
    device.unlockForConfiguration()

    if captureSession.canAddOutput(photoOutput) {
      captureSession.addOutput(photoOutput)
      photoOutput.isHighResolutionCaptureEnabled = true
    }

    let videoQueue = DispatchQueue(label: "scanner.video.queue",
                                   qos: .userInitiated)
    videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_32BGRA
    ]

    if captureSession.canAddOutput(videoOutput) {
      captureSession.addOutput(videoOutput)
    }

    captureSession.commitConfiguration()
  }

  private func checkCameraPermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video)
    default: return false
    }
  }

  func startSession() {
    let session = captureSession
    Task.detached(priority: .userInitiated) {
      session.startRunning()
    }
  }

  func stopSession() {
    captureSession.stopRunning()
  }

  func capturePhoto() {
    triggerCapture()
  }

  private func triggerCapture() {
    heavyHaptic.impactOccurred()
    guidance = .capturing

    let settings = AVCapturePhotoSettings()
    settings.isHighResolutionPhotoEnabled = true
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  private func processCapturedImage(_ image: UIImage) async {
    let blurScore = await Task.detached(priority: .userInitiated) {
      BlurDetector.calculateSharpness(of: image)
    }.value

    let quad = detectedQuad
    let corrected = ImageProcessor.correctPerspective(image: image, quad: quad) ?? image
    let mode = currentMode
    let defaultMode = mode.defaultEnhancement
    let enhanced =
      ImageProcessor.applyEnhancement(defaultMode, to: corrected) ?? corrected

    var page = ScannedPage(
      originalImage: image,
      correctedImage: corrected,
      enhancedImage: enhanced,
      quad: quad,
      enhancementMode: defaultMode,
      blurScore: blurScore
    )

    // Blur warning disabled — it was firing on captures that looked
    // perfectly fine to the human eye (parlak ID surfaces, indoor
    // light, small subjects all push the Laplacian score down even
    // without motion blur). The blur score is still surfaced in the
    // review screen so the user can retake if they genuinely don't
    // like a page.
    _ = page.needsRetake(forMode: mode)

    // Card mode flip flow: the first capture is the front side, then
    // we prompt the user to flip and the next capture is the back —
    // both get stitched in the preview / PDF assembler.
    if mode == .card {
      if capturedFrontSide == nil {
        page.side = .front
        capturedFrontSide = page
        guidance = .flipCard
        rectangleHistory.removeAll()
        lastStableDetection = nil
        captureCountdown = nil
        // Hold the flip banner up briefly, then re-arm detection.
        Task { [weak self] in
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          await MainActor.run {
            guard let self = self,
                  self.currentMode == .card,
                  self.capturedFrontSide != nil else { return }
            self.guidance = .searching
          }
        }
        return
      } else {
        page.side = .back
        capturedPages.append(capturedFrontSide!)
        capturedPages.append(page)
        capturedFrontSide = nil
        // Card flow is single-shot: roll to the preview automatically.
        shouldShowPreview = true
        resetState()
        return
      }
    }

    capturedPages.append(page)
    resetState()
  }

  private func resetState() {
    rectangleHistory.removeAll()
    lastStableDetection = nil
    captureCountdown = nil
    guidance = .searching
  }

  // MARK: Vision frame analysis

  fileprivate func processFrame(pixelBuffer: CVPixelBuffer) {
    // Pull rectangle detection tuning from the active mode — receipt
    // (tall narrow), card (1.6:1 landscape), id (passport portrait),
    // doc (loose default). Without this, the detector would stay on
    // doc-tuned thresholds and reject narrow receipts entirely.
    let config = currentMode.rectangleDetectionConfig

    let request = VNDetectRectanglesRequest { [weak self] request, _ in
      guard let self = self else { return }
      let observations = request.results as? [VNRectangleObservation] ?? []
      Task { @MainActor in
        self.handleObservations(observations)
      }
    }

    request.minimumAspectRatio = config.aspectMin
    request.maximumAspectRatio = config.aspectMax
    request.minimumSize = config.sizeMin
    request.maximumObservations = 1
    request.minimumConfidence = 0.75
    request.quadratureTolerance = config.quadTolerance

    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                        orientation: .right,
                                        options: [:])
    try? handler.perform([request])
  }

  @MainActor
  private func handleObservations(_ observations: [VNRectangleObservation]) {
    // Once the auto-capture countdown is armed, freeze the state
    // machine. Without this, a single jittery frame mid-countdown
    // (which is ~50 frames at 30fps) bumps guidance back to
    // .holdSteady and the trigger Task's `case .readyToCapture =
    // guidance` guard then cancels the capture. Net effect for the
    // user: "Capturing in 1s" shows up and nothing actually fires.
    if captureCountdown != nil {
      // Still update the visible quad so brackets follow the doc
      // smoothly, but don't touch guidance / stability / history.
      if let rect = observations.first {
        detectedQuad = [
          rect.topLeft, rect.topRight,
          rect.bottomRight, rect.bottomLeft,
        ]
      }
      return
    }

    guard let rect = observations.first else {
      handleNoDetection()
      return
    }

    detectedQuad = [
      rect.topLeft, rect.topRight,
      rect.bottomRight, rect.bottomLeft
    ]

    // `boundingBox` returns Vision's axis-aligned bbox of the quad in
    // normalised image coordinates. Using it instead of the raw
    // top-edge × left-edge multiply means a slightly tilted card still
    // gets its real area counted instead of an artificially squashed
    // one (the old formula assumed topRight.y == topLeft.y).
    let bbox = rect.boundingBox
    let area = bbox.width * bbox.height

    // Each mode wants a different "close enough / too close" band:
    //   * card / id: tight subjects, often only fill ~12-40% of the
    //     frame because users naturally hold them at a comfortable
    //     reading distance — push the lower bound down hard.
    //   * receipt: a thermal receipt is tall + narrow, so even when
    //     it fills the frame it usually only covers ~25-50%.
    //   * doc: full-page documents need to fill most of the frame.
    let mode = currentMode
    let minArea: CGFloat
    let maxArea: CGFloat
    switch mode {
    case .doc:
      minArea = 0.25
      maxArea = 0.92
    case .receipt:
      minArea = 0.12
      maxArea = 0.88
    case .card:
      minArea = 0.08
      maxArea = 0.80
    case .id:
      minArea = 0.15
      maxArea = 0.88
    }

    if area < minArea {
      updateGuidance(.moveCloser)
      resetStability()
      return
    }

    if area > maxArea {
      updateGuidance(.moveFurther)
      resetStability()
      return
    }

    rectangleHistory.append(rect)
    if rectangleHistory.count > 10 {
      rectangleHistory.removeFirst()
    }

    let isStable = checkStability()

    if !isStable {
      updateGuidance(.holdSteady)
      resetStability()
      return
    }

    if lastStableDetection == nil {
      lastStableDetection = Date()
      updateGuidance(.detected(quality: CGFloat(rect.confidence)))
      return
    }

    let stableDuration = Date().timeIntervalSince(lastStableDetection!)

    // Card / ID don't need a full 0.6s lock — the subject is small,
    // users naturally hold it more steady than a full doc, and the
    // longer wait reads as "the scanner isn't responding".
    let requiredHold: TimeInterval
    switch currentMode {
    case .doc, .receipt: requiredHold = stabilityThreshold
    case .card, .id: requiredHold = 0.4
    }
    if stableDuration >= requiredHold && isAutoCapture {
      updateGuidance(.readyToCapture)
      startAutoCaptureCountdown()
    }
  }

  @MainActor
  private func handleNoDetection() {
    detectedQuad = []
    rectangleHistory.removeAll()
    lastStableDetection = nil
    captureCountdown = nil
    updateGuidance(.searching)
  }

  @MainActor
  private func updateGuidance(_ new: ScannerGuidance) {
    if new != lastGuidance {
      if case .detected = new, case .holdSteady = lastGuidance {
        lightHaptic.impactOccurred()
      } else if new == .readyToCapture {
        mediumHaptic.impactOccurred()
      }
      lastGuidance = new
    }
    guidance = new
  }

  private func checkStability() -> Bool {
    guard rectangleHistory.count >= 5 else { return false }
    let recent = Array(rectangleHistory.suffix(5))
    let xVariance = variance(recent.map { $0.topLeft.x })
    let yVariance = variance(recent.map { $0.topLeft.y })
    // The 0.003 threshold worked for full-page documents (the small
    // subject moves less in normalised image space) but failed on
    // hand-held cards and IDs where micro-jitter pushes variance over
    // the line repeatedly, so the user sees "Detected ↔ Hold steady"
    // bouncing forever. Loosen for the close-subject modes.
    let threshold: CGFloat
    switch currentMode {
    case .doc: threshold = 0.003
    case .receipt: threshold = 0.006
    case .card, .id: threshold = 0.012
    }
    return xVariance < threshold && yVariance < threshold
  }

  private func variance(_ values: [CGFloat]) -> CGFloat {
    guard !values.isEmpty else { return 0 }
    let mean = values.reduce(0, +) / CGFloat(values.count)
    let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
    return squaredDiffs.reduce(0, +) / CGFloat(values.count)
  }

  private func resetStability() {
    lastStableDetection = nil
    captureCountdown = nil
  }

  private func startAutoCaptureCountdown() {
    guard captureCountdown == nil else { return }
    captureCountdown = 1

    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      await MainActor.run {
        guard let self = self else { return }
        // No more `case .readyToCapture = guidance` guard — once we
        // armed the countdown and the user didn't dismiss the
        // scanner, we want the photo fired even if a stray frame
        // briefly bumped guidance somewhere else. handleObservations
        // also freezes state while `captureCountdown != nil`, so by
        // the time we're here the guidance should still be ready —
        // but treat the guard as defensive, not gating.
        self.captureCountdown = nil
        self.triggerCapture()
      }
    }
  }
}

extension ScannerCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
  nonisolated func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      self.frameCount += 1
      // Throttle Vision requests to every 3rd frame.
      guard self.frameCount % 3 == 0 else { return }
      self.processFrame(pixelBuffer: pixelBuffer)
    }
  }
}

extension ScannerCoordinator: AVCapturePhotoCaptureDelegate {
  nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                               didFinishProcessingPhoto photo: AVCapturePhoto,
                               error: Error?) {
    guard let data = photo.fileDataRepresentation(),
          let image = UIImage(data: data) else { return }
    Task { @MainActor [weak self] in
      await self?.processCapturedImage(image)
    }
  }
}

// =============================================================================
// MARK: - Scanner UI (capture)
// =============================================================================

struct ScannerView: View {
  @ObservedObject var coordinator: ScannerCoordinator
  let onClose: () -> Void
  let onShowPreview: () -> Void

  var body: some View {
    ZStack {
      CameraPreviewLayer(session: coordinator.captureSession)
        .ignoresSafeArea()

      EdgeBracketOverlay(
        quad: coordinator.detectedQuad,
        isReady: coordinator.guidance.isReady
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      VStack {
        ScannerTopBar(onClose: onClose)

        GuidancePill(
          guidance: coordinator.guidance,
          countdown: coordinator.captureCountdown
        )
        .padding(.top, 8)

        ModeBanner(
          mode: coordinator.currentMode,
          hasCapturedFront: coordinator.capturedFrontSide != nil
        )
        .padding(.top, 6)

        Spacer()

        ScannerBottomBar(
          mode: coordinator.currentMode,
          onModeChange: { coordinator.setMode($0) },
          capturedCount: coordinator.capturedPages.count,
          isAutoCapture: $coordinator.isAutoCapture,
          onCapture: { coordinator.capturePhoto() },
          onShowPreview: onShowPreview
        )
      }
    }
    .preferredColorScheme(.dark)
    .task {
      do {
        try await coordinator.setupCamera()
        coordinator.startSession()
      } catch {
        // Camera permission denied or no rear camera. UI will sit on
        // a black preview — user can tap X to back out.
        print("Scanner camera setup error: \(error)")
      }
    }
    .onDisappear {
      coordinator.stopSession()
    }
    .alert("Photo too blurry",
           isPresented: Binding(
            get: { coordinator.blurWarningPage != nil },
            set: { if !$0 { coordinator.blurWarningPage = nil } }
           )) {
      Button("Retake", role: .cancel) {
        coordinator.blurWarningPage = nil
      }
      Button("Use anyway") {
        if let page = coordinator.blurWarningPage {
          coordinator.capturedPages.append(page)
          coordinator.blurWarningPage = nil
        }
      }
    } message: {
      Text("This photo looks blurry. Retake for a sharper scan?")
    }
  }
}

private struct ScannerTopBar: View {
  let onClose: () -> Void

  var body: some View {
    HStack {
      iconButton("xmark", action: onClose)
      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.top, 12)
  }

  private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .medium))
        .foregroundColor(.white)
        .frame(width: 40, height: 40)
        .background(Color.black.opacity(0.45))
        .clipShape(Circle())
    }
  }
}

private struct GuidancePill: View {
  let guidance: ScannerGuidance
  let countdown: Int?

  var body: some View {
    HStack(spacing: 8) {
      if let icon = guidance.iconName {
        Image(systemName: icon)
          .font(.system(size: 13, weight: .semibold))
      }
      Text(displayText)
        .font(.system(size: 14, weight: .medium))
    }
    .foregroundColor(.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(backgroundColor)
    .clipShape(Capsule())
    .animation(.easeInOut(duration: 0.25), value: guidance)
  }

  private var displayText: String {
    if guidance == .readyToCapture, let countdown = countdown {
      return "Capturing in \(countdown)s"
    }
    return guidance.userMessage
  }

  private var backgroundColor: Color {
    switch guidance {
    case .searching:
      return Color.black.opacity(0.6)
    case .moveCloser, .moveFurther, .improveLight, .holdSteady:
      return Color.orange.opacity(0.92)
    case .detected, .readyToCapture, .capturing:
      return Color.brandTeal.opacity(0.95)
    case .flipCard:
      return Color.brandTealLight.opacity(0.95)
    }
  }
}

private struct EdgeBracketOverlay: View {
  let quad: [CGPoint]
  let isReady: Bool

  var body: some View {
    GeometryReader { geo in
      if quad.count == 4 {
        let mapped = quad.map { p in
          CGPoint(x: p.x * geo.size.width,
                  y: (1 - p.y) * geo.size.height)
        }

        ZStack {
          Path { path in
            path.move(to: mapped[0])
            path.addLine(to: mapped[1])
            path.addLine(to: mapped[2])
            path.addLine(to: mapped[3])
            path.closeSubpath()
          }
          .stroke(bracketColor, lineWidth: 2)

          ForEach(0..<4, id: \.self) { idx in
            CornerBracket(
              position: mapped[idx],
              corner: cornerType(idx),
              color: bracketColor
            )
          }
        }
        .animation(.easeOut(duration: 0.15), value: quad)
      }
    }
  }

  private var bracketColor: Color {
    isReady ? Color.brandTealLight : Color.white.opacity(0.7)
  }

  private func cornerType(_ idx: Int) -> CornerBracket.Corner {
    switch idx {
    case 0: return .topLeft
    case 1: return .topRight
    case 2: return .bottomRight
    case 3: return .bottomLeft
    default: return .topLeft
    }
  }
}

private struct CornerBracket: View {
  enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

  let position: CGPoint
  let corner: Corner
  let color: Color

  private let size: CGFloat = 26
  private let thickness: CGFloat = 4

  var body: some View {
    Path { path in
      switch corner {
      case .topLeft:
        path.move(to: CGPoint(x: 0, y: size))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: size, y: 0))
      case .topRight:
        path.move(to: CGPoint(x: -size, y: 0))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: size))
      case .bottomLeft:
        path.move(to: CGPoint(x: 0, y: -size))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: size, y: 0))
      case .bottomRight:
        path.move(to: CGPoint(x: -size, y: 0))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: -size))
      }
    }
    .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
    .position(position)
  }
}

private struct ScannerBottomBar: View {
  let mode: ScanMode
  let onModeChange: (ScanMode) -> Void
  let capturedCount: Int
  @Binding var isAutoCapture: Bool
  let onCapture: () -> Void
  let onShowPreview: () -> Void

  private let modes: [ScanMode] = [.doc, .receipt, .card, .id]

  var body: some View {
    VStack(spacing: 16) {
      HStack(spacing: 6) {
        ForEach(modes, id: \.self) { m in
          Button {
            if m != mode {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              onModeChange(m)
            }
          } label: {
            modeChip(m, isActive: m == mode)
          }
          .buttonStyle(.plain)
        }
      }

      HStack {
        galleryButton
        Spacer()
        shutterButton
        Spacer()
        trailingControl
      }
    }
    .padding(.horizontal, 22)
    .padding(.bottom, 30)
  }

  private var galleryButton: some View {
    Button(action: onShowPreview) {
      ZStack(alignment: .topTrailing) {
        RoundedRectangle(cornerRadius: 10)
          .fill(Color.white.opacity(0.15))
          .frame(width: 48, height: 48)
          .overlay(
            Image(systemName: capturedCount > 0
                  ? "doc.text.fill"
                  : "photo.on.rectangle")
              .font(.system(size: 18))
              .foregroundColor(.white)
          )

        if capturedCount > 0 {
          Circle()
            .fill(Color.brandTealLight)
            .frame(width: 22, height: 22)
            .overlay(
              Text("\(capturedCount)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black)
            )
            .offset(x: 8, y: -8)
        }
      }
    }
    .disabled(capturedCount == 0)
    .opacity(capturedCount == 0 ? 0.5 : 1.0)
  }

  private var shutterButton: some View {
    Button(action: onCapture) {
      ZStack {
        Circle()
          .stroke(Color.white, lineWidth: 5)
          .frame(width: 72, height: 72)

        Circle()
          .fill(Color.white)
          .frame(width: 58, height: 58)
      }
    }
  }

  @ViewBuilder
  private var trailingControl: some View {
    if capturedCount > 0 {
      Button(action: onShowPreview) {
        HStack(spacing: 4) {
          Text("Done")
            .font(.system(size: 15, weight: .semibold))
          Image(systemName: "arrow.right")
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(Color.brandTealLight)
        .frame(width: 64, height: 48)
      }
    } else {
      VStack(spacing: 3) {
        Toggle("", isOn: $isAutoCapture)
          .toggleStyle(SwitchToggleStyle(tint: Color.brandTealLight))
          .labelsHidden()
          .scaleEffect(0.8)
        Text("Auto")
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.white.opacity(0.7))
      }
      .frame(width: 64, height: 48)
    }
  }

  private func modeChip(_ m: ScanMode, isActive: Bool) -> some View {
    VStack(spacing: 3) {
      Image(systemName: m.iconName)
        .font(.system(size: 14, weight: .medium))
      Text(m.shortLabel)
        .font(.system(size: 11, weight: .semibold))
    }
    // 0.75 instead of 0.5 — the old contrast read as "disabled".
    .foregroundColor(isActive ? .white : .white.opacity(0.75))
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(isActive
                ? Color.white.opacity(0.18)
                : Color.white.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    // Make the entire pill (including transparent areas) tap-able.
    .contentShape(RoundedRectangle(cornerRadius: 12))
  }
}

/// Small pill under the guidance prompt that reminds the user which
/// mode is active and — for card mode — which side is being asked for
/// right now.
private struct ModeBanner: View {
  let mode: ScanMode
  let hasCapturedFront: Bool

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: mode.iconName)
        .font(.system(size: 11, weight: .medium))
      Text(displayText)
        .font(.system(size: 11, weight: .semibold))
    }
    .foregroundColor(.white.opacity(0.9))
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .background(Color.black.opacity(0.4))
    .clipShape(Capsule())
  }

  private var displayText: String {
    if mode == .card {
      return hasCapturedFront
        ? "Card · Back side"
        : "Card · Front side"
    }
    return mode.displayName
  }
}

private struct CameraPreviewLayer: UIViewRepresentable {
  let session: AVCaptureSession

  func makeUIView(context: Context) -> PreviewUIView {
    let view = PreviewUIView()
    view.videoPreviewLayer.session = session
    view.videoPreviewLayer.videoGravity = .resizeAspectFill
    return view
  }

  func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

private final class PreviewUIView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var videoPreviewLayer: AVCaptureVideoPreviewLayer {
    layer as! AVCaptureVideoPreviewLayer
  }
}

// =============================================================================
// MARK: - Scanner Preview / review screen
// =============================================================================

struct ScannerPreviewView: View {
  @ObservedObject var coordinator: ScannerCoordinator
  let enableOCR: Bool
  let onBackToScanner: () -> Void
  let onDone: (URL, ScanMetadata?) -> Void

  @State private var isBuilding = false
  @State private var buildError: String?
  @State private var receiptMeta: ScanMetadata?
  @State private var idRegions: [(field: IDRedactor.RedactField, bounds: CGRect)] = []
  @State private var didApplyRedaction: Bool = false
  @State private var didRunModePostProcess: Bool = false
  @State private var selectedPageIndex: Int = 0

  var body: some View {
    NavigationView {
      ZStack {
        Color.brandCream.ignoresSafeArea()

        if coordinator.capturedPages.isEmpty {
          emptyState
        } else {
          VStack(spacing: 0) {
            ScrollView {
              VStack(spacing: 14) {
                if coordinator.currentMode == .receipt, let meta = receiptMeta {
                  receiptBanner(meta)
                }
                if coordinator.currentMode == .id && !idRegions.isEmpty {
                  idBanner
                }
                pageList
              }
              .padding(.vertical, 8)
            }
            Divider().opacity(0.4)
            doneBar
          }
        }

        if isBuilding {
          Color.black.opacity(0.55).ignoresSafeArea()
          ProgressView("Building PDF…")
            .padding(24)
            .background(Color.brandCream)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
      }
      .navigationTitle(navTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button(action: onBackToScanner) {
            Image(systemName: "camera.fill")
              .foregroundColor(.brandTeal)
          }
        }
      }
      .alert("Couldn't build PDF",
             isPresented: Binding(
              get: { buildError != nil },
              set: { if !$0 { buildError = nil } }
             )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(buildError ?? "Try again or retake some pages.")
      }
    }
    .navigationViewStyle(.stack)
    .task(id: coordinator.capturedPages.map { $0.id }) {
      await runModePostProcess()
    }
  }

  private var navTitle: String {
    let mode = coordinator.currentMode
    let count = coordinator.capturedPages.count
    return "Review · \(mode.displayName) · \(count) page\(count == 1 ? "" : "s")"
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "doc.viewfinder")
        .font(.system(size: 44))
        .foregroundColor(.brandTeal.opacity(0.5))
      Text("No pages yet")
        .font(.system(size: 18, weight: .semibold))
      Text("Tap the camera button to start scanning.")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
      Button(action: onBackToScanner) {
        Label("Back to scanner", systemImage: "camera.fill")
          .font(.system(size: 14, weight: .semibold))
      }
      .padding(.top, 8)
    }
  }

  private var pageList: some View {
    List {
      ForEach(Array(coordinator.capturedPages.enumerated()), id: \.element.id) { idx, page in
        HStack(spacing: 14) {
          Image(uiImage: page.enhancedImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 70, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
            )

          VStack(alignment: .leading, spacing: 4) {
            Text(pageTitle(forIndex: idx, page: page))
              .font(.system(size: 15, weight: .semibold))
            Text(qualityLabel(for: page.blurScore))
              .font(.system(size: 12))
              .foregroundColor(page.blurScore < 0.45 ? .orange : .secondary)
          }

          Spacer()

          Menu {
            ForEach(EnhancementMode.allCases, id: \.self) { mode in
              Button {
                applyMode(mode, to: page)
              } label: {
                Label(mode.rawValue, systemImage: mode.iconName)
              }
            }
          } label: {
            Image(systemName: page.enhancementMode.iconName)
              .foregroundColor(.brandTeal)
              .frame(width: 40, height: 40)
          }
        }
        .listRowBackground(Color.white)
      }
      .onDelete(perform: deletePages)
      .onMove(perform: movePages)
    }
    .frame(minHeight: CGFloat(coordinator.capturedPages.count) * 110 + 40)
    .listStyle(.insetGrouped)
    .background(Color.brandCream)
    .environment(\.editMode, .constant(.active))
  }

  private var doneBar: some View {
    HStack(spacing: 12) {
      if coordinator.currentMode.supportsMultiPage {
        Button(action: onBackToScanner) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 28))
            .foregroundColor(.brandTeal)
        }
      }

      Button(action: build) {
        HStack(spacing: 6) {
          Text("Save PDF")
            .font(.system(size: 15, weight: .semibold))
          Image(systemName: "arrow.right")
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.brandTeal)
        .clipShape(RoundedRectangle(cornerRadius: 14))
      }
      .disabled(isBuilding)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(Color.brandCream)
  }

  // MARK: - Mode-specific banners

  @ViewBuilder
  private func receiptBanner(_ meta: ScanMetadata) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.brandSuccess)
        Text("Extracted from receipt")
          .font(.system(size: 13, weight: .semibold))
      }
      if let merchant = meta.extractedMerchant {
        Text("Merchant: \(merchant)").font(.system(size: 12))
      }
      if let amount = meta.extractedAmount {
        Text("Amount: \(meta.extractedCurrency ?? "USD") \(String(format: "%.2f", amount))")
          .font(.system(size: 12))
      }
      if let date = meta.extractedDate {
        Text("Date: \(date.formatted(date: .abbreviated, time: .omitted))")
          .font(.system(size: 12))
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.brandTealBg)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .padding(.horizontal, 18)
  }

  @ViewBuilder
  private var idBanner: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "eye.slash.fill")
          .foregroundColor(.brandWarning)
        Text("Sensitive data detected")
          .font(.system(size: 13, weight: .semibold))
      }
      Text("\(idRegions.count) field\(idRegions.count == 1 ? "" : "s") found:")
        .font(.system(size: 12))
      ForEach(Array(Set(idRegions.map { $0.field })), id: \.self) { field in
        Text("• \(field.displayName)")
          .font(.system(size: 12))
      }
      Button {
        applyIDRedaction()
      } label: {
        Text(didApplyRedaction ? "Redacted ✓" : "Redact all")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(didApplyRedaction ? Color.brandSuccess : Color.brandWarning)
          .clipShape(Capsule())
      }
      .disabled(didApplyRedaction)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.brandWarning.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .padding(.horizontal, 18)
  }

  // MARK: - Helpers

  private func pageTitle(forIndex idx: Int, page: ScannedPage) -> String {
    if coordinator.currentMode == .card {
      switch page.side {
      case .front: return "Front side"
      case .back: return "Back side"
      case .none: return "Card"
      }
    }
    return "Page \(idx + 1)"
  }

  private func qualityLabel(for score: Double) -> String {
    if score < 0.3 { return "Blurry · consider retake" }
    if score < 0.55 { return "Okay" }
    return "Sharp"
  }

  private func applyMode(_ mode: EnhancementMode, to page: ScannedPage) {
    guard let idx = coordinator.capturedPages.firstIndex(where: { $0.id == page.id })
    else { return }
    let source = coordinator.capturedPages[idx].correctedImage
    if let enhanced = ImageProcessor.applyEnhancement(mode, to: source) {
      coordinator.capturedPages[idx].enhancedImage = enhanced
      coordinator.capturedPages[idx].enhancementMode = mode
    }
  }

  private func deletePages(at offsets: IndexSet) {
    coordinator.capturedPages.remove(atOffsets: offsets)
  }

  private func movePages(from offsets: IndexSet, to dest: Int) {
    coordinator.capturedPages.move(fromOffsets: offsets, toOffset: dest)
  }

  // MARK: - Mode post-processing (OCR / receipt parse / ID detect)

  /// Runs once when the page list stabilises. Receipt mode pulls OCR
  /// + parser metadata so the banner shows immediately; ID mode runs
  /// the text-region detector and surfaces the redact suggestion.
  private func runModePostProcess() async {
    guard !didRunModePostProcess, !coordinator.capturedPages.isEmpty
    else { return }
    didRunModePostProcess = true

    let mode = coordinator.currentMode
    let firstPage = coordinator.capturedPages[0].enhancedImage

    if mode == .receipt {
      let text = await OCRProcessor.recognizeText(in: firstPage)
      let parsed = ReceiptParser.parse(text)
      await MainActor.run { self.receiptMeta = parsed }
    }

    if mode == .id {
      let regions = await OCRProcessor.detectTextRegions(in: firstPage)
      let sensitive = IDRedactor.findSensitiveRegions(in: regions)
      await MainActor.run { self.idRegions = sensitive }
    }
  }

  private func applyIDRedaction() {
    guard !didApplyRedaction, !idRegions.isEmpty else { return }
    for (index, page) in coordinator.capturedPages.enumerated() {
      let redacted = IDRedactor.redact(
        image: page.enhancedImage,
        regions: idRegions
      )
      coordinator.capturedPages[index].enhancedImage = redacted
    }
    didApplyRedaction = true
  }

  // MARK: - Build

  private func build() {
    let pages = coordinator.capturedPages
    let mode = coordinator.currentMode
    guard !pages.isEmpty else { return }
    isBuilding = true

    // Snapshot metadata destined for Dart. Receipt extracts populate
    // the relevant fields; ID mode reports which field types we
    // redacted; other modes leave nil/empty.
    var outboundMeta: ScanMetadata? = nil
    if mode == .receipt, let m = receiptMeta {
      outboundMeta = m
    }
    if mode == .id, didApplyRedaction {
      var m = ScanMetadata()
      m.redactedFields = Array(Set(idRegions.map { $0.field.rawValue }))
      outboundMeta = m
    }

    Task.detached(priority: .userInitiated) {
      let data = PDFAssembler.assemble(pages: pages, mode: mode)
      await MainActor.run {
        isBuilding = false
        guard let data = data else {
          buildError = "PDF writer returned no data."
          return
        }
        do {
          let path = try PDFAssembler.writeToTemp(data: data)
          let url = URL(fileURLWithPath: path)
          onDone(url, outboundMeta)
        } catch {
          buildError = "Couldn't write PDF: \(error.localizedDescription)"
        }
      }
    }
  }
}

// =============================================================================
// MARK: - Host wrapper (capture → preview navigation)
// =============================================================================

struct ScannerHostView: View {
  let initialMode: ScanMode
  let enableOCR: Bool
  let onDone: (URL, ScanMetadata?) -> Void
  let onCancel: () -> Void

  @StateObject private var coordinator = ScannerCoordinator()
  @State private var showPreview = false
  @State private var didSeedMode = false

  var body: some View {
    Group {
      if showPreview {
        ScannerPreviewView(
          coordinator: coordinator,
          enableOCR: enableOCR,
          onBackToScanner: { showPreview = false },
          onDone: onDone
        )
      } else {
        ScannerView(
          coordinator: coordinator,
          onClose: onCancel,
          onShowPreview: { showPreview = true }
        )
      }
    }
    .onAppear {
      // Seed the coordinator with the requested mode the very first
      // time this host renders. After that, the user's mode pill
      // selections drive `coordinator.currentMode` directly.
      if !didSeedMode {
        coordinator.setMode(initialMode)
        didSeedMode = true
      }
    }
    .onChange(of: coordinator.shouldShowPreview) { newValue in
      // Card mode + the last receipt page auto-advance to preview;
      // we listen here so the host's `showPreview` flips in sync.
      if newValue {
        showPreview = true
        coordinator.shouldShowPreview = false
      }
    }
  }
}

// =============================================================================
// MARK: - Flutter Bridge
// =============================================================================

class DocumentScannerBridge: NSObject, FlutterPlugin,
                             VNDocumentCameraViewControllerDelegate {
  static let channelName = "com.erekstudio.pdfprivio/scanner"

  private var pendingResult: FlutterResult?
  private var presentedHost: UIViewController?
  /// Set when the VisionKit fallback is opened so the delegate
  /// callbacks know which mode to assemble for. The custom path
  /// doesn't need this — `ScannerHostView` carries its own mode.
  private var pendingVisionKitMode: ScanMode?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DocumentScannerBridge()
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      // Real device with a back camera. Simulator always returns false.
      let hasCamera = AVCaptureDevice.default(
        .builtInWideAngleCamera, for: .video, position: .back) != nil
      result(hasCamera)

    case "scan":
      let args = call.arguments as? [String: Any]
      let useAppleVisionKit = args?["useAppleVisionKit"] as? Bool ?? false
      let modeString = (args?["mode"] as? String) ?? "doc"
      let enableOCR = args?["enableOCR"] as? Bool ?? false
      guard let mode = ScanMode(rawValue: modeString) else {
        result(FlutterError(
          code: "mode_unsupported",
          message: "Unknown scan mode: \(modeString)",
          details: nil
        ))
        return
      }
      if useAppleVisionKit {
        scanWithVisionKit(result: result, mode: mode)
      } else {
        scanWithCustomUI(result: result, mode: mode, enableOCR: enableOCR)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Custom AVFoundation scanner

  private func scanWithCustomUI(
    result: @escaping FlutterResult,
    mode: ScanMode,
    enableOCR: Bool
  ) {
    guard let root = Self.rootViewController() else {
      result(FlutterError(code: "no_presenter",
                          message: "Could not find a presenter.",
                          details: nil))
      return
    }
    if pendingResult != nil {
      result(FlutterError(code: "busy",
                          message: "Scanner is already open.",
                          details: nil))
      return
    }
    pendingResult = result

    let host = ScannerHostView(
      initialMode: mode,
      enableOCR: enableOCR,
      onDone: { [weak self] url, metadata in
        self?.finishSuccess(pdfPath: url.path, metadata: metadata)
      },
      onCancel: { [weak self] in
        self?.finishCancel()
      }
    )

    let hosting = UIHostingController(rootView: host)
    hosting.modalPresentationStyle = .fullScreen
    presentedHost = hosting
    Self.topMost(from: root).present(hosting, animated: true)
  }

  /// Success path — returns a `Map` over the channel with the PDF path
  /// and (for receipt / id modes) a metadata dictionary the Dart side
  /// decodes into `ScanMetadata`.
  private func finishSuccess(pdfPath: String, metadata: ScanMetadata?) {
    presentedHost?.dismiss(animated: true)
    presentedHost = nil

    var payload: [String: Any] = ["pdfPath": pdfPath]
    if let meta = metadata {
      var dict: [String: Any] = [:]
      if let date = meta.extractedDate {
        dict["date"] = Int(date.timeIntervalSince1970 * 1000)
      }
      if let amount = meta.extractedAmount {
        dict["amount"] = amount
      }
      if let currency = meta.extractedCurrency {
        dict["currency"] = currency
      }
      if let merchant = meta.extractedMerchant {
        dict["merchant"] = merchant
      }
      if !meta.redactedFields.isEmpty {
        dict["redactedFields"] = meta.redactedFields
      }
      if let ocrText = meta.ocrText {
        dict["ocrText"] = ocrText
      }
      if !dict.isEmpty {
        payload["metadata"] = dict
      }
    }

    pendingResult?(payload)
    pendingResult = nil
  }

  /// Cancel path — returns nil so the Dart side reads it as user
  /// cancellation, not an error.
  private func finishCancel() {
    presentedHost?.dismiss(animated: true)
    presentedHost = nil
    pendingResult?(nil)
    pendingResult = nil
  }

  // MARK: VisionKit fallback (debug toggle)

  private func scanWithVisionKit(
    result: @escaping FlutterResult,
    mode: ScanMode
  ) {
    guard VNDocumentCameraViewController.isSupported else {
      result(FlutterError(code: "unsupported",
                          message: "VisionKit scanner needs a real camera.",
                          details: nil))
      return
    }
    guard let root = Self.rootViewController() else {
      result(FlutterError(code: "no_presenter",
                          message: "Could not find a presenter.",
                          details: nil))
      return
    }
    if pendingResult != nil {
      result(FlutterError(code: "busy",
                          message: "Scanner is already open.",
                          details: nil))
      return
    }

    pendingResult = result
    pendingVisionKitMode = mode
    let scanner = VNDocumentCameraViewController()
    scanner.delegate = self
    scanner.modalPresentationStyle = .fullScreen
    presentedHost = scanner
    Self.topMost(from: root).present(scanner, animated: true)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFinishWith scan: VNDocumentCameraScan
  ) {
    var images: [UIImage] = []
    for i in 0..<scan.pageCount {
      images.append(scan.imageOfPage(at: i))
    }

    let mode = pendingVisionKitMode ?? .doc
    pendingVisionKitMode = nil

    // VisionKit gives us plain UIImages without quad / blur metadata,
    // so wrap them as ScannedPages with default-enhancement set to the
    // mode's default and route through the mode-aware assembler so
    // receipt / card layouts come out the same as the custom path.
    let scannedPages: [ScannedPage] = images.map { img in
      ScannedPage(
        originalImage: img,
        correctedImage: img,
        enhancedImage: img,
        quad: [],
        enhancementMode: mode.defaultEnhancement,
        blurScore: 1.0
      )
    }

    controller.dismiss(animated: true)
    presentedHost = nil

    if let data = PDFAssembler.assemble(pages: scannedPages, mode: mode) {
      do {
        let path = try PDFAssembler.writeToTemp(data: data)
        pendingResult?(["pdfPath": path])
      } catch {
        pendingResult?(FlutterError(code: "pdf_failed",
                                    message: error.localizedDescription,
                                    details: nil))
      }
    } else {
      pendingResult?(FlutterError(code: "pdf_failed",
                                  message: "Could not assemble PDF.",
                                  details: nil))
    }
    pendingResult = nil
  }

  func documentCameraViewControllerDidCancel(
    _ controller: VNDocumentCameraViewController
  ) {
    controller.dismiss(animated: true)
    presentedHost = nil
    pendingVisionKitMode = nil
    pendingResult?(nil)
    pendingResult = nil
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    controller.dismiss(animated: true)
    presentedHost = nil
    pendingVisionKitMode = nil
    pendingResult?(FlutterError(code: "scan_failed",
                                message: error.localizedDescription,
                                details: nil))
    pendingResult = nil
  }

  // MARK: helpers

  private static func rootViewController() -> UIViewController? {
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?
      .rootViewController
  }

  private static func topMost(from vc: UIViewController) -> UIViewController {
    if let presented = vc.presentedViewController {
      return topMost(from: presented)
    }
    return vc
  }
}
