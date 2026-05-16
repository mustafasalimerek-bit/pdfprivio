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
        default:
            SmallView(entry: entry)
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

@main
struct PDFPrivioWidget: Widget {
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
