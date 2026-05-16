//
//  FileProviderExtension.swift
//  FileProviderExtension
//
//  Modern NSFileProviderReplicatedExtension that exposes the App
//  Group's Inbox folder as a top-level location in the iOS Files app.
//  Read-only for v1.0 — files arrive into the Inbox via the main app's
//  Share Sheet handler, the extension just surfaces them so a lawyer
//  can browse "PDFPrivio" in Files alongside iCloud Drive and Dropbox.
//
//  iOS 16+ only (NSFileProviderReplicatedExtension). The Files app
//  registers the domain on first launch via NSFileProviderManager.add.
//

import FileProvider
import UniformTypeIdentifiers

@available(iOS 16.0, *)
class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain
    static let appGroupId = "group.com.erekstudio.pdfprivio"

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

    func invalidate() {}

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        if identifier == .rootContainer {
            completionHandler(RootContainerItem(), nil)
            return Progress()
        }
        if let url = InboxResolver.url(for: identifier) {
            completionHandler(InboxFileItem(url: url), nil)
        } else {
            completionHandler(
                nil,
                NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.noSuchItem.rawValue
                )
            )
        }
        return Progress()
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        guard let url = InboxResolver.url(for: itemIdentifier) else {
            completionHandler(
                nil, nil,
                NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.noSuchItem.rawValue
                )
            )
            return Progress()
        }
        // The FileProvider system hands the URL back to whoever
        // requested fetchContents. We copy from the App Group into a
        // temp URL so the system can take ownership of the file.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            completionHandler(dest, InboxFileItem(url: url), nil)
        } catch {
            completionHandler(nil, nil, error)
        }
        return Progress()
    }

    // Read-only v1.0 stubs — Files app delete / rename / create disabled.
    // v1.1 will wire write back into the Inbox folder.

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        completionHandler(
            nil, [], false,
            NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.notAuthenticated.rawValue
            )
        )
        return Progress()
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        completionHandler(
            nil, [], false,
            NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.notAuthenticated.rawValue
            )
        )
        return Progress()
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions,
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        completionHandler(
            NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.notAuthenticated.rawValue
            )
        )
        return Progress()
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        return FileProviderEnumerator(containerIdentifier: containerItemIdentifier)
    }
}

// MARK: - Inbox resolution

@available(iOS 16.0, *)
enum InboxResolver {
    static var inboxURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: FileProviderExtension.appGroupId)
        else { return nil }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: inbox,
            withIntermediateDirectories: true
        )
        return inbox
    }

    static func url(for identifier: NSFileProviderItemIdentifier) -> URL? {
        guard let inbox = inboxURL else { return nil }
        let url = inbox.appendingPathComponent(identifier.rawValue)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func listFiles() -> [URL] {
        guard let inbox = inboxURL else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap { $0.contentModificationDate } ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap { $0.contentModificationDate } ?? .distantPast
            return da > db
        }
    }
}

// MARK: - Items

@available(iOS 16.0, *)
class RootContainerItem: NSObject, NSFileProviderItem {
    var itemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { "PDFPrivio" }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities {
        [.allowsContentEnumerating, .allowsReading]
    }
}

@available(iOS 16.0, *)
class InboxFileItem: NSObject, NSFileProviderItem {
    let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(rawValue: url.lastPathComponent)
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }

    var filename: String { url.lastPathComponent }

    var contentType: UTType {
        UTType(filenameExtension: url.pathExtension) ?? .data
    }

    var capabilities: NSFileProviderItemCapabilities {
        [.allowsReading]
    }

    var documentSize: NSNumber? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size
    }

    var contentModificationDate: Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        return date
    }

    var itemVersion: NSFileProviderItemVersion {
        let modDate = contentModificationDate ?? Date.distantPast
        let stamp = "\(modDate.timeIntervalSince1970)".data(using: .utf8) ?? Data()
        return NSFileProviderItemVersion(
            contentVersion: stamp,
            metadataVersion: stamp
        )
    }
}

// MARK: - Enumerator

@available(iOS 16.0, *)
class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    let containerIdentifier: NSFileProviderItemIdentifier

    init(containerIdentifier: NSFileProviderItemIdentifier) {
        self.containerIdentifier = containerIdentifier
        super.init()
    }

    func invalidate() {}

    func enumerateItems(
        for observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        guard containerIdentifier == .rootContainer
                || containerIdentifier == .workingSet else {
            observer.finishEnumerating(upTo: nil)
            return
        }
        let items = InboxResolver.listFiles().map { InboxFileItem(url: $0) }
        observer.didEnumerate(items)
        observer.finishEnumerating(upTo: nil)
    }

    func currentSyncAnchor(
        completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
    ) {
        let anchor = "\(Date().timeIntervalSince1970)".data(using: .utf8) ?? Data()
        completionHandler(NSFileProviderSyncAnchor(anchor))
    }
}
