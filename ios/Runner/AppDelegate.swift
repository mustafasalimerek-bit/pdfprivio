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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShareExtensionBridge") {
      ShareExtensionBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SummarizationBridge") {
      SummarizationBridge.register(with: registrar)
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    // Intercept our custom PDFPrivioShare wake-up URL before
    // receive_sharing_intent or anything else sees it. The drop
    // folder polling happens from Flutter on app resume, but we
    // also nudge it here so a cold-launched-by-share gets the
    // drain to run as soon as the channel is ready.
    if url.scheme == "pdfprivio" {
      ShareExtensionBridge.notifyNewShare()
      return true
    }
    return super.application(app, open: url, options: options)
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

// MARK: - ShareExtensionBridge
//
// Drains the App Group's SharedExtensionDrop folder (written by the
// PDFPrivioShare custom Share Extension) and hands the file paths to
// the Flutter side. Flutter then copies each into Documents/Inbox and
// surfaces the action sheet so the user picks a tool.
//
// Two entry points:
//   * `drain` — called from Flutter on every resume / cold launch
//   * `notifyNewShare` — fired from AppDelegate's openURL handler
//     when our pdfprivio:// wake-up URL hits; sets a flag the next
//     drain call can detect so Flutter knows to refresh immediately
//     even if its lifecycle observer hasn't ticked yet.

class ShareExtensionBridge: NSObject, FlutterPlugin {
  static let channelName = "com.erekstudio.pdfprivio/share_extension"
  static let appGroupId = "group.com.erekstudio.pdfprivio"
  static let dropFolderName = "SharedExtensionDrop"
  static let pendingFlagKey = "pdfprivio.shareExtensionPending"

  static var pendingChannel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ShareExtensionBridge()
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    pendingChannel = channel
  }

  static func notifyNewShare() {
    UserDefaults.standard.set(true, forKey: pendingFlagKey)
    // Best-effort nudge — channel may or may not have a Dart listener
    // yet on cold launch, the polling-on-resume path covers that case.
    pendingChannel?.invokeMethod("shareExtensionPending", arguments: nil)
  }

  static let preferredActionKey = "pdfprivio.preferredShareAction"

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "drain":
      result(Self.drainDropFolder())
    case "clearPendingFlag":
      UserDefaults.standard.removeObject(forKey: Self.pendingFlagKey)
      result(nil)
    case "hasPending":
      result(UserDefaults.standard.bool(forKey: Self.pendingFlagKey))
    case "consumePreferredAction":
      // Read + clear the Action Extension's preferred-tool hint from
      // App Group UserDefaults (set by Quick Sign etc.). Returns nil
      // if the share came from the plain Share Extension.
      guard let defaults = UserDefaults(suiteName: Self.appGroupId) else {
        result(nil)
        return
      }
      let action = defaults.string(forKey: Self.preferredActionKey)
      defaults.removeObject(forKey: Self.preferredActionKey)
      result(action)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Lists every file currently in the App Group drop folder. Flutter
  /// is responsible for copying them to its own Documents/Inbox and
  /// then calling back into `clearPendingFlag` once it's done.
  private static func drainDropFolder() -> [String] {
    guard let container = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
      return []
    }
    let drop = container.appendingPathComponent(dropFolderName, isDirectory: true)
    guard FileManager.default.fileExists(atPath: drop.path) else {
      return []
    }
    let contents = (try? FileManager.default.contentsOfDirectory(
      at: drop,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    return contents
      .sorted { a, b in
        let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))
          .flatMap { $0.contentModificationDate } ?? .distantPast
        let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))
          .flatMap { $0.contentModificationDate } ?? .distantPast
        return da < db
      }
      .map { $0.path }
  }
}
