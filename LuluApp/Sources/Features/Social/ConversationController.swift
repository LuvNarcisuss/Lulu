import PhotosUI
import UIKit

@MainActor
final class ConversationController: TravelScreen, UITextViewDelegate, PHPickerViewControllerDelegate, UIScrollViewDelegate {
    private let conversationID: String
    private let messages = column()
    private let composer = multilineInput("Message", height: 90)
    private let replyLabel = text("", 13, color: Palette.teal)
    private let attachmentLabel = text("", 13, color: Palette.muted)
    private let stateLabel = text("", 13, color: Palette.muted)
    private var sendButton: UIButton?
    private var built = false
    private var replyID: String?
    private var attachment: Data?
    private var uploadedPath: String?
    private var sending = false
    private var photoLoading = false
    private var photoGeneration = UUID()
    private var savedDraft = ""
    private var draftTask: Task<Void, Never>?
    private var draftGeneration = 0
    private var saveInFlight = false
    private var pendingID = UUID().uuidString
    private var lastReadMessage = ""
    private var accountID = ""
    private let composerPanel = column([], spacing: 8)
    private var newMessagesButton: UIButton?
    private let policyLabel = text("", 12, color: Palette.muted)
    private var renderedMessages: [Record] = []
    private var hasRenderedMessages = false
    private var staysAtBottom = true
    private var lastViewportHeight: CGFloat = 0

    init(store: TravelStore, conversationID: String) { self.conversationID = conversationID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func render() {
        if !built {
            super.render(); built = true; accountID = store.userID; refreshWhileEditing = true
            savedDraft = chatPreference(conversationID, store: store).string("draft")
            composer.text = savedDraft
            composer.delegate = self
            content.addArrangedSubview(line([
                action("Travelers", icon: "icon-group", filled: false) { [weak self] in self?.showMembers() },
                iconButton("icon-video", label: "Open video call camera preview") { [weak self] in
                    guard let self else { return }
                    self.push(LocalVideoPreviewController(store: self.store))
                }
            ]))
            content.addArrangedSubview(policyLabel)
            content.addArrangedSubview(messages)
            scroll.delegate = self
            installComposer()

        }
        title = store.rows("conversations").first { $0.id == conversationID }.map { conversationName($0, store: store) } ?? "Conversation"
        updateMessages(); updateComposer()
    }

    private func installComposer() {
        let newMessages = action("New messages", icon: "icon-comment", filled: false) { [weak self] in
            self?.scrollToLatest(animated: !UIAccessibility.isReduceMotionEnabled)
        }
        newMessages.isHidden = true; newMessagesButton = newMessages
        composerPanel.addArrangedSubview(newMessages)
        composerPanel.addArrangedSubview(replyLabel)
        composerPanel.addArrangedSubview(attachmentLabel)
        composerPanel.addArrangedSubview(composer)
        composer.heightAnchor.constraint(equalToConstant: 90).isActive = true
        let send = action("Send", icon: "icon-send") { [weak self] in self?.send() }
        sendButton = send
        composerPanel.addArrangedSubview(line([
            iconButton("icon-photo", label: "Attach photo") { [weak self] in self?.pickPhoto() },
            iconButton("icon-close", label: "Clear reply and attachment") { [weak self] in
                guard let self, !self.sending else { return }
                self.replyID = nil; self.attachment = nil; self.uploadedPath = nil; self.pendingID = UUID().uuidString; self.updateComposer()
            }, send
        ]))
        composerPanel.addArrangedSubview(stateLabel)
        composerPanel.backgroundColor = Palette.paper
        composerPanel.isLayoutMarginsRelativeArrangement = true
        composerPanel.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        composerPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(composerPanel)
        for constraint in view.constraints where (constraint.firstItem as? UIScrollView) === scroll && constraint.firstAttribute == .bottom {
            constraint.isActive = false
        }
        NSLayoutConstraint.activate([
            composerPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerPanel.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: composerPanel.topAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scroll.bounds.height != lastViewportHeight {
            lastViewportHeight = scroll.bounds.height
            if staysAtBottom { scrollToLatest(animated: false) }
        }
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        staysAtBottom = isNearBottom
        if staysAtBottom {
            newMessagesButton?.isHidden = true
            markRead()
        }
    }
    private var isNearBottom: Bool {
        scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom >= scroll.contentSize.height - 100
    }
    private func scrollToLatest(animated: Bool) {
        view.layoutIfNeeded()
        let y = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        staysAtBottom = true
        scroll.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
        newMessagesButton?.isHidden = true
        markRead()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        markRead()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        draftTask?.cancel(); draftTask = nil
        persistDraft()
        photoGeneration = UUID()
        photoLoading = false
    }
    func textViewDidChange(_ textView: UITextView) {
        pendingID = UUID().uuidString
        draftGeneration += 1
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.persistDraft()
        }
    }
    private func persistDraft() {
        guard !saveInFlight, accountID == store.userID, store.isAuthenticated else { return }
        let value = composer.text ?? ""
        guard value != savedDraft else { return }
        guard value.count <= 2000 else { stateLabel.text = "Drafts can contain up to 2,000 characters."; return }
        saveInFlight = true
        let generation = draftGeneration
        Task { [self] in
            do {
                try await store.perform("chat.preferences", ["conversation_id": .string(conversationID), "draft": .string(value)])
                guard accountID == store.userID else { saveInFlight = false; return }
                savedDraft = value
                stateLabel.text = "Draft saved"
                saveInFlight = false
                if generation != draftGeneration || composer.text != value { persistDraft() }
            } catch {
                saveInFlight = false
                stateLabel.text = "Draft not saved: \(error.localizedDescription)"
            }
        }
    }
    private func updateComposer() {
        replyLabel.text = replyID == nil ? "" : "Replying to a message"
        replyLabel.isHidden = replyID == nil
        attachmentLabel.text = photoLoading ? "Preparing photo…" : attachment == nil ? "" : "Photo attached"
        attachmentLabel.isHidden = !photoLoading && attachment == nil
        updateMessagePolicy()
        sendButton?.isEnabled = !sending && !photoLoading
        sendButton?.setTitle(sending ? "Sending…" : "Send", for: .normal)
    }
    private func updateMessages() {
        let records = store.rows("messages").filter { $0.string("conversation_id") == conversationID }.sorted { $0.string("created_at") < $1.string("created_at") }
        guard !hasRenderedMessages || records != renderedMessages else { return }
        let wasNearBottom = !hasRenderedMessages || isNearBottom
        let previousIDs = Set(renderedMessages.map(\.id))
        let hasNewMessages = hasRenderedMessages && records.contains { !previousIDs.contains($0.id) }
        let priorOffset = scroll.contentOffset
        renderedMessages = records; hasRenderedMessages = true
        clearStack(messages)
        if records.isEmpty { messages.addArrangedSubview(card([text("A blank page for your travel plans", 23, display: true), text("Send the first message when you are ready.", color: Palette.muted)])) }
        for record in records {
            let own = record.string("sender_id") == store.userID
            var views: [UIView] = [action(own ? "You" : memberName(record.string("sender_id"), store: store), filled: false) { [weak self] in
                guard let self else { return }; self.push(PublicProfileController(store: self.store, profileID: record.string("sender_id")))
            }]
            if !record.string("reply_to").isEmpty {
                let original = records.first { $0.id == record.string("reply_to") }
                views.append(text("Reply to: \(original?.string("body", fallback: "Photo") ?? "Earlier message")", 13, color: Palette.muted))
            }
            if !record.string("body").isEmpty { views.append(text(record.string("body"))) }
            if !record.string("attachment_path").isEmpty { views.append(remoteImage(record.string("attachment_path"), store: store, height: 220)) }
            views.append(text("\(own ? "Sent · " : "")\(record.string("created_at"))", 11, color: Palette.muted))
            views.append(line([
                action("Reply", icon: "icon-comment", filled: false) { [weak self] in
                    guard let self, !self.sending else { return }; self.replyID = record.id; self.pendingID = UUID().uuidString; self.updateComposer(); self.composer.becomeFirstResponder()
                }, action("Report", icon: "icon-report", filled: false) { [weak self] in
                    guard let self else { return }; self.push(ReportController(store: self.store, kind: "message", targetID: record.id))
                }
            ]))
            messages.addArrangedSubview(card(views, color: own ? Palette.cream : Palette.paper))
        }
        view.layoutIfNeeded()
        if wasNearBottom {
            scrollToLatest(animated: false)
        } else {
            scroll.setContentOffset(priorOffset, animated: false)
            staysAtBottom = false
            if hasNewMessages { newMessagesButton?.isHidden = false }
        }
    }
    private func updateMessagePolicy() {
        guard let conversation = store.rows("conversations").first(where: { $0.id == conversationID }), !conversation.bool("is_group"),
              let other = conversation.strings("member_ids").first(where: { $0 != store.userID }) else { policyLabel.isHidden = true; return }
        let outgoing = store.rows("follows").contains { $0.string("follower_id") == store.userID && $0.string("following_id") == other }
        let incoming = store.rows("follows").contains { $0.string("follower_id") == other && $0.string("following_id") == store.userID }
        policyLabel.text = outgoing && incoming ? "You follow each other. Keep the travel plans flowing." : "You can send one greeting before following each other. The server checks this limit."
        policyLabel.isHidden = false
    }
    private func markRead() {
        guard accountID == store.userID, viewIfLoaded?.window != nil, isNearBottom else { return }
        let latest = store.rows("messages").filter { $0.string("conversation_id") == conversationID }.max { $0.string("created_at") < $1.string("created_at") }?.id ?? ""
        guard !latest.isEmpty, latest != lastReadMessage else { return }
        lastReadMessage = latest
        Task { [weak self] in
            guard let self else { return }
            do { try await self.store.perform("chat.preferences", ["conversation_id": .string(self.conversationID), "last_read_at": .string(ISO8601DateFormatter().string(from: Date()))]) }
            catch { self.lastReadMessage = ""; self.stateLabel.text = "Read state could not be saved: \(error.localizedDescription)" }
        }
    }
    private func send() {
        guard !sending, !photoLoading, accountID == store.userID else { return }
        guard let conversation = store.rows("conversations").first(where: { $0.id == conversationID }) else { notice("Refresh to load this conversation."); return }
        guard !conversation.strings("member_ids").contains(where: { isBlocked($0, store: store) }) else { notice("Messaging is unavailable while a member is blocked."); return }
        let raw = composer.text ?? ""
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || attachment != nil else { notice("Write a message or attach a photo."); return }
        guard body.count <= 2000 else { notice("Messages can contain up to 2,000 characters."); return }
        let id = pendingID
        let reply = replyID
        let photo = attachment
        sending = true; updateComposer()
        Task { [self] in
            do {
                if let photo, uploadedPath == nil { uploadedPath = try await store.upload(data: photo, contentType: "image/jpeg", purpose: "chat") }
                guard accountID == store.userID, store.isAuthenticated else { sending = false; updateComposer(); return }
                try await store.perform("chat.send", ["id": .string(id), "conversation_id": .string(conversationID), "body": .string(body), "attachment_path": uploadedPath.map(JSONValue.string) ?? .null, "attachment_type": photo == nil ? .null : .string("image/jpeg"), "reply_to": reply.map(JSONValue.string) ?? .null])
                if composer.text == raw { composer.text = ""; draftGeneration += 1 }
                replyID = nil; attachment = nil; uploadedPath = nil; pendingID = UUID().uuidString
                stateLabel.text = "Sent"; persistDraft()
            } catch { stateLabel.text = "Not sent: \(error.localizedDescription)" }
            sending = false; updateComposer()
        }
    }
    private func pickPhoto() {
        guard !sending, !photoLoading else { return }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images; configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self; present(picker, animated: true)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        let generation = UUID(); photoGeneration = generation; photoLoading = true; updateComposer()
        loadTravelPhoto(result.itemProvider) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.photoGeneration == generation, self.accountID == self.store.userID else { return }
                self.photoLoading = false
                switch result {
                case .success(let data): self.attachment = data; self.uploadedPath = nil; self.pendingID = UUID().uuidString
                case .failure(let error): self.notice(error.localizedDescription)
                }
                self.updateComposer()
            }
        }
    }
    private func showMembers() {
        let controller = ConversationMembersController(store: store, conversationID: conversationID)
        push(controller)
    }
}

@MainActor
final class ConversationMembersController: TravelScreen {
    private let conversationID: String
    init(store: TravelStore, conversationID: String) { self.conversationID = conversationID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func render() {
        super.render(); title = "Travelers"
        let conversation = store.rows("conversations").first { $0.id == conversationID }
        for id in Set(conversation?.strings("member_ids") ?? []).sorted() {
            let profile = id == store.userID ? store.profile : store.rows("profiles").first { $0.id == id }
            var views: [UIView] = []
            if let profile, !profile.string("avatar_path").isEmpty {
                views.append(remoteImage(profile.string("avatar_path"), store: store, height: 120))
            }
            views.append(action(memberName(id, store: store), icon: "icon-profile", filled: false) { [weak self] in
                guard let self else { return }; self.push(PublicProfileController(store: self.store, profileID: id))
            })
            content.addArrangedSubview(card(views))
        }
        content.addArrangedSubview(text("Messages are saved by the server. Read state is private to your account; delivery receipts and calls are not available.", 14, color: Palette.muted))
    }
}
