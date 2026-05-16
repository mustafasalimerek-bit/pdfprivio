//
//  SummarizationBridge.swift
//  Runner
//
//  Bridges the Flutter side to Apple's FoundationModels framework
//  (iOS 26+, Apple Intelligence). Three responsibilities:
//
//   1. `availability` reports whether the system on-device LLM can be
//      used right now — the result is one of four user-facing states
//      (available / device-not-eligible / not-enabled / model-not-
//      ready) so the UI can show an actionable explanation instead of
//      a generic "summary unavailable" toast.
//
//   2. `summarize` runs a single chunk of text through
//      LanguageModelSession and returns the model's response. The
//      Flutter side handles map-reduce chunking so this stays a
//      simple text-in / text-out interface.
//
//   3. iOS 17 / iOS 18 / pre-Apple-Intelligence devices get a clean
//      `available: false` answer and the screen shows an "extract
//      text only" fallback. We never crash on older OS.
//

import Flutter
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

class SummarizationBridge: NSObject, FlutterPlugin {
    static let channelName = "com.erekstudio.pdfprivio/summarization"

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SummarizationBridge()
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "availability":
            result(currentAvailability())
        case "summarize":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String else {
                result(FlutterError(
                    code: "bad_args",
                    message: "summarize requires { text: String, [style: String] }",
                    details: nil
                ))
                return
            }
            let style = (args["style"] as? String) ?? "concise"
            summarize(text: text, style: style, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Availability

    /// One of: "available", "device_not_eligible", "not_enabled",
    /// "model_not_ready", "os_too_old", "unknown".
    private func currentAvailability() -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return "available"
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return "device_not_eligible"
                case .appleIntelligenceNotEnabled:
                    return "not_enabled"
                case .modelNotReady:
                    return "model_not_ready"
                @unknown default:
                    return "unknown"
                }
            }
        }
        return "os_too_old"
        #else
        return "os_too_old"
        #endif
    }

    // MARK: - Summarize

    private func summarize(text: String, style: String, result: @escaping FlutterResult) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Task {
                do {
                    let session = LanguageModelSession()
                    let prompt = buildPrompt(text: text, style: style)
                    let response = try await session.respond(to: prompt)
                    DispatchQueue.main.async {
                        result(response.content)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "summarize_failed",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
                }
            }
            return
        }
        #endif
        result(FlutterError(
            code: "unavailable",
            message: "Apple Intelligence is not available on this device.",
            details: nil
        ))
    }

    /// Prompts vary by intended downstream use:
    ///   * "concise" — 3-5 paragraphs, preserves names / dates / amounts
    ///   * "bullets" — bullet-point key takeaways
    ///   * "chunk"   — short paragraph summary used as input to a
    ///                 second map-reduce pass over long documents
    private func buildPrompt(text: String, style: String) -> String {
        let instruction: String
        switch style {
        case "bullets":
            instruction = "Extract the 5-7 most important points from this document as a bullet list. Preserve names, dates, dollar amounts, and any deadlines exactly as they appear. Do not summarise legal opinions or advice — only state the facts the document presents."
        case "chunk":
            instruction = "Provide a single short paragraph (2-4 sentences) summarising this document section. Preserve named parties, dates, and amounts. Avoid paraphrasing technical or legal terms."
        case "concise":
            fallthrough
        default:
            instruction = "Write a 3-5 paragraph summary of this document. Preserve names of parties, dates, dollar amounts, and any deadlines. Keep technical and legal language faithful to the source. Do not add opinions, recommendations, or speculation."
        }
        return "\(instruction)\n\nDocument:\n\(text)"
    }
}
