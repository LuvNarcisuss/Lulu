import CryptoKit
import PDFKit
import UIKit

@MainActor
final class SettingsController: TravelScreen {
    override func render() {
        super.render(); title = "Settings"
        content.addArrangedSubview(text("Your travel essentials", 30, display: true))
        content.addArrangedSubview(action("Edit profile", icon: "icon-edit", filled: false) { [weak self] in guard let self else { return }; self.push(EditProfileController(store: self.store)) })
        content.addArrangedSubview(action("Blocked profiles", icon: "icon-block", filled: false) { [weak self] in guard let self else { return }; self.push(SafetyHistoryController(store: self.store, reports: false)) })
        content.addArrangedSubview(action("Your reports", icon: "icon-report", filled: false) { [weak self] in guard let self else { return }; self.push(SafetyHistoryController(store: self.store, reports: true)) })
        content.addArrangedSubview(action("Hidden guides", icon: "icon-location", filled: false) { [weak self] in
            guard let self else { return }
            self.push(HiddenGuidesController(store: self.store))
        })
        content.addArrangedSubview(action("Media credits", icon: "icon-camera", filled: false) { [weak self] in guard let self else { return }; self.push(MediaCreditsController(store: self.store)) })
        for document in TravelAgreement.allCases {
            content.addArrangedSubview(action(document.title, icon: "icon-globe", filled: false) { [weak self] in
                guard let self else { return }
                self.push(AgreementController(store: self.store, document: document))
            })
        }
        content.addArrangedSubview(action("Log out", icon: "icon-profile", filled: false) { [weak self] in
            guard let self else { return }
            self.confirm("Log out of this account?", destructive: true) {
                self.run { try await self.store.signOut() }
            }
        })
        let deletionConfigured = Bundle.main.url(forResource: "BackendConfig", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Record.self, from: $0) }?.bool("accountDeletionDeployed") ?? false
        let deleteButton = action("Delete my account", icon: "icon-trash", filled: false) { [weak self] in
            guard let self else { return }
            self.confirm("Permanently delete your account?", message: "Your profile, private activity and uploads will be deleted. Published videos and guides will stay in the community without your profile. This cannot be undone.", destructive: true, actionTitle: "Delete account") {
                self.run { try await self.store.deleteAccount() }
            }
        }
        deleteButton.isEnabled = deletionConfigured
        content.addArrangedSubview(deleteButton)
        if !deletionConfigured { content.addArrangedSubview(text("Account deletion is temporarily unavailable.", 14, color: Palette.muted)) }
    }
}

@MainActor
final class SafetyHistoryController: TravelScreen {
    private let reports: Bool
    init(store: TravelStore, reports: Bool) { self.reports = reports; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func render() {
        super.render(); title = reports ? "Your reports" : "Blocked profiles"
        let rows = store.rows(reports ? "reports" : "blocks").filter { $0.string(reports ? "user_id" : "blocker_id") == store.userID }
        if rows.isEmpty { content.addArrangedSubview(text(reports ? "You have not submitted any reports." : "You have not blocked any profiles.", color: Palette.muted)) }
        for row in rows {
            if reports {
                content.addArrangedSubview(card([text(row.string("reason"), 22, display: true), text(row.string("details"), color: Palette.muted), text("\(row.string("target_kind")) · \(row.string("created_at"))", 12, color: Palette.muted),
                    action("Withdraw report", icon: "icon-trash", filled: false) { [weak self] in
                        guard let self else { return }
                        self.confirm("Withdraw report?", message: "The report will be removed from your submitted reports.") {
                            self.run { try await self.store.perform("safety.unreport", ["report_id": .string(row.id)]) }
                        }
                    }
                ]))
            } else {
                let id = row.string("blocked_id")
                content.addArrangedSubview(card([text(memberName(id, store: store), 22, display: true), text(id, 11, color: Palette.muted),
                    action("View profile", icon: "icon-profile", filled: false) { [weak self] in guard let self else { return }; self.push(PublicProfileController(store: self.store, profileID: id)) },
                    action("Unblock", icon: "icon-block", filled: false) { [weak self] in
                        guard let self else { return }
                        self.confirm("Unblock profile?", message: "This profile may interact with you again.") {
                            self.run { try await self.store.perform("safety.block", ["profile_id": .string(id), "enabled": .bool(false)]) }
                        }
                    }
                ]))
            }
        }
    }
}

private final class HiddenGuidesController: TravelScreen {
    override func render() {
        super.render()
        title = "Hidden guides"
        guard store.hasGuideVisibility else {
            content.addArrangedSubview(text("Your hidden guides could not be loaded.", color: Palette.muted))
            content.addArrangedSubview(action("Retry", icon: "icon-refresh", filled: false) { [weak self] in
                guard let self else { return }
                self.run { try await self.store.refresh() }
            })
            return
        }
        let places = store.rows("places").filter { store.hiddenPlaceIDs.contains($0.id) }
        if places.isEmpty {
            content.addArrangedSubview(text("You have no hidden guides.", color: Palette.muted))
        }
        for place in places {
            content.addArrangedSubview(card([
                text(place.string("name"), 22, display: true),
                action("Restore guide", icon: "icon-refresh", filled: false) { [weak self] in
                    guard let self else { return }
                    self.run {
                        try await self.store.perform("safety.hide_place", ["place_id": .string(place.id), "enabled": .bool(false)])
                    }
                }
            ]))
        }
    }
}

enum TravelAgreement: String, CaseIterable {
    case terms, privacy

    var title: String { self == .terms ? "Terms of Service" : "Privacy Policy" }
    var resource: String { self == .terms ? "TermsOfService" : "PrivacyPolicy" }
    var configurationKey: String { rawValue + "URL" }
    var checksumKey: String { rawValue + "SHA256" }
    var consentLink: URL { URL(string: "lulu-agreement://\(rawValue)")! }
}

@MainActor
final class AgreementController: TravelScreen {
    private let agreement: TravelAgreement
    private var built = false
    private var request: Task<Void, Never>?
    private let status = text("Loading agreement…", color: Palette.muted)
    private let pdf = PDFView()
    init(store: TravelStore, document: TravelAgreement) {
        agreement = document
        super.init(store: store)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func render() {
        guard !built else { return }
        super.render(); built = true; title = agreement.title
        content.addArrangedSubview(status)
        pdf.autoScales = true; pdf.backgroundColor = Palette.paper
        pdf.heightAnchor.constraint(equalToConstant: 640).isActive = true
        pdf.accessibilityLabel = agreement.title
        content.addArrangedSubview(pdf)
        content.addArrangedSubview(action("Retry online copy", icon: "icon-refresh", filled: false) { [weak self] in self?.loadAgreement() })
        loadAgreement()
    }
    private func loadAgreement() {
        request?.cancel()
        let bundled = Bundle.main.url(forResource: agreement.resource, withExtension: "pdf")
        let configURL = Bundle.main.url(forResource: "BackendConfig", withExtension: "json")
        let values = configURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let raw = values?[agreement.configurationKey] as? String ?? ""
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil,
              let checksum = values?[agreement.checksumKey] as? String else {
            if let bundled, let document = PDFDocument(url: bundled) { pdf.document = document; status.text = "Bundled agreement" }
            else { status.text = "This agreement is not configured yet. Operator details must be confirmed before release." }
            return
        }
        status.text = "Loading current agreement…"
        request = Task { [weak self] in
            do {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 20
                let session = URLSession(configuration: config)
                defer { session.invalidateAndCancel() }
                let (file, response) = try await session.download(from: url)
                defer { try? FileManager.default.removeItem(at: file) }
                guard !Task.isCancelled else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      response.url == url,
                      response.mimeType == "application/pdf",
                      let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= 8 * 1024 * 1024 else { throw PhotoImportError.unreadable }
                let data = try Data(contentsOf: file)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest == checksum, let document = PDFDocument(data: data), document.pageCount > 0 else {
                    throw PhotoImportError.unreadable
                }
                self?.pdf.document = document
                self?.status.text = "Current published agreement"
            } catch {
                guard !Task.isCancelled else { return }
                if let bundled, let document = PDFDocument(url: bundled) { self?.pdf.document = document; self?.status.text = "Offline bundled agreement" }
                else { self?.status.text = "The agreement could not be loaded. Please try again." }
            }
        }
    }
    deinit { request?.cancel() }
}

@MainActor
final class MediaCreditsController: TravelScreen {
    override func render() {
        super.render(); title = "Media credits"
        content.addArrangedSubview(text("Stories have sources", 30, display: true))
        content.addArrangedSubview(text("Destination descriptions are independently written. Footage and photographs retain their original source and author credits. Editorial publishers use licensed illustrative portraits, not member identities or endorsements. Their display counts include fixed illustrative baselines; real member interactions are stored separately.", color: Palette.muted))
        for clip in store.rows("clips") {
            credit(clip.string("title"), author: clip.string("author"), source: clip.string("source_url"))
        }
        for place in store.rows("places") { credit(place.string("name"), author: "Destination source", source: place.string("source_url")) }
        if let file = Bundle.main.url(forResource: "MediaCredits", withExtension: "json"),
           let data = try? Data(contentsOf: file), let metadata = try? JSONDecoder().decode(Record.self, from: data) {
            content.addArrangedSubview(text("Photography credits", 26, display: true))
            for photo in metadata.records("photographs") {
                credit(photo.string("title", fallback: photo.string("path").split(separator: "/").last.map(String.init) ?? "Destination photograph"), author: photo.string("author", fallback: "See source for creator credits"), source: photo.string("source_url"))
                if let license = URL(string: photo.string("license_url")), license.scheme == "https" {
                    content.addArrangedSubview(action(photo.string("license", fallback: "Photo license"), icon: "icon-globe", filled: false) { UIApplication.shared.open(license) })
                }
            }
        }
        content.addArrangedSubview(text("Interface illustrations and icons were generated for this application. Typography uses the packaged Kalam and Fraunces fonts; license files are included with the application resources.", 14, color: Palette.muted))
    }
    private func credit(_ title: String, author: String, source: String) {
        var views: [UIView] = [text(title, 21, display: true), text(author, 14, color: Palette.muted)]
        if let url = URL(string: source), url.scheme == "https" {
            views.append(action("View original source", icon: "icon-globe", filled: false) { UIApplication.shared.open(url) })
        }
        content.addArrangedSubview(card(views))
    }
}
