//
//  ReviewBridge.swift
//  Runner
//
//  Surfaces Apple's `SKStoreReviewController` in-app review prompt
//  on demand from the Flutter side. The Dart `ReviewPromptService`
//  owns the gating logic (success count, days-since-install,
//  cooldown); this bridge is the thin native shim that actually
//  asks iOS to show the prompt.
//
//  iOS rate-limits the prompt itself: at most 3 displays per 365
//  days per app, and it may silently no-op if the user has already
//  declined or rated. We treat all of that as expected — the Dart
//  side bumps its cooldown regardless of whether iOS rendered
//  anything, so we never spam the API.
//

import Flutter
import StoreKit
import UIKit

class ReviewBridge: NSObject, FlutterPlugin {
  static let channelName = "com.erekstudio.pdfprivio/review"

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ReviewBridge()
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestReview":
      requestReview(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// `SKStoreReviewController.requestReview(in:)` is iOS 14+. Our
  /// deployment target is 15.5 so the `#available` is purely a
  /// belt-and-braces check — never hit in practice.
  private func requestReview(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      if #available(iOS 14.0, *) {
        let scene = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .first { $0.activationState == .foregroundActive }
          ?? UIApplication.shared.connectedScenes
              .compactMap { $0 as? UIWindowScene }
              .first
        guard let scene = scene else {
          result(false)
          return
        }
        SKStoreReviewController.requestReview(in: scene)
        result(true)
      } else {
        SKStoreReviewController.requestReview()
        result(true)
      }
    }
  }
}
