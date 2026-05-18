//
//  PDFPrivioAppShortcuts.swift
//  Privio
//
//  Declares the AppShortcuts iOS automatically surfaces in the
//  Shortcuts app + as Siri voice triggers. The `phrases` list is what
//  the user actually speaks; ${(.applicationName)} resolves to the
//  app's display name so a future rebrand won't strand the phrases.
//

import AppIntents

@available(iOS 16.0, *)
struct PDFPrivioAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SignPdfIntent(),
            phrases: [
                "Sign a PDF with \(.applicationName)",
                "Sign a document with \(.applicationName)",
                "Sign in \(.applicationName)"
            ],
            shortTitle: "Sign PDF",
            systemImageName: "signature"
        )
        AppShortcut(
            intent: RedactPdfIntent(),
            phrases: [
                "Redact a PDF with \(.applicationName)",
                "Hide sensitive text with \(.applicationName)",
                "Redact in \(.applicationName)"
            ],
            shortTitle: "Redact PDF",
            systemImageName: "rectangle.dashed"
        )
        AppShortcut(
            intent: OcrPdfIntent(),
            phrases: [
                "OCR a PDF with \(.applicationName)",
                "Make a PDF searchable with \(.applicationName)",
                "Run OCR in \(.applicationName)"
            ],
            shortTitle: "OCR PDF",
            systemImageName: "doc.text.viewfinder"
        )
        AppShortcut(
            intent: FindSensitiveDataIntent(),
            phrases: [
                "Find sensitive data with \(.applicationName)",
                "Scan a PDF for PII with \(.applicationName)",
                "Check this PDF for personal data with \(.applicationName)"
            ],
            shortTitle: "Find sensitive data",
            systemImageName: "exclamationmark.shield"
        )
        AppShortcut(
            intent: ScanToPdfIntent(),
            phrases: [
                "Scan a document with \(.applicationName)",
                "Scan to PDF with \(.applicationName)",
                "Start a scan in \(.applicationName)"
            ],
            shortTitle: "Scan to PDF",
            systemImageName: "doc.viewfinder"
        )
        AppShortcut(
            intent: OpenRecentIntent(),
            phrases: [
                "Show my recent PDFs in \(.applicationName)",
                "Open recent files in \(.applicationName)"
            ],
            shortTitle: "Open Recent",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
