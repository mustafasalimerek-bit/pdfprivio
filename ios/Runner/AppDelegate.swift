import FileProvider
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerFileProviderDomain()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DocumentScannerBridge") {
      DocumentScannerBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TextRecognizerBridge") {
      TextRecognizerBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppIntentBridge") {
      AppIntentBridge.register(with: registrar)
    }
  }

  /// Register the FileProvider domain so PDFPrivio appears as a
  /// top-level location in the Files app sidebar. Idempotent —
  /// NSFileProviderManager.add returns success if already registered.
  /// iOS 16+ only; older devices still get the "On My iPhone >
  /// PDFPrivio" entry via UIFileSharingEnabled + LSSupportsOpening
  /// DocumentsInPlace in Info.plist.
  private func registerFileProviderDomain() {
    guard #available(iOS 16.0, *) else { return }
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier(rawValue: "PDFPrivioInbox"),
      displayName: "PDFPrivio"
    )
    NSFileProviderManager.add(domain) { error in
      if let error = error as NSError? {
        // Code 1 = "already exists" — that's fine.
        if error.code != 1 {
          NSLog("[PDFPrivio] FileProvider domain add failed: \(error)")
        }
      }
    }
  }
}

// MARK: - AppIntentBridge
//
// Tiny channel that hands the pending intent route from
// PDFPrivioIntentRoute's UserDefaults slot over to the Flutter side.
// Flutter calls `consume` on cold launch + every foreground resume;
// we read, clear, and return whatever route the AppIntent enqueued.
//
// Defined here (not in AppIntents/) so the iOS 15.5 build still
// compiles — AppIntents/* files use `@available(iOS 16, *)`, this
// bridge is plain Foundation and works on any version.

class AppIntentBridge: NSObject, FlutterPlugin {
  static let channelName = "com.erekstudio.pdfprivio/app_intent"
  static let defaultsKey = "pdfprivio.pendingIntentRoute"

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AppIntentBridge()
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "consume":
      let defaults = UserDefaults.standard
      let pending = defaults.string(forKey: Self.defaultsKey)
      defaults.removeObject(forKey: Self.defaultsKey)
      result(pending)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
