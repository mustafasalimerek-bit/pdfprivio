//
//  QuickLookBridge.swift
//  Runner
//
//  Presents a file (PDF or image) in Apple's QLPreviewController.
//
//  Why QuickLook instead of a custom VisionKit / ImageAnalyzer
//  rendering: the system viewer ALREADY does Live Text (iOS 16+),
//  Visual Look Up (iOS 17+), Markup, signing, share — all of the
//  iOS-native interactions a lawyer wants when reading a PDF, with
//  pixel-perfect typography and zero work on our part. Editorial
//  pitch is the same ("powered by Apple's Live Text + Visual Look
//  Up"), implementation cost is a third.
//
//  The bridge presents the viewer modally over whatever's at the
//  top of the navigation stack and returns control via the
//  FlutterResult once the user dismisses it.
//

import Flutter
import QuickLook
import UIKit

class QuickLookBridge: NSObject, FlutterPlugin {
    static let channelName = "com.erekstudio.pdfprivio/quick_look"

    private var pendingResult: FlutterResult?
    private var pendingURL: URL?
    private weak var presentedController: QLPreviewController?

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = QuickLookBridge()
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(
                    code: "bad_args",
                    message: "show requires { path: String }",
                    details: nil
                ))
                return
            }
            present(path: path, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func present(path: String, result: @escaping FlutterResult) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            result(FlutterError(
                code: "not_found",
                message: "File doesn't exist at \(path)",
                details: nil
            ))
            return
        }
        guard let presenter = Self.topMostController() else {
            result(FlutterError(
                code: "no_presenter",
                message: "Could not find a view controller to present from.",
                details: nil
            ))
            return
        }
        if pendingResult != nil {
            // Already showing — politely tell the caller.
            result(FlutterError(
                code: "busy",
                message: "QuickLook is already presenting another file.",
                details: nil
            ))
            return
        }

        pendingResult = result
        pendingURL = url

        let preview = QLPreviewController()
        preview.dataSource = self
        preview.delegate = self
        preview.modalPresentationStyle = .fullScreen
        presentedController = preview
        presenter.present(preview, animated: true)
    }

    private static func topMostController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        guard let root = root else { return nil }
        var top: UIViewController = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - QLPreviewControllerDataSource

extension QuickLookBridge: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return pendingURL == nil ? 0 : 1
    }

    func previewController(
        _ controller: QLPreviewController,
        previewItemAt index: Int
    ) -> QLPreviewItem {
        return (pendingURL ?? URL(fileURLWithPath: "/dev/null")) as QLPreviewItem
    }
}

// MARK: - QLPreviewControllerDelegate

extension QuickLookBridge: QLPreviewControllerDelegate {
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        // User dismissed — hand control back to Flutter.
        pendingResult?(true)
        pendingResult = nil
        pendingURL = nil
        presentedController = nil
    }
}
