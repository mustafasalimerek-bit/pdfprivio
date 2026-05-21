//
//  Intents.swift
//  Privio
//
//  AppIntent definitions surfaced to Siri + the Shortcuts app. Each
//  intent opens the host app via `openAppWhenRun: true` and drops a
//  target route into UserDefaults; AppIntentBridge (Swift) reads it
//  inside the running app and forwards over a MethodChannel so the
//  Flutter side can Navigator.pushNamed straight into the tool.
//
//  iOS 16+ only — AppIntents framework. Annotated with @available so
//  the rest of the app still builds for the iOS 15.5 deployment
//  target.
//

import AppIntents
import Foundation

enum PDFPrivioIntentRoute {
    static let defaultsKey = "pdfprivio.pendingIntentRoute"
    static let appGroupId = "group.com.erekstudio.pdfprivio"

    /// Write the pending route to BOTH the standard UserDefaults
    /// domain AND the App Group container. The widget-side copy of
    /// these intents (in PDFPrivioWidget.swift) already does this
    /// dual-write because widgets run out-of-process. The host-side
    /// intents historically only wrote to `standard`, which works
    /// today because `openAppWhenRun: true` runs the intent in the
    /// host process — but Apple has been moving AppIntent execution
    /// out-of-process incrementally (Action Button on iOS 17.4+
    /// already does it for some intents). Mirroring both keeps the
    /// route reachable from either side, so AppIntentBridge.consume
    /// can find it on cold launch regardless of which process iOS
    /// chose to run the intent in.
    static func enqueue(_ route: String) {
        UserDefaults.standard.set(route, forKey: defaultsKey)
        UserDefaults(suiteName: appGroupId)?
            .set(route, forKey: defaultsKey)
    }
}

@available(iOS 16.0, *)
struct SignPdfIntent: AppIntent {
    static var title: LocalizedStringResource = "Sign a PDF"
    static var description = IntentDescription(
        "Open the Sign tool to draw and place a signature on a PDF."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PDFPrivioIntentRoute.enqueue("/tool/sign")
        return .result()
    }
}

@available(iOS 16.0, *)
struct RedactPdfIntent: AppIntent {
    static var title: LocalizedStringResource = "Redact a PDF"
    static var description = IntentDescription(
        "Open the Redact tool to search and permanently remove text from a PDF."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PDFPrivioIntentRoute.enqueue("/tool/redact")
        return .result()
    }
}

@available(iOS 16.0, *)
struct OcrPdfIntent: AppIntent {
    static var title: LocalizedStringResource = "OCR a PDF"
    static var description = IntentDescription(
        "Open the OCR tool to add a searchable text layer to a scanned PDF."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PDFPrivioIntentRoute.enqueue("/tool/ocr")
        return .result()
    }
}

@available(iOS 16.0, *)
struct FindSensitiveDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Find sensitive data"
    static var description = IntentDescription(
        "Open the PII scanner to auto-detect SSN, EIN, credit cards, emails, and phone numbers in a PDF."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PDFPrivioIntentRoute.enqueue("/tool/pii")
        return .result()
    }
}

@available(iOS 16.0, *)
struct ScanToPdfIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan to PDF"
    static var description = IntentDescription(
        "Open the document scanner — auto edge detection and multi-page capture into one PDF."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // `?auto=1` tells ScanScreen to fire VNDocumentCameraViewController
        // immediately instead of showing the "Scan now" intro screen.
        // The whole point of a Siri / Shortcuts trigger is to skip the
        // tap-through; without auto-fire the shortcut buys the user
        // nothing over tapping the home tile.
        PDFPrivioIntentRoute.enqueue("/tool/scan?auto=1")
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenRecentIntent: AppIntent {
    static var title: LocalizedStringResource = "Open recent files"
    static var description = IntentDescription(
        "Jump straight to the Recent tab to pick up yesterday's work."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PDFPrivioIntentRoute.enqueue("tab:recent")
        return .result()
    }
}
