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
    private let brandTeal = UIColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1)

    // Visual parity with PDFPrivioShare/ShareViewController. Same card
    // layout, same header, same row style — but only one row (Sign),
    // because the user already declared their intent by tapping
    // "Quick Sign" in the Edit Actions row.
    private let card = UIView()
    private let contentStack = UIStackView()
    private var pendingOpenURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        installShell()
        showLoadingState()
        processAttachments()
    }

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

    private func showLoadingState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clearContent()
            let icon = UIImageView(image: UIImage(
                systemName: "signature",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 36, weight: .semibold)))
            icon.tintColor = self.brandTeal
            icon.contentMode = .scaleAspectFit
            icon.heightAnchor.constraint(equalToConstant: 40).isActive = true

            let title = UILabel()
            title.text = "Queuing for Quick Sign…"
            title.font = .systemFont(ofSize: 17, weight: .semibold)
            title.textAlignment = .center

            let detail = UILabel()
            detail.text = "Reading the PDF"
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

    private func showSignState(fileName: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.clearContent()
            self.contentStack.alignment = .fill

            // Same header as ShareViewController so the two extensions
            // read as one consistent feature, not two divergent surfaces.
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
            nameLabel.text = fileName ?? "Shared PDF"
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

            let openWithLabel = UILabel()
            openWithLabel.text = "OPEN WITH"
            openWithLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            openWithLabel.textColor = .tertiaryLabel
            self.contentStack.setCustomSpacing(18, after: headerStack)
            self.contentStack.addArrangedSubview(openWithLabel)

            // The one row Quick Sign needs — Sign. Same visual treatment
            // as ShareViewController's rows, no chevron, single-tool list.
            let signTool = QuickSignToolRow.Tool(
                id: "sign",
                title: "Sign",
                subtitle: "Draw and place a signature",
                symbolName: "signature")
            let row = QuickSignToolRow(tool: signTool, brandTeal: self.brandTeal)
            row.addTarget(self, action: #selector(self.signRowTapped),
                          for: .touchUpInside)
            self.contentStack.addArrangedSubview(row)

            // Cancel
            let cancel = UIButton(type: .system)
            cancel.setTitle("Cancel", for: .normal)
            cancel.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            cancel.setTitleColor(.secondaryLabel, for: .normal)
            cancel.addTarget(self, action: #selector(self.cancelTapped),
                             for: .touchUpInside)
            self.contentStack.setCustomSpacing(8, after: row)
            self.contentStack.addArrangedSubview(cancel)
        }
    }

    @objc private func signRowTapped() {
        if let defaults = UserDefaults(suiteName: appGroupId) {
            defaults.set("sign", forKey: preferredActionKey)
        }
        if let url = pendingOpenURL ?? URL(string:
            "\(wakeUpScheme)://\(wakeUpHost)") {
            openHostApp(url)
        }
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
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments,
              !providers.isEmpty
        else {
            finish(savedPaths: [])
            return
        }

        // Quick Sign only makes sense for PDFs — Apple's Activation
        // Rule already filters non-PDFs, but be defensive.
        let pdfProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }

        let group = DispatchGroup()
        var savedPaths: [String] = []
        for provider in pdfProviders {
            group.enter()
            handleAttachment(provider) { path in
                if let p = path { savedPaths.append(p) }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finish(savedPaths: savedPaths)
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
                title: "No PDF found",
                detail: "The attachment didn't contain a readable PDF.")
            scheduleAutoDismiss(after: 2.0)
            return
        }

        pendingOpenURL = URL(string: "\(wakeUpScheme)://\(wakeUpHost)")

        var displayName: String?
        if let first = savedPaths.first {
            let base = (first as NSString).lastPathComponent
            if let underscore = base.firstIndex(of: "_") {
                displayName = String(base[base.index(after: underscore)...])
            } else {
                displayName = base
            }
        }
        showSignState(fileName: displayName)
    }

    private func scheduleAutoDismiss(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
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

// MARK: - QuickSignToolRow

/// Visual twin of ShareViewController.ToolRowControl — same layout, no
/// chevron, single tap target. Kept here because Swift extensions can't
/// see private types declared in the host app's compilation unit.
private final class QuickSignToolRow: UIControl {
    struct Tool {
        let id: String
        let title: String
        let subtitle: String
        let symbolName: String
    }

    let tool: Tool

    init(tool: Tool, brandTeal: UIColor) {
        self.tool = tool
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14

        let iconView = UIImageView(image: UIImage(
            systemName: tool.symbolName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 20, weight: .semibold)))
        iconView.translatesAutoresizingMaskIntoConstraints = false
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
        stack.isUserInteractionEnabled = false
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
