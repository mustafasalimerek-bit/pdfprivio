//
//  QuickSignViewController.swift
//  PDFPrivioQuickSign
//
//  Action Extension that appears in the system Share Sheet's
//  "Actions" row as "Quick Sign with PDFPrivio". Same drop-folder
//  mechanics as PDFPrivioShare — the difference is the URL we fire
//  carries `?action=sign`, and ShareIntentService on the Flutter
//  side skips the action chooser and routes the user straight to
//  the Sign tool with the PDF pre-loaded.
//
//  Pure Swift; no Pods, no Flutter framework dependency. Mirrors
//  PDFPrivioShare's pattern so the two appex's stay maintainable
//  side-by-side.
//

import MobileCoreServices
import Social
import UIKit
import UniformTypeIdentifiers

class QuickSignViewController: UIViewController {
    private let appGroupId = "group.com.erekstudio.pdfprivio"
    private let dropFolderName = "SharedExtensionDrop"
    private let preferredActionKey = "pdfprivio.preferredShareAction"
    private let wakeUpScheme = "pdfprivio"
    private let wakeUpHost = "share"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.alpha = 0
        processAttachments()
    }

    private func processAttachments() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments,
              !providers.isEmpty
        else {
            finish(savedCount: 0)
            return
        }

        // Quick Sign only makes sense for PDFs — Apple's Activation
        // Rule already filters non-PDFs, but be defensive.
        let pdfProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }

        let group = DispatchGroup()
        var savedCount = 0
        for provider in pdfProviders {
            group.enter()
            handleAttachment(provider) { path in
                if path != nil { savedCount += 1 }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finish(savedCount: savedCount)
        }
    }

    private func handleAttachment(
        _ provider: NSItemProvider,
        completion: @escaping (String?) -> Void
    ) {
        provider.loadItem(
            forTypeIdentifier: UTType.pdf.identifier,
            options: nil
        ) { [weak self] item, _ in
            guard let self = self else {
                completion(nil)
                return
            }
            var fileURL: URL?
            if let i = item as? URL {
                fileURL = i
            } else if let i = item as? Data {
                fileURL = self.saveDataToTemp(i)
            }
            guard let src = fileURL else {
                completion(nil)
                return
            }
            let dest = self.copyToAppGroup(src)
            completion(dest?.path)
        }
    }

    private func saveDataToTemp(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
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
        if savedCount > 0 {
            // Tell ShareIntentService which tool to route to — bypasses
            // the chooser sheet so "Quick Sign" actually feels quick.
            if let defaults = UserDefaults(suiteName: appGroupId) {
                defaults.set("sign", forKey: preferredActionKey)
            }
            if let url = URL(string: "\(wakeUpScheme)://\(wakeUpHost)") {
                openHostApp(url)
            }
        }
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    /// Wake the host app via the `pdfprivio://share` URL scheme. See
    /// the matching method on ShareViewController for the full rationale
    /// — extensionContext.open returns success=false for action
    /// extensions, the only iOS-17/18 reliable channel is the
    /// responder-chain selector trick with `responds(to:)` (not the
    /// type-cast version, which silently fails because the UIKit
    /// proxy isn't a UIApplication subclass).
    private func openHostApp(_ url: URL) {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector) {
                _ = r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }
}
