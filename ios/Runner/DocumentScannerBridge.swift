import Flutter
import UIKit
import VisionKit

class DocumentScannerBridge: NSObject, FlutterPlugin, VNDocumentCameraViewControllerDelegate {
  static let channelName = "com.erekstudio.pdfwork/scanner"

  private var pendingResult: FlutterResult?

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
      result(VNDocumentCameraViewController.isSupported)
    case "scan":
      scan(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func scan(result: @escaping FlutterResult) {
    guard VNDocumentCameraViewController.isSupported else {
      result(FlutterError(
        code: "unsupported",
        message: "Document Scanner needs a real camera — try on iPhone.",
        details: nil
      ))
      return
    }

    guard let root = Self.rootViewController() else {
      result(FlutterError(
        code: "no_presenter",
        message: "Could not find a view controller to present the scanner.",
        details: nil
      ))
      return
    }

    if pendingResult != nil {
      result(FlutterError(
        code: "busy",
        message: "Scanner is already open.",
        details: nil
      ))
      return
    }

    pendingResult = result
    let scanner = VNDocumentCameraViewController()
    scanner.delegate = self
    scanner.modalPresentationStyle = .fullScreen
    Self.topMost(from: root).present(scanner, animated: true)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFinishWith scan: VNDocumentCameraScan
  ) {
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    let outputDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("pdfwork_scans_\(stamp)", isDirectory: true)

    do {
      try FileManager.default.createDirectory(
        at: outputDir,
        withIntermediateDirectories: true
      )
    } catch {
      controller.dismiss(animated: true)
      pendingResult?(FlutterError(
        code: "io_failed",
        message: "Could not create temp directory: \(error.localizedDescription)",
        details: nil
      ))
      pendingResult = nil
      return
    }

    var paths: [String] = []
    for i in 0..<scan.pageCount {
      let image = scan.imageOfPage(at: i)
      guard let data = image.jpegData(compressionQuality: 0.92) else { continue }
      let url = outputDir.appendingPathComponent(
        String(format: "page_%03d.jpg", i + 1)
      )
      do {
        try data.write(to: url, options: .atomic)
        paths.append(url.path)
      } catch {
        // Skip individual page write failures — return whatever we got.
      }
    }

    controller.dismiss(animated: true)
    pendingResult?(paths)
    pendingResult = nil
  }

  func documentCameraViewControllerDidCancel(
    _ controller: VNDocumentCameraViewController
  ) {
    controller.dismiss(animated: true)
    pendingResult?([])
    pendingResult = nil
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    controller.dismiss(animated: true)
    pendingResult?(FlutterError(
      code: "scan_failed",
      message: error.localizedDescription,
      details: nil
    ))
    pendingResult = nil
  }

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
