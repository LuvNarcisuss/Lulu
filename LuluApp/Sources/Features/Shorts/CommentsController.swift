import UIKit

final class CommentsController: TravelScreen {
    var onClose: (() -> Void)?
    private let clipID: String
    private let composer = input("Add a thoughtful comment")
    private let replyLabel = text("", 13, color: Palette.muted)
    private var parentID: String?
    private var sending = false
    init(store: TravelStore, clipID: String) { self.clipID = clipID; super.init(store: store); refreshWhileEditing = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        title = "Conversation"
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: iconButton("icon-close", label: "Close comments") { [weak self] in self?.onClose?() })
        let send = iconButton("icon-send", label: "Send comment") { [weak self] in self?.send() }
        let cancel = iconButton("icon-close", label: "Cancel reply") { [weak self] in self?.parentID = nil; self?.replyLabel.text = "" }
        let reply = line([replyLabel, cancel])
        let bar = column([reply, line([composer, send])], spacing: 5)
        bar.backgroundColor = Palette.paper
        bar.isLayoutMarginsRelativeArrangement = true
        bar.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 10, trailing: 14)
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)])
        scroll.contentInset.bottom = 140
    }
    override func render() {
        super.render()
        let reported = Set(store.rows("reports").filter { $0.string("target_kind") == "comment" }.map { $0.string("target_id") })
        let blocked = Set(store.rows("blocks").map { $0.string("blocked_id") })
        let comments = store.rows("comments").filter { $0.string("clip_id") == clipID && !reported.contains($0.id) && !blocked.contains($0.string("user_id")) }.sorted { $0.string("created_at") < $1.string("created_at") }
        content.addArrangedSubview(text("Notes from the road", 28, display: true))
        if comments.isEmpty { content.addArrangedSubview(text("Be the first to share a useful thought about this place.", 17, color: Palette.muted)) }
        for comment in comments {
            let author = store.rows("profiles").first { $0.id == comment.string("user_id") }
            let name = author?.string("display_name", fallback: "Traveler") ?? "Traveler"
            var views: [UIView] = []
            let heading = action(name, icon: "icon-profile", filled: false) { [weak self] in guard let self else { return }; self.push(PublicProfileController(store: self.store, profileID: comment.string("user_id"))) }
            views.append(heading)
            if let parent = comments.first(where: { $0.id == comment.string("parent_id") }) { views.append(text("Replying to: " + String(parent.string("body").prefix(90)), 13, color: Palette.muted)) }
            views.append(text(comment.string("body"), 17))
            views.append(text(String(comment.string("created_at").prefix(16)).replacingOccurrences(of: "T", with: " "), 12, color: Palette.muted))
            let reply = action("Reply", icon: "icon-comment", filled: false) { [weak self] in self?.parentID = comment.id; self?.replyLabel.text = "Replying to " + name; self?.composer.becomeFirstResponder() }
            let more = iconButton("icon-more", label: "Comment options") { [weak self] in
                guard let self else { return }
                if comment.string("user_id") == self.store.userID {
                    self.confirm("Remove your comment?", message: "This comment will be removed from the conversation.", destructive: true) {
                        self.run { try await self.store.perform("comment.delete", ["comment_id": .string(comment.id)]) }
                    }
                } else { self.push(ReportController(store: self.store, kind: "comment", targetID: comment.id)) }
            }
            views.append(line([reply, UIView(), more]))
            content.addArrangedSubview(card(views))
        }
    }
    private func send() {
        guard !sending else { return }
        let raw = composer.text ?? ""
        let reply = parentID
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 500 else { notice("Write a comment between 1 and 500 characters."); return }
        sending = true
        let payload: [String: JSONValue] = ["clip_id": .string(clipID), "body": .string(body), "parent_id": reply.map(JSONValue.string) ?? .null]
        Task { [weak self] in
            guard let self else { return }; defer { self.sending = false }
            do {
                try await self.store.perform("comment.add", payload)
                if self.composer.text == raw { self.composer.text = "" }
                if self.parentID == reply { self.parentID = nil; self.replyLabel.text = "" }
                self.render()
            } catch { self.notice(error.localizedDescription) }
        }
    }
}
