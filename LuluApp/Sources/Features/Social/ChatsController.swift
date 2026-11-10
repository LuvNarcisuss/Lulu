import UIKit

@MainActor
final class ChatsController: TravelScreen {
    private let search = input("Search conversations")
    private let list = column()
    private let inbox = column(spacing: 20)
    private lazy var emptyInbox = makeEmptyInbox()
    private var filter = 0
    private var built = false
    private var showArchived = false
    private let filterSlot = column()
    private lazy var archiveToggle = action("Show archived", filled: false) { [weak self] in
        guard let self else { return }
        self.showArchived.toggle()
        self.updateList()
    }

    override func render() {
        if !built {
            super.render(); built = true; title = "Chats"; refreshWhileEditing = true
            inbox.addArrangedSubview(text("Postcards & conversations", 30, display: true))
            inbox.addArrangedSubview(text("Make plans with real travelers.", 16, color: Palette.muted))
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: iconButton("icon-add", label: "Add traveler") { [weak self] in self?.addTravelerOptions() })
            inbox.addArrangedSubview(line([
                action("Find travelers", icon: "icon-search") { [weak self] in self?.discover(false) },
                action("New group", icon: "icon-group", filled: false) { [weak self] in self?.discover(true) }
            ]))
            search.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
            inbox.addArrangedSubview(search)
            inbox.addArrangedSubview(filterSlot)
            inbox.addArrangedSubview(archiveToggle)
            inbox.addArrangedSubview(action("Refresh", icon: "icon-refresh", filled: false) { [weak self] in
                guard let self else { return }; self.run { try await self.store.refresh() }
            })
            inbox.addArrangedSubview(list)
            content.addArrangedSubview(emptyInbox)
            content.addArrangedSubview(inbox)

            let refresh = UIRefreshControl()
            refresh.tintColor = Palette.teal
            refresh.addAction(UIAction { [weak self, weak refresh] _ in
                guard let self else { return }
                Task {
                    defer { refresh?.endRefreshing() }
                    try? await self.store.refresh()
                }
            }, for: .valueChanged)
            scroll.refreshControl = refresh
        }
        updateList()
    }

    @objc private func searchChanged() { updateList() }
    private func discover(_ group: Bool) { push(MemberDiscoveryController(store: store, group: group)) }
    private func makeEmptyInbox() -> UIStackView {
        let mark = UIImageView(image: UIImage(named: "icon-chats"))
        mark.contentMode = .scaleAspectFit
        mark.heightAnchor.constraint(equalToConstant: 90).isActive = true
        mark.isAccessibilityElement = false

        let heading = text("Postcards &\nconversations", 36, display: true)
        heading.accessibilityTraits.insert(.header)
        let cardTitle = text("Your next journey starts with a hello", 26, display: true)
        cardTitle.accessibilityTraits.insert(.header)
        return column([
            heading,
            text("Make plans with real travelers.", 17, color: Palette.muted),
            card([
                mark,
                cardTitle,
                text("Find a traveler to start a conversation.", 17),
                action("Find travelers", icon: "icon-search") { [weak self] in self?.discover(false) }
            ]),
            action("New group", icon: "icon-group", filled: false) { [weak self] in self?.discover(true) }
        ], spacing: 20)
    }

    private func updateList() {
        let conversations = store.rows("conversations")
        let isEmpty = conversations.isEmpty
        emptyInbox.isHidden = !isEmpty
        inbox.isHidden = isEmpty
        clearStack(list); clearStack(filterSlot)
        guard !isEmpty else {
            search.resignFirstResponder()
            search.text = nil
            filter = 0
            showArchived = false
            return
        }
        let archiveAction = showArchived ? "Back to inbox" : "Show archived"
        archiveToggle.configuration?.title = archiveAction
        archiveToggle.accessibilityLabel = archiveAction
        filterSlot.addArrangedSubview(choiceStrip(["All", "Unread", "Pinned", "Drafts"], selected: filter) { [weak self] index in
            self?.filter = index; self?.updateList()
        })
        let query = search.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rows = conversations.filter { record in
            let preference = chatPreference(record.id, store: store)
            guard preference.bool("archived") == showArchived else { return false }
            if filter == 1 && record.int("unread_count") == 0 { return false }
            if filter == 2 && !preference.bool("pinned") { return false }
            if filter == 3 && preference.string("draft").isEmpty { return false }
            return query.isEmpty || conversationName(record, store: store).localizedCaseInsensitiveContains(query) || record.string("last_message").localizedCaseInsensitiveContains(query)
        }.sorted { left, right in
            let leftPin = chatPreference(left.id, store: store).bool("pinned")
            let rightPin = chatPreference(right.id, store: store).bool("pinned")
            if leftPin != rightPin { return leftPin }
            return left.string("updated_at") > right.string("updated_at")
        }
        if rows.isEmpty {
            let emptyTitle: String
            let detail: String
            if !query.isEmpty {
                emptyTitle = "No matching conversations"
                detail = "Try a different search or clear it to see more conversations."
            } else {
                switch filter {
                case 1:
                    emptyTitle = "No unread conversations"
                    detail = "New messages will appear here until you read them."
                case 2:
                    emptyTitle = "No pinned conversations"
                    detail = "Pin a conversation from its options to find it here."
                case 3:
                    emptyTitle = "No conversation drafts"
                    detail = "Unsent messages you save as drafts will appear here."
                default:
                    emptyTitle = showArchived ? "No archived conversations" : "Your next journey starts with a hello"
                    detail = showArchived ? "Conversations you archive will appear here." : "Find a traveler to start a conversation."
                }
            }
            list.addArrangedSubview(card([text(emptyTitle, 23, display: true), text(detail, 16, color: Palette.muted)]))
        }
        for record in rows {
            let preference = chatPreference(record.id, store: store)
            let draft = preference.string("draft")
            let detail = draft.isEmpty ? record.string("last_message", fallback: "No messages yet") : "Draft: \(draft)"
            var markers: [String] = []
            if preference.bool("pinned") { markers.append("Pinned") }
            if preference.bool("muted") { markers.append("Muted") }
            if record.int("unread_count") > 0 { markers.append("\(record.int("unread_count")) unread") }
            let summary = column([
                action(conversationName(record, store: store), filled: false) { [weak self] in
                    guard let self else { return }; self.push(ConversationController(store: self.store, conversationID: record.id))
                }, text(detail, 15, color: Palette.muted),
                text([recentChatTime(record.string("updated_at")), markers.joined(separator: " · ")].filter { !$0.isEmpty }.joined(separator: " · "), 12, color: Palette.teal)
            ], spacing: 6)
            summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            list.addArrangedSubview(card([
                line([conversationAvatar(record, store: store), summary]),
                action("Conversation options", icon: "icon-more", filled: false) { [weak self] in self?.options(record) }
            ]))
        }
    }
    private func addTravelerOptions() {
        let dialog = TravelDialogController(title: "Add a traveler", message: "Find a member, scan a traveler code or share your own code.", choices: [
            ("Find travelers", false, { [weak self] in self?.discover(false) }),
            ("Scan traveler code", false, { [weak self] in guard let self else { return }; self.push(FriendScannerController(store: self.store)) }),
            ("My traveler code", false, { [weak self] in guard let self else { return }; self.push(TravelerCodeController(store: self.store)) }),
            ("Cancel", false, { })
        ])
        present(dialog, animated: true)
    }
    private func options(_ record: Record) {
        push(ConversationOptionsController(store: store, conversationID: record.id))
    }

}

@MainActor
final class MemberDiscoveryController: TravelScreen {
    private let group: Bool
    private let search = input("Search by traveler name or full ID")
    private let groupTitle = input("Group name")
    private let list = column()
    private var selected = Set<String>()
    private var built = false
    init(store: TravelStore, group: Bool) { self.group = group; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func render() {
        if !built {
            super.render(); built = true; title = group ? "New group" : "Find travelers"; refreshWhileEditing = true
            content.addArrangedSubview(text(group ? "Bring your travel circle together" : "Meet fellow travelers", 28, display: true))
            content.addArrangedSubview(text("Only discoverable member accounts appear here. Editorial publishers cannot receive messages.", 15, color: Palette.muted))
            content.addArrangedSubview(search)
            search.addTarget(self, action: #selector(updateMembers), for: .editingChanged)
            if group {
                content.addArrangedSubview(groupTitle)
                content.addArrangedSubview(action("Create group", icon: "icon-group") { [weak self] in self?.createGroup() })
            }
            content.addArrangedSubview(action("Refresh travelers", filled: false) { [weak self] in guard let self else { return }; self.run { try await self.store.refresh() } })
            content.addArrangedSubview(list)
        }
        updateMembers()
    }
    @objc private func updateMembers() {
        clearStack(list)
        let query = search.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let members = store.rows("profiles").filter {
            !$0.bool("is_editorial") && $0.id != store.userID && !isBlocked($0.id, store: store) &&
            (query.isEmpty || $0.string("display_name").localizedCaseInsensitiveContains(query) || $0.id.caseInsensitiveCompare(query) == .orderedSame)
        }
        let eligible = Set(members.map(\.id))
        selected = selected.filter { id in store.rows("profiles").contains { $0.id == id && !$0.bool("is_editorial") && !isBlocked(id, store: store) } }
        if members.isEmpty { list.addArrangedSubview(text("No matching travelers. Try another name or refresh.", color: Palette.muted)) }
        for member in members {
            let title = member.string("display_name", fallback: "Traveler")
            let control = action(group ? "\(selected.contains(member.id) ? "Selected: " : "Add: ")\(title)" : "Message \(title)", icon: group ? "icon-check" : "icon-send", filled: selected.contains(member.id)) { [weak self] in
                guard let self, eligible.contains(member.id) else { return }
                if self.group {
                    if self.selected.contains(member.id) { self.selected.remove(member.id) } else { self.selected.insert(member.id) }
                    self.updateMembers()
                } else {
                    self.run {
                        let result = try await self.store.perform("chat.direct", ["profile_id": .string(member.id)])
                        let id = result.string("conversation_id")
                        guard !id.isEmpty else { throw SocialError.missingConversation }
                        self.push(ConversationController(store: self.store, conversationID: id))
                    }
                }
            }
            list.addArrangedSubview(card([text(title, 21, display: true), text(member.string("bio"), 14, color: Palette.muted), text(member.id, 11, color: Palette.muted), control,
                action("View profile", filled: false) { [weak self] in guard let self else { return }; self.push(PublicProfileController(store: self.store, profileID: member.id)) }
            ]))
        }
    }
    private func createGroup() {
        let name = groupTitle.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, name.count <= 60 else { notice("Enter a group name up to 60 characters."); return }
        guard selected.count >= 2 else { notice("Select at least two other travelers."); return }
        run { [self] in
            let result = try await store.perform("chat.group", ["title": .string(name), "member_ids": .array(selected.sorted().map(JSONValue.string))])
            let id = result.string("conversation_id")
            guard !id.isEmpty else { throw SocialError.missingConversation }
            push(ConversationController(store: store, conversationID: id))
        }
    }
}

enum SocialError: LocalizedError {
    case missingConversation
    var errorDescription: String? { "The server did not return a conversation. Refresh before trying again." }
}


@MainActor
final class ConversationOptionsController: TravelScreen {
    private let conversationID: String
    init(store: TravelStore, conversationID: String) { self.conversationID = conversationID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func render() {
        super.render(); title = "Conversation options"
        let preference = chatPreference(conversationID, store: store)
        for (key, label) in [("pinned", preference.bool("pinned") ? "Unpin" : "Pin"), ("muted", preference.bool("muted") ? "Unmute" : "Mute"), ("archived", preference.bool("archived") ? "Unarchive" : "Archive")] {
            content.addArrangedSubview(action(label) { [weak self] in
                guard let self else { return }
                self.run {
                    try await self.store.perform("chat.preferences", ["conversation_id": .string(self.conversationID), key: .bool(!preference.bool(key))])
                    self.navigationController?.popViewController(animated: true)
                }
            })
        }
        content.addArrangedSubview(action("Mark as read", icon: "icon-check", filled: false) { [weak self] in
            guard let self else { return }
            self.run {
                try await self.store.perform("chat.preferences", ["conversation_id": .string(self.conversationID), "last_read_at": .string(ISO8601DateFormatter().string(from: Date()))])
                self.navigationController?.popViewController(animated: true)
            }
        })
    }
}
