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
    private let preferredActionKey = "pdfprivio.preferredShareAction"
    private let wakeUpScheme = "pdfprivio"
    private let wakeUpHost = "share"
    private let brandTeal = UIColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1)

    // The card swaps between three states managed by setCardContent():
    //   1. Loading — spinner + "Saving…" while we process the attachment
    //   2. Error   — red icon + reason + auto-dismiss (App Group missing,
    //                no PDF found, etc.)
    //   3. Picker  — file confirmation + the list of tools the user can
    //                hand off to Privio
    // Each Tool below maps to a `pdfprivio.preferredShareAction` value
    // that the host app's SharedFileActionSheet already consumes (see
    // _routeForAction in lib/widgets/shared_file_action_sheet.dart).
    fileprivate struct Tool {
        let id: String?      // nil = no preferred action, fall through to chooser
        let title: String
        let subtitle: String
        let symbolName: String
    }

    private let tools: [Tool] = [
        Tool(id: "sign", title: "Sign", subtitle: "Draw and place a signature",
             symbolName: "signature"),
        Tool(id: "redact", title: "Redact",
             subtitle: "Black out sensitive text",
             symbolName: "rectangle.dashed"),
        Tool(id: "merge", title: "Merge with another PDF",
             subtitle: "Combine multiple files",
             symbolName: "rectangle.stack"),
        Tool(id: "ocr", title: "OCR",
             subtitle: "Make a scanned PDF searchable",
             symbolName: "doc.text.magnifyingglass"),
        Tool(id: "pii", title: "Find sensitive data",
             subtitle: "SSN, EIN, cards, emails, phones",
             symbolName: "shield"),
        Tool(id: nil, title: "Other tools…",
             subtitle: "Open Privio for the full menu",
             symbolName: "ellipsis.circle"),
    ]

    private let card = UIView()
    private let contentStack = UIStackView()
    private var pendingOpenURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        installShell()
        showLoadingState()
        processAttachments()
    }

    // MARK: - Shell + state swapping

    private func installShell() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentStack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 320),
            card.heightAnchor.constraint(lessThanOrEqualTo:
                view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.88),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
    }

    private func clearContent() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    // MARK: - States

    private func showLoadingState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clearContent()
            let icon = UIImageView(image: UIImage(
                systemName: "arrow.down.circle",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 36, weight: .semibold)))
            icon.tintColor = self.brandTeal
            icon.contentMode = .scaleAspectFit
            icon.heightAnchor.constraint(equalToConstant: 40).isActive = true

            let title = UILabel()
            title.text = "Saving to Privio…"
            title.font = .systemFont(ofSize: 17, weight: .semibold)
            title.textAlignment = .center

            let detail = UILabel()
            detail.text = "Reading attachment"
            detail.font = .systemFont(ofSize: 13)
            detail.textColor = .secondaryLabel
            detail.textAlignment = .center

            self.contentStack.alignment = .center
            self.contentStack.addArrangedSubview(icon)
            self.contentStack.addArrangedSubview(title)
            self.contentStack.addArrangedSubview(detail)
        }
    }

    private func showErrorState(title: String, detail: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clearContent()
            let icon = UIImageView(image: UIImage(
                systemName: "xmark.octagon.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 36, weight: .semibold)))
            icon.tintColor = .systemRed
            icon.contentMode = .scaleAspectFit
            icon.heightAnchor.constraint(equalToConstant: 40).isActive = true

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0

            let detailLabel = UILabel()
            detailLabel.text = detail
            detailLabel.font = .systemFont(ofSize: 13)
            detailLabel.textColor = .secondaryLabel
            detailLabel.textAlignment = .center
            detailLabel.numberOfLines = 0

            self.contentStack.alignment = .center
            self.contentStack.addArrangedSubview(icon)
            self.contentStack.addArrangedSubview(titleLabel)
            self.contentStack.addArrangedSubview(detailLabel)
        }
    }

    private func showPickerState(fileName: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clearContent()
            self.contentStack.alignment = .fill

            // Header: small green check + file name + "Saved to Privio"
            let checkIcon = UIImageView(image: UIImage(
                systemName: "checkmark.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 28, weight: .semibold)))
            checkIcon.tintColor = self.brandTeal
            checkIcon.contentMode = .scaleAspectFit

            let savedTitle = UILabel()
            savedTitle.text = "Saved to Privio"
            savedTitle.font = .systemFont(ofSize: 16, weight: .semibold)

            let nameLabel = UILabel()
            nameLabel.text = fileName ?? "Shared file"
            nameLabel.font = .systemFont(ofSize: 12)
            nameLabel.textColor = .secondaryLabel
            nameLabel.lineBreakMode = .byTruncatingMiddle

            let textStack = UIStackView(arrangedSubviews: [savedTitle, nameLabel])
            textStack.axis = .vertical
            textStack.spacing = 2

            let headerStack = UIStackView(
                arrangedSubviews: [checkIcon, textStack])
            headerStack.axis = .horizontal
            headerStack.alignment = .center
            headerStack.spacing = 12
            checkIcon.widthAnchor.constraint(equalToConstant: 32).isActive = true
            self.contentStack.addArrangedSubview(headerStack)

            // Section label
            let openWithLabel = UILabel()
            openWithLabel.text = "OPEN WITH"
            openWithLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            openWithLabel.textColor = .tertiaryLabel
            self.contentStack.setCustomSpacing(18, after: headerStack)
            self.contentStack.addArrangedSubview(openWithLabel)

            // Tool rows
            for tool in self.tools {
                self.contentStack.addArrangedSubview(self.makeToolRow(tool))
            }

            // Cancel
            let cancel = UIButton(type: .system)
            cancel.setTitle("Cancel", for: .normal)
            cancel.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            cancel.setTitleColor(.secondaryLabel, for: .normal)
            cancel.addTarget(self, action: #selector(self.cancelTapped),
                             for: .touchUpInside)
            self.contentStack.setCustomSpacing(8, after:
                self.contentStack.arrangedSubviews.last!)
            self.contentStack.addArrangedSubview(cancel)
        }
    }

    private func makeToolRow(_ tool: Tool) -> UIControl {
        let row = ToolRowControl(tool: tool, brandTeal: brandTeal)
        row.addTarget(self, action: #selector(toolRowTapped(_:)),
                      for: .touchUpInside)
        return row
    }

    @objc private func toolRowTapped(_ sender: ToolRowControl) {
        let tool = sender.tool
        // Hand the preferred action to the host via App Group UserDefaults
        // so SharedFileActionSheet routes straight to that tool instead of
        // showing the chooser. nil id = "Other tools…" → leave the key
        // unset and let the chooser open.
        if let actionId = tool.id,
           let defaults = UserDefaults(suiteName: appGroupId) {
            defaults.set(actionId, forKey: preferredActionKey)
        }
        if let url = pendingOpenURL ?? URL(string:
            "\(wakeUpScheme)://\(wakeUpHost)") {
            openHostApp(url)
        }
        // Give iOS a beat to honour the URL hand-off before we dismiss
        // the extension. Calling completeRequest synchronously seemed to
        // cancel the open on some iOS versions — by the time the URL
        // handler kicked in, the extension was already torn down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.extensionContext?.completeRequest(
                returningItems: nil, completionHandler: nil)
        }
    }

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil,
                                          completionHandler: nil)
    }

    private func processAttachments() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            finish(savedPaths: [])
            return
        }
        let providers = item.attachments ?? []
        if providers.isEmpty {
            finish(savedPaths: [])
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
            self?.finish(savedPaths: savedPaths)
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

    private func finish(savedPaths: [String]) {
        let groupOk = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId) != nil

        if !groupOk {
            showErrorState(
                title: "App Group unavailable",
                detail: "Privio's shared storage couldn't be opened.\n" +
                        "Reinstall the app or contact support.")
            scheduleAutoDismiss(after: 2.0)
            return
        }
        if savedPaths.isEmpty {
            showErrorState(
                title: "No file shared",
                detail: "Couldn't read the attachment. Try sharing the " +
                        "PDF directly instead of a link.")
            scheduleAutoDismiss(after: 2.0)
            return
        }

        pendingOpenURL = URL(string: "\(wakeUpScheme)://\(wakeUpHost)")

        // Strip the timestamp prefix the extension added so the display
        // matches what the user shared. e.g. "1779280063424_Dekont.pdf"
        // → "Dekont.pdf".
        var displayName: String?
        if let first = savedPaths.first {
            let base = (first as NSString).lastPathComponent
            if let underscore = base.firstIndex(of: "_") {
                displayName = String(base[base.index(after: underscore)...])
            } else {
                displayName = base
            }
        }
        showPickerState(fileName: displayName)
    }

    private func scheduleAutoDismiss(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
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

// MARK: - ToolRowControl

/// One tappable row in the tool picker. Custom UIControl subclass so the
/// whole row gets a single touch target + a press-down highlight,
/// instead of fighting with nested UIButton hit-testing.
private final class ToolRowControl: UIControl {
    let tool: ShareViewController.Tool
    private let iconView = UIImageView()

    init(tool: ShareViewController.Tool, brandTeal: UIColor) {
        self.tool = tool
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(
            systemName: tool.symbolName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 20, weight: .semibold))
        iconView.tintColor = brandTeal
        iconView.contentMode = .scaleAspectFit

        let title = UILabel()
        title.text = tool.title
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .label

        let subtitle = UILabel()
        subtitle.text = tool.subtitle
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [title, subtitle])
        labels.axis = .vertical
        labels.spacing = 1

        let stack = UIStackView(arrangedSubviews: [iconView, labels])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false  // let the UIControl handle taps
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.alpha = self.isHighlighted ? 0.7 : 1
            }
        }
    }
}
