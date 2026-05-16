//
//  ShareViewController.swift
//  PDFPrivioShare
//
//  Custom Share Extension that branded-appears as "PDFPrivio" in the
//  system Share Sheet. Receives PDFs and images via NSItemProvider,
//  copies them to the App Group's SharedExtensionDrop folder, and
//  opens the host app with a wake-up URL.
//
//  The host app's Flutter side polls SharedExtensionDrop on every
//  AppLifecycleState.resumed (via ShareExtensionBridge MethodChannel),
//  moves each file into Documents/Inbox, and surfaces the action
//  sheet that lets the user pick a tool (Sign / Redact / etc.).
//
//  Pure Swift — no Pods, no Flutter framework dependency. That's
//  what kept the receive_sharing_intent-based attempt from building.
//

import MobileCoreServices
import Social
import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private let appGroupId = "group.com.erekstudio.pdfprivio"
    private let dropFolderName = "SharedExtensionDrop"
    private let wakeUpScheme = "pdfprivio"
    private let wakeUpHost = "share"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // We don't want a visible UI — process attachments then dismiss.
        view.alpha = 0
        processAttachments()
    }

    private func processAttachments() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            finish(savedCount: 0)
            return
        }
        let providers = item.attachments ?? []
        if providers.isEmpty {
            finish(savedCount: 0)
            return
        }

        let group = DispatchGroup()
        var savedPaths: [String] = []

        for provider in providers {
            let typeId = resolveTypeIdentifier(for: provider)
            guard let typeId = typeId else { continue }
            group.enter()
            handleAttachment(provider: provider, typeId: typeId) { path in
                if let p = path { savedPaths.append(p) }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finish(savedCount: savedPaths.count)
        }
    }

    /// Pick the highest-priority type the provider can give us. PDF
    /// takes precedence over generic file/image so a PDF shared from
    /// Mail doesn't get treated as a "data" blob.
    private func resolveTypeIdentifier(for provider: NSItemProvider) -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return UTType.pdf.identifier
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return UTType.image.identifier
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return UTType.fileURL.identifier
        }
        return nil
    }

    private func handleAttachment(
        provider: NSItemProvider,
        typeId: String,
        completion: @escaping (String?) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] item, _ in
            guard let self = self else {
                completion(nil)
                return
            }
            var fileURL: URL?
            if let i = item as? URL {
                fileURL = i
            } else if let i = item as? UIImage {
                fileURL = self.saveImageToTemp(i)
            } else if let i = item as? Data {
                let ext: String
                if typeId == UTType.pdf.identifier {
                    ext = "pdf"
                } else if typeId == UTType.image.identifier {
                    ext = "jpg"
                } else {
                    ext = "bin"
                }
                fileURL = self.saveDataToTemp(i, ext: ext)
            }
            guard let src = fileURL else {
                completion(nil)
                return
            }
            let saved = self.copyToAppGroup(src)
            completion(saved?.path)
        }
    }

    private func saveImageToTemp(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        try? data.write(to: url)
        return url
    }

    private func saveDataToTemp(_ data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(ext)")
        try? data.write(to: url)
        return url
    }

    private func copyToAppGroup(_ src: URL) -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
        else {
            return nil
        }
        let drop = container.appendingPathComponent(dropFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: drop,
            withIntermediateDirectories: true
        )
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let dest = drop.appendingPathComponent("\(stamp)_\(src.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private func finish(savedCount: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if savedCount > 0 {
                self.openHostApp()
            }
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    /// Open the host app via our custom URL scheme. iOS routes the
    /// URL to FlutterAppDelegate.application(_:open:options:); our
    /// AppDelegate override forwards it to a MethodChannel so the
    /// Flutter side can drain the drop folder.
    @objc private func openHostApp() {
        guard let url = URL(string: "\(wakeUpScheme)://\(wakeUpHost)") else { return }
        var responder: UIResponder? = self
        while responder != nil {
            if let app = responder as? UIApplication {
                _ = app.perform(#selector(openURL(_:)), with: url)
                return
            }
            responder = responder?.next
        }
    }

    // iOS deprecates application.open(_:) inside extensions — this
    // selector-based trick still works and is the documented pattern
    // for share-extension → host-app deep links.
    @objc func openURL(_ url: URL) {}
}
