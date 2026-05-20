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

    // Mirror of ShareViewController's card. See that file for the full
    // rationale — iOS 17+ blocks programmatic host-app launches from
    // extensions, but a user-initiated tap on a button rendered inside
    // the extension's own UI IS still honoured. The "Open Privio" CTA
    // below is what closes the share→app loop.
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let iconView = UIImageView()
    private let openButton = UIButton(type: .system)
    private var pendingOpenURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        installStatusCard(title: "Queuing for Quick Sign…",
                          detail: "Reading the PDF")
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
            systemName: "signature",
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

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.setTitle("Sign in Privio  →", for: .normal)
        openButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        openButton.setTitleColor(.white, for: .normal)
        openButton.backgroundColor = UIColor(
            red: 0.06, green: 0.46, blue: 0.43, alpha: 1)
        openButton.layer.cornerRadius = 14
        openButton.contentEdgeInsets = UIEdgeInsets(
            top: 12, left: 22, bottom: 12, right: 22)
        openButton.isHidden = true
        openButton.addTarget(self,
                             action: #selector(openButtonTapped),
                             for: .touchUpInside)

        let stack = UIStackView(
            arrangedSubviews: [iconView, statusLabel, detailLabel, openButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(16, after: detailLabel)
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

    @objc private func openButtonTapped() {
        guard let url = pendingOpenURL else {
            extensionContext?.completeRequest(
                returningItems: nil, completionHandler: nil)
            return
        }
        openHostApp(url)
        extensionContext?.completeRequest(
            returningItems: nil, completionHandler: nil)
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
            title = "No PDF found"
            detail = "The attachment didn't contain a readable PDF."
        } else {
            success = true
            // Tell ShareIntentService which tool to route to — bypasses
            // the chooser sheet so "Quick Sign" actually feels quick.
            if let defaults = UserDefaults(suiteName: appGroupId) {
                defaults.set("sign", forKey: preferredActionKey)
            }
            title = "Ready for Quick Sign"
            detail = "Tap below to open the Sign tool."
        }
        updateStatus(success: success, title: title, detail: detail)

        if success,
           let url = URL(string: "\(wakeUpScheme)://\(wakeUpHost)") {
            pendingOpenURL = url
            DispatchQueue.main.async { [weak self] in
                self?.openButton.isHidden = false
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.extensionContext?.completeRequest(
                returningItems: nil, completionHandler: nil)
        }
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
