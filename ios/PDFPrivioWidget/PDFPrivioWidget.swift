//
//  PDFPrivioWidget.swift
//  PDFPrivioWidget
//
//  Home Screen widget for PDFPrivio. Reads the top-3 recent files
//  out of the App Group shared NSUserDefaults (written from the Flutter
//  side by WidgetDataService) and renders them in Small / Medium sizes.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - ScanToPdfIntent (widget-side copy)
//
// AppIntents bound to a ControlWidgetButton must be declared inside
// the widget extension's compilation unit — the widget target can't
// see the Runner target's intent struct. Both copies enqueue the
// same App Group UserDefaults key, so the host app's
// AppIntentBridge drains either invocation identically. Keep this
// in sync with ios/Runner/AppIntents/Intents.swift if the routing
// key or route string changes.

@available(iOS 16.0, *)
struct ScanToPdfIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan to PDF"
    static var description = IntentDescription(
        "Open the document scanner — Apple VisionKit edge detection and multi-page capture into one PDF."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let defaults = UserDefaults(suiteName: "group.com.erekstudio.pdfprivio") {
            defaults.set("/tool/scan", forKey: "pdfprivio.pendingIntentRoute")
        }
        UserDefaults.standard.set("/tool/scan", forKey: "pdfprivio.pendingIntentRoute")
        return .result()
    }
}

// MARK: - Data model

private struct RecentFileItem: Codable {
    let name: String
    let tool: String
    let openedAtMs: Int64

    var openedAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(openedAtMs) / 1000.0)
    }
}

private struct PDFPrivioEntry: TimelineEntry {
    let date: Date
    let files: [RecentFileItem]
    let isPlaceholder: Bool
}

// MARK: - Timeline Provider

private struct Provider: TimelineProvider {
    private let appGroupId = "group.com.erekstudio.pdfprivio"
    private let dataKey = "recent_files_json"

    func placeholder(in context: Context) -> PDFPrivioEntry {
        PDFPrivioEntry(date: Date(), files: sampleFiles, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PDFPrivioEntry) -> Void) {
        let files = loadFiles() ?? (context.isPreview ? sampleFiles : [])
        completion(PDFPrivioEntry(date: Date(), files: files, isPlaceholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PDFPrivioEntry>) -> Void) {
        let files = loadFiles() ?? []
        let entry = PDFPrivioEntry(date: Date(), files: files, isPlaceholder: false)
        // Refresh hourly as a safety net. HomeWidget.updateWidget() from
        // the Flutter side triggers an immediate refresh on top of this
        // whenever a recent file is recorded.
        let next = Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadFiles() -> [RecentFileItem]? {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        guard let raw = defaults.string(forKey: dataKey) else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        struct Payload: Codable {
            let files: [RecentFileItem]
        }
        return (try? JSONDecoder().decode(Payload.self, from: data))?.files
    }

    private var sampleFiles: [RecentFileItem] {
        let now = Date().timeIntervalSince1970 * 1000
        return [
            RecentFileItem(name: "Contract draft.pdf", tool: "Signed", openedAtMs: Int64(now - 60_000)),
            RecentFileItem(name: "Tax return.pdf", tool: "Merged", openedAtMs: Int64(now - 3_600_000)),
            RecentFileItem(name: "Affidavit.pdf", tool: "Redacted", openedAtMs: Int64(now - 86_400_000))
        ]
    }
}

// MARK: - Theming helpers

private let brandColor = Color(red: 15.0 / 255.0, green: 118.0 / 255.0, blue: 110.0 / 255.0)

private func relativeTime(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - Views

private struct PDFPrivioWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: PDFPrivioEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(entry: entry)
        case .systemMedium:
            MediumView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            SmallView(entry: entry)
        }
    }
}

// MARK: - Lock Screen accessory views (iOS 16+)
//
// Three small widgets that live on the Lock Screen / Always-On Display.
// Rendered in a monochrome tint by the system, so we lean on shape +
// SF Symbols rather than colour. accessoryRectangular gives the most
// space; accessoryCircular is the small round badge; accessoryInline
// is the single line above the clock.

private struct AccessoryRectangularView: View {
    let entry: PDFPrivioEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                Text("PDFPrivio")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            if let first = entry.files.first {
                // Privacy mode (empty name): show tool only.
                if first.name.isEmpty {
                    Text(first.tool)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(relativeTime(from: first.openedAtDate))
                        .font(.system(size: 10))
                } else {
                    Text(first.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("\(first.tool) · \(relativeTime(from: first.openedAtDate))")
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
            } else {
                Text("No recent files")
                    .font(.system(size: 11))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct AccessoryCircularView: View {
    let entry: PDFPrivioEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12))
                Text("\(entry.files.count)")
                    .font(.system(size: 16, weight: .bold))
            }
        }
    }
}

private struct AccessoryInlineView: View {
    let entry: PDFPrivioEntry

    var body: some View {
        if let first = entry.files.first {
            Label {
                if first.name.isEmpty {
                    Text("\(first.tool) · \(relativeTime(from: first.openedAtDate))")
                } else {
                    Text("\(first.name) · \(relativeTime(from: first.openedAtDate))")
                }
            } icon: {
                Image(systemName: "doc.text.fill")
            }
        } else {
            Label("PDFPrivio — no recent files", systemImage: "doc.text.fill")
        }
    }
}

private struct SmallView: View {
    let entry: PDFPrivioEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(brandColor)
                    .font(.system(size: 14, weight: .semibold))
                Text("PDFPrivio")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            Spacer()
            if let first = entry.files.first {
                // Empty name = privacy-mode opt-out from Settings.
                // Fall back to a tool-prominent layout that doesn't
                // surface client-identifying filenames on the Home
                // Screen — the lawyer-wedge default for hidden mode.
                if first.name.isEmpty {
                    Text(first.tool)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(brandColor)
                    Spacer(minLength: 4)
                    Text(relativeTime(from: first.openedAtDate))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text(first.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Text(first.tool)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(brandColor)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(relativeTime(from: first.openedAtDate))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No recent files yet")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
    }
}

private struct MediumView: View {
    let entry: PDFPrivioEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(brandColor)
                    .font(.system(size: 13, weight: .semibold))
                Text("PDFPrivio Recent")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 9))
                    Text("On-device")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(brandColor)
            }
            Divider().padding(.vertical, 6)

            if entry.files.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "tray")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                        Text("Recent PDFs will show here")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(Array(entry.files.prefix(3).enumerated()), id: \.offset) { _, file in
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 11))
                            .foregroundColor(brandColor.opacity(0.7))
                        // Privacy-mode (empty name) renders the tool
                        // label as the primary line so a lawyer's
                        // client-named files don't appear on the Home
                        // Screen.
                        if file.name.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.tool)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(brandColor)
                                Text(relativeTime(from: file.openedAtDate))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                HStack(spacing: 3) {
                                    Text(file.tool)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(brandColor)
                                    Text("·")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                    Text(relativeTime(from: file.openedAtDate))
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }
}

// MARK: - Widget definition

struct PDFPrivioRecentWidget: Widget {
    let kind: String = "PDFPrivioWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                PDFPrivioWidgetEntryView(entry: entry)
                    .containerBackground(.background, for: .widget)
            } else {
                PDFPrivioWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(.systemBackground))
            }
        }
        .configurationDisplayName("PDFPrivio Recent")
        .description("Pick up where you left off with your recent PDFs.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

// MARK: - Lock Screen / Control Center quick action (iOS 18+)
//
// A Control surface lets the user pin "Scan to PDF with PDFPrivio"
// to Control Center or as a Lock Screen control. Tapping it fires
// the same ScanToPdfIntent that Siri and the Action Button bind to,
// so iPhone 15 Pro+ owners can map the hardware Action Button to
// PDFPrivio's scanner via Settings → Action Button → Shortcut →
// PDFPrivio → Scan to PDF.
//
// Wrapped in iOS 18 availability — ControlWidget didn't ship until
// iOS 18 (Sept 2024). Pre-18 devices still get every Lock Screen
// accessory family above.

@available(iOS 18.0, *)
struct PDFPrivioScanControl: ControlWidget {
    static let kind: String = "com.erekstudio.pdfprivio.ScanControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ScanToPdfIntent()) {
                Label("Scan to PDF", systemImage: "doc.viewfinder")
            }
        }
        .displayName("Scan to PDF")
        .description("Open PDFPrivio's document scanner from Control Center or the Lock Screen.")
    }
}

@main
struct PDFPrivioWidgetBundle: WidgetBundle {
    var body: some Widget {
        PDFPrivioRecentWidget()
        if #available(iOS 18.0, *) {
            PDFPrivioScanControl()
        }
    }
}
