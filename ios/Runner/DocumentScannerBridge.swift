import AVFoundation
import Flutter
import PDFKit
import UIKit
import Vision
import VisionKit

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

  /// Per-mode default enhancement, tagged on each [ScannedPage] so
  /// future PDFAssembler tweaks can branch on intent (e.g. apply a
  /// B&W pass to receipt pages without re-deriving from the mode).
  var defaultEnhancement: EnhancementMode {
    switch self {
    case .doc: return .colorDocument
    case .receipt: return .blackAndWhite
    case .card: return .magicColor
    case .id: return .colorDocument
    }
  }
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

enum EnhancementMode: String {
  case original = "Original"
  case colorDocument = "Color"
  case grayscale = "Grayscale"
  case blackAndWhite = "B&W"
  case magicColor = "Magic"
}

/// Page wrapper carried into [PDFAssembler]. Today VisionKit hands
/// us pre-cropped UIImages, so `originalImage / correctedImage /
/// enhancedImage` all reference the same image and `quad` is empty —
/// the struct is kept (rather than passing raw UIImages) so the
/// assembler signature stays compatible if a future mode needs to
/// override one of the three (e.g. ID redaction does this for
/// `enhancedImage`).
struct ScannedPage: Identifiable {
  let id = UUID()
  let originalImage: UIImage
  var correctedImage: UIImage
  var enhancedImage: UIImage
  var quad: [CGPoint]
  var enhancementMode: EnhancementMode = .colorDocument
  var blurScore: Double
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
         let combined = combineCardSides(
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

  /// Composites the two card faces side-by-side on a white canvas so
  /// the CR80 landscape PDF lands a single image with both sides
  /// visible. 40pt gap, 800pt height — read well at print sizes.
  private static func combineCardSides(
    front: UIImage, back: UIImage
  ) -> UIImage? {
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

  private static func scaleImage(
    _ image: UIImage, toHeight height: CGFloat
  ) -> UIImage? {
    let ratio = height / image.size.height
    let newWidth = image.size.width * ratio
    let newSize = CGSize(width: newWidth, height: height)
    UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
    defer { UIGraphicsEndImageContext() }
    image.draw(in: CGRect(origin: .zero, size: newSize))
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

}

// =============================================================================
// MARK: - Flutter Bridge
// =============================================================================

class DocumentScannerBridge: NSObject, FlutterPlugin,
                             VNDocumentCameraViewControllerDelegate {
  static let channelName = "com.erekstudio.pdfprivio/scanner"

  private var pendingResult: FlutterResult?
  private var presentedHost: UIViewController?
  /// Carries the requested mode from `scan` through to the
  /// `VNDocumentCameraViewControllerDelegate` callbacks so the
  /// post-processing branch (OCR / Receipt / ID) and the PDF
  /// assembler know which layout to produce.
  private var pendingMode: ScanMode?
  /// When false, the Receipt/ID post-processing branch skips OCR
  /// entirely and the bridge returns only the PDF. Callers that run
  /// their own (higher-fidelity, bounding-box aware) OCR pipeline
  /// — currently just `receipt_capture_screen` — use this to avoid
  /// double work.
  private var pendingExtractMetadata: Bool = true

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
      let modeString = (args?["mode"] as? String) ?? "doc"
      let extractMetadata = (args?["extractMetadata"] as? Bool) ?? true
      guard let mode = ScanMode(rawValue: modeString) else {
        result(FlutterError(
          code: "mode_unsupported",
          message: "Unknown scan mode: \(modeString)",
          details: nil
        ))
        return
      }
      scanWithVisionKit(
        result: result, mode: mode, extractMetadata: extractMetadata
      )

    default:
      result(FlutterMethodNotImplemented)
    }
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

  // MARK: VisionKit scanner

  private func scanWithVisionKit(
    result: @escaping FlutterResult,
    mode: ScanMode,
    extractMetadata: Bool
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
    pendingMode = mode
    pendingExtractMetadata = extractMetadata
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

    let mode = pendingMode ?? .doc
    let extractMetadata = pendingExtractMetadata
    pendingMode = nil
    pendingExtractMetadata = true

    controller.dismiss(animated: true)
    presentedHost = nil

    // Mode-aware post-processing runs on the images VisionKit already
    // cropped + deskewed. Receipt extracts metadata so the Expense
    // Ledger prompt has values to pre-fill; ID detects sensitive
    // regions (SSN, card, DOB, license) and bakes black rectangles
    // into the images before they hit the PDF assembler. Receipt + ID
    // both honour `extractMetadata = false` for callers that prefer to
    // run their own OCR pass on the result PDF.
    Task { [weak self] in
      guard let self = self else { return }

      let processedImages: [UIImage]
      let metadata: ScanMetadata?

      switch mode {
      case .doc, .card:
        processedImages = images
        metadata = nil

      case .receipt:
        if extractMetadata, let first = images.first {
          let text = await OCRProcessor.recognizeText(in: first)
          metadata = ReceiptParser.parse(text)
        } else {
          metadata = nil
        }
        processedImages = images

      case .id:
        if !extractMetadata {
          processedImages = images
          metadata = nil
          break
        }
        var redacted: [UIImage] = []
        var redactedFields: Set<String> = []
        for image in images {
          let regions = await OCRProcessor.detectTextRegions(in: image)
          let sensitive = IDRedactor.findSensitiveRegions(in: regions)
          if sensitive.isEmpty {
            redacted.append(image)
          } else {
            redacted.append(IDRedactor.redact(image: image, regions: sensitive))
            sensitive.forEach { redactedFields.insert($0.field.rawValue) }
          }
        }
        processedImages = redacted
        if redactedFields.isEmpty {
          metadata = nil
        } else {
          var m = ScanMetadata()
          m.redactedFields = Array(redactedFields).sorted()
          metadata = m
        }
      }

      let scannedPages: [ScannedPage] = processedImages.map { img in
        ScannedPage(
          originalImage: img,
          correctedImage: img,
          enhancedImage: img,
          quad: [],
          enhancementMode: mode.defaultEnhancement,
          blurScore: 1.0
        )
      }

      await MainActor.run {
        guard let data = PDFAssembler.assemble(
          pages: scannedPages, mode: mode
        ) else {
          self.pendingResult?(FlutterError(
            code: "pdf_failed",
            message: "Could not assemble PDF.",
            details: nil
          ))
          self.pendingResult = nil
          return
        }
        do {
          let path = try PDFAssembler.writeToTemp(data: data)
          self.finishSuccess(pdfPath: path, metadata: metadata)
        } catch {
          self.pendingResult?(FlutterError(
            code: "pdf_failed",
            message: error.localizedDescription,
            details: nil
          ))
          self.pendingResult = nil
        }
      }
    }
  }

  func documentCameraViewControllerDidCancel(
    _ controller: VNDocumentCameraViewController
  ) {
    controller.dismiss(animated: true)
    presentedHost = nil
    pendingMode = nil
    pendingExtractMetadata = true
    pendingResult?(nil)
    pendingResult = nil
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    controller.dismiss(animated: true)
    presentedHost = nil
    pendingMode = nil
    pendingExtractMetadata = true
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
