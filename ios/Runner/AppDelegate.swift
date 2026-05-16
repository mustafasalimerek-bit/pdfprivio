import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
