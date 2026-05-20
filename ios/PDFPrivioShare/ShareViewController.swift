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

    // Visible diagnostic UI — replaces the invisible (alpha=0) flow we
    // were using before. iOS 17+ blocks programmatic host-app launches
    // from share extensions, so the only reliable wake-up is the user
    // opening Privio manually. The card tells them the save succeeded
    // (or shows the exact failure mode) so we can finally see what's
    // happening on real-device builds instead of guessing.
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let iconView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        installStatusCard(title: "Saving to Privio…", detail: "Reading attachment")
        processAttachments()
    }

    private func installStatusCard(title: String, detail: String) {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        let card = UIView()
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 18
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1)
        iconView.image = UIImage(
            systemName: "arrow.down.circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold))
        iconView.contentMode = .scaleAspectFit

        statusLabel.text = title
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0

        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [iconView, statusLabel, detailLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 280),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            iconView.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func updateStatus(success: Bool?, title: String, detail: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = title
            self.detailLabel.text = detail
            if let success = success {
                self.iconView.image = UIImage(
                    systemName: success ? "checkmark.circle.fill" : "xmark.octagon.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold))
                self.iconView.tintColor = success
                    ? UIColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1)
                    : .systemRed
            }
        }
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
        let groupOk = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId) != nil

        let title: String
        let detail: String
        let success: Bool
        if !groupOk {
            success = false
            title = "App Group unavailable"
            detail = "Privio's shared storage couldn't be opened.\n" +
                     "Reinstall the app or contact support."
        } else if savedCount == 0 {
            success = false
            title = "No file shared"
            detail = "Couldn't read the attachment. Try sharing the PDF " +
                     "directly instead of a link."
        } else {
            success = true
            title = "Saved to Privio"
            detail = "Open Privio to keep going."
        }
        updateStatus(success: success, title: title, detail: detail)

        if success, let url = URL(string:
            "\(self.wakeUpScheme)://\(self.wakeUpHost)") {
            // Best-effort wake-up — iOS 17+ usually blocks programmatic
            // host-app launches from share extensions, so we don't rely
            // on it. The card above tells the user to switch to Privio
            // manually; the file is already in the App Group so the
            // host app's resume-drain catches it either way.
            openHostApp(url)
        }

        // Keep the status card on screen for a beat so the user can
        // actually read it before the share sheet pops back to the
        // host (WhatsApp / Mail / etc.).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.extensionContext?.completeRequest(
                returningItems: nil, completionHandler: nil)
        }
    }

    /// Wake the host app via the shared `pdfprivio://share` URL scheme.
    ///
    /// `NSExtensionContext.open(_:)` looks promising in the docs but
    /// Apple's small print is "each extension point decides whether to
    /// support this method" — in practice, share/action extensions on
    /// iOS 17+ get `success = false` and nothing fires. That's what
    /// killed the apps-row tap on build 20.
    ///
    /// The pattern that actually works (1Password, Bear, Drafts) is to
    /// walk the responder chain and call `openURL:` via the ObjC
    /// runtime on whichever object responds to it. UIKit installs a
    /// private UIApplication-proxy in the extension context that
    /// responds to that selector, but it isn't a UIApplication
    /// subclass — so the old `responder as? UIApplication` cast
    /// silently dropped through the loop. `responds(to:)` is
    /// class-agnostic and finds the proxy.
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
