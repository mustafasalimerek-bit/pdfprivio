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
  static let brandTealLight = Color(red: 0x14 / 255.0,
                                    green: 0xB8 / 255.0,
                                    blue: 0xA6 / 255.0)
  static let brandCream = Color(red: 0xF5 / 255.0,
                                green: 0xF1 / 255.0,
                                blue: 0xEA / 255.0)
}

// =============================================================================
// MARK: - Scanner Models
// =============================================================================

enum ScannerGuidance: Equatable {
  case searching
  case moveCloser
  case moveFurther
  case holdSteady
  case improveLight
  case detected(quality: CGFloat)
  case readyToCapture
  case capturing

  var userMessage: String {
    switch self {
    case .searching: return "Looking for document"
    case .moveCloser: return "Move closer"
    case .moveFurther: return "Move further away"
    case .holdSteady: return "Hold steady"
    case .improveLight: return "Move to better light"
    case .detected: return "Document detected"
    case .readyToCapture: return "Capturing in 1s…"
    case .capturing: return "Captured"
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

  var needsRetake: Bool { blurScore < 0.3 }
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

// =============================================================================
// MARK: - PDF Assembler
// =============================================================================

enum PDFAssembler {
  /// Builds a PDF from the enhanced images of each ScannedPage and
  /// writes to `destination`. Returns true on success.
  static func writePDF(pages: [ScannedPage], to destination: URL) -> Bool {
    let pdf = PDFDocument()
    for (idx, page) in pages.enumerated() {
      guard let pdfPage = PDFPage(image: page.enhancedImage) else { continue }
      pdf.insert(pdfPage, at: idx)
    }
    return pdf.write(to: destination)
  }

  /// Convenience overload for the VisionKit fallback path which only
  /// has plain UIImages (no Quad / blur score).
  static func writePDF(images: [UIImage], to destination: URL) -> Bool {
    let pdf = PDFDocument()
    for (idx, image) in images.enumerated() {
      guard let pdfPage = PDFPage(image: image) else { continue }
      pdf.insert(pdfPage, at: idx)
    }
    return pdf.write(to: destination)
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
    let enhanced = ImageProcessor.applyEnhancement(.colorDocument, to: corrected) ?? corrected

    let page = ScannedPage(
      originalImage: image,
      correctedImage: corrected,
      enhancedImage: enhanced,
      quad: quad,
      blurScore: blurScore
    )

    if page.needsRetake {
      blurWarningPage = page
    } else {
      capturedPages.append(page)
    }

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
    let request = VNDetectRectanglesRequest { [weak self] request, _ in
      guard let self = self else { return }
      let observations = request.results as? [VNRectangleObservation] ?? []
      Task { @MainActor in
        self.handleObservations(observations)
      }
    }

    request.minimumAspectRatio = 0.4
    request.maximumAspectRatio = 1.0
    request.minimumSize = 0.3
    request.maximumObservations = 1
    request.minimumConfidence = 0.75
    request.quadratureTolerance = 25

    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                        orientation: .right,
                                        options: [:])
    try? handler.perform([request])
  }

  @MainActor
  private func handleObservations(_ observations: [VNRectangleObservation]) {
    guard let rect = observations.first else {
      handleNoDetection()
      return
    }

    detectedQuad = [
      rect.topLeft, rect.topRight,
      rect.bottomRight, rect.bottomLeft
    ]

    let area = abs(
      (rect.topRight.x - rect.topLeft.x) *
      (rect.bottomLeft.y - rect.topLeft.y)
    )

    if area < 0.25 {
      updateGuidance(.moveCloser)
      resetStability()
      return
    }

    if area > 0.92 {
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

    if stableDuration >= stabilityThreshold && isAutoCapture {
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
    return xVariance < 0.003 && yVariance < 0.003
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
        guard let self = self,
              case .readyToCapture = self.guidance else { return }
        self.triggerCapture()
        self.captureCountdown = nil
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

        Spacer()

        ScannerBottomBar(
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
  let capturedCount: Int
  @Binding var isAutoCapture: Bool
  let onCapture: () -> Void
  let onShowPreview: () -> Void

  @State private var selectedMode: String = "Doc"
  @State private var showComingSoon: Bool = false
  private let modes = ["Doc", "Receipt", "Card", "ID"]

  var body: some View {
    VStack(spacing: 16) {
      HStack(spacing: 6) {
        ForEach(modes, id: \.self) { mode in
          modeChip(mode, isActive: mode == selectedMode, enabled: mode == "Doc")
            .onTapGesture {
              if mode == "Doc" {
                selectedMode = mode
              } else {
                showComingSoon = true
              }
            }
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
    .alert("Coming soon", isPresented: $showComingSoon) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Receipt, Card, and ID modes are arriving in a future update. Doc mode handles most documents today.")
    }
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

  private func modeChip(_ title: String, isActive: Bool, enabled: Bool) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .medium))
      .foregroundColor(enabled
                       ? (isActive ? .white : .white.opacity(0.5))
                       : .white.opacity(0.25))
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(isActive ? Color.white.opacity(0.18) : Color.clear)
      .clipShape(Capsule())
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
  let onBackToScanner: () -> Void
  let onDone: (URL) -> Void

  @State private var isBuilding = false
  @State private var buildError: String?

  var body: some View {
    NavigationView {
      ZStack {
        Color.brandCream.ignoresSafeArea()

        if coordinator.capturedPages.isEmpty {
          emptyState
        } else {
          VStack(spacing: 0) {
            pageList
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
      .navigationTitle("Review \(coordinator.capturedPages.count) page\(coordinator.capturedPages.count == 1 ? "" : "s")")
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
            Text("Page \(idx + 1)")
              .font(.system(size: 15, weight: .semibold))
            Text(qualityLabel(for: page.blurScore))
              .font(.system(size: 12))
              .foregroundColor(page.blurScore < 0.45
                               ? .orange
                               : .secondary)
          }

          Spacer()

          Menu {
            ForEach(EnhancementMode.allCases) { mode in
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
    .listStyle(.insetGrouped)
    .background(Color.brandCream)
    .environment(\.editMode, .constant(.active))
  }

  private var doneBar: some View {
    HStack(spacing: 12) {
      Button(action: onBackToScanner) {
        Image(systemName: "plus.circle.fill")
          .font(.system(size: 28))
          .foregroundColor(.brandTeal)
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

  private func build() {
    let pages = coordinator.capturedPages
    guard !pages.isEmpty else { return }
    isBuilding = true

    Task.detached(priority: .userInitiated) {
      let destination = PDFAssembler.makeTemporaryDestination()
      let ok = PDFAssembler.writePDF(pages: pages, to: destination)
      await MainActor.run {
        isBuilding = false
        if ok {
          onDone(destination)
        } else {
          buildError = "PDF writer returned false."
        }
      }
    }
  }
}

// =============================================================================
// MARK: - Host wrapper (capture → preview navigation)
// =============================================================================

struct ScannerHostView: View {
  let onDone: (URL) -> Void
  let onCancel: () -> Void

  @StateObject private var coordinator = ScannerCoordinator()
  @State private var showPreview = false

  var body: some View {
    if showPreview {
      ScannerPreviewView(
        coordinator: coordinator,
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
}

// =============================================================================
// MARK: - Flutter Bridge
// =============================================================================

class DocumentScannerBridge: NSObject, FlutterPlugin,
                             VNDocumentCameraViewControllerDelegate {
  static let channelName = "com.erekstudio.pdfprivio/scanner"

  private var pendingResult: FlutterResult?
  private var presentedHost: UIViewController?

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
      if useAppleVisionKit {
        scanWithVisionKit(result: result)
      } else {
        scanWithCustomUI(result: result)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Custom AVFoundation scanner

  private func scanWithCustomUI(result: @escaping FlutterResult) {
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
      onDone: { [weak self] url in
        self?.finish(success: url.path)
      },
      onCancel: { [weak self] in
        self?.finish(success: nil)
      }
    )

    let hosting = UIHostingController(rootView: host)
    hosting.modalPresentationStyle = .fullScreen
    presentedHost = hosting
    Self.topMost(from: root).present(hosting, animated: true)
  }

  private func finish(success path: String?) {
    presentedHost?.dismiss(animated: true)
    presentedHost = nil
    pendingResult?(path)
    pendingResult = nil
  }

  // MARK: VisionKit fallback (debug toggle)

  private func scanWithVisionKit(result: @escaping FlutterResult) {
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

    let destination = PDFAssembler.makeTemporaryDestination()
    let ok = PDFAssembler.writePDF(images: images, to: destination)
    controller.dismiss(animated: true)
    presentedHost = nil
    if ok {
      pendingResult?(destination.path)
    } else {
      pendingResult?(FlutterError(code: "pdf_failed",
                                  message: "Could not write PDF.",
                                  details: nil))
    }
    pendingResult = nil
  }

  func documentCameraViewControllerDidCancel(
    _ controller: VNDocumentCameraViewController
  ) {
    controller.dismiss(animated: true)
    presentedHost = nil
    pendingResult?(nil)
    pendingResult = nil
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    controller.dismiss(animated: true)
    presentedHost = nil
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
