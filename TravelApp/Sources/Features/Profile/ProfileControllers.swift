import UIKit

@MainActor
final class MeController: TravelScreen {
    private var selection = 0
    override func render() {
        super.render(); title = "Me"
        let profile = store.profile
        var header: [UIView] = []
        if !profile.string("avatar_path").isEmpty { header.append(remoteImage(profile.string("avatar_path"), store: store, height: 150, radius: 26)) }
        header += [text(profile.string("display_name", fallback: "Traveler"), 32, display: true), text(profile.string("bio", fallback: "Your travel story starts here."), 16, color: Palette.muted), text("Traveler ID: \(store.userID)", 11, color: Palette.muted)]
        let following = store.rows("follows").filter { $0.string("follower_id") == store.userID }.count
        let followers = store.rows("follows").filter { $0.string("following_id") == store.userID }.count
        let works = store.rows("clips").filter { $0.string("publisher_id") == store.userID }
        header.append(text("\(works.count) works · \(following) following · \(followers) followers", 14, color: Palette.teal))
        content.addArrangedSubview(card(header))
        content.addArrangedSubview(line([
            action("Edit profile", icon: "icon-edit", filled: false) { [weak self] in guard let self else { return }; self.push(EditProfileController(store: self.store)) },
            action("Settings", icon: "icon-settings", filled: false) { [weak self] in guard let self else { return }; self.push(SettingsController(store: self.store)) }
        ]))
        content.addArrangedSubview(action("My traveler code", icon: "icon-share", filled: false) { [weak self] in guard let self else { return }; self.push(TravelerCodeController(store: self.store)) })
        content.addArrangedSubview(action("Wallet · \(store.balance) diamonds", icon: "icon-wallet") { [weak self] in guard let self else { return }; self.push(WalletController(store: self.store)) })
        content.addArrangedSubview(choiceStrip(["Works", "Liked", "Saved", "Pending"], selected: selection) { [weak self] index in self?.selection = index; self?.render() })
        var clips: [Record] = []
        switch selection {
        case 0: clips = works
        case 1:
            let ids = Set(store.rows("likes").filter { $0.string("user_id") == store.userID }.map { $0.string("clip_id") })
            clips = store.rows("clips").filter { ids.contains($0.id) }
        case 2:
            let ids = Set(store.rows("saved_clips").filter { $0.string("user_id") == store.userID }.map { $0.string("clip_id") })
            clips = store.rows("clips").filter { ids.contains($0.id) }
            let placeIDs = Set(store.rows("saved_places").filter { $0.string("user_id") == store.userID }.map { $0.string("place_id") })
            for place in store.rows("places").filter({ placeIDs.contains($0.id) }) {
                content.addArrangedSubview(card([remoteImage(place.string("photo_path"), store: store, height: 150), action(place.string("name"), icon: "icon-location", filled: false) { [weak self] in
                    guard let self else { return }; self.push(PlaceController(store: self.store, placeID: place.id))
                }]))
            }
            if clips.isEmpty && placeIDs.isEmpty { empty("Keep places and stories close", "Save a destination or video to find it here.") }
        default:
            let pending = store.rows("submissions").filter { $0.string("owner_id") == store.userID }
            if pending.isEmpty { empty("No submissions yet", "Your uploads appear here with their actual review status.") }
            for submission in pending {
                var views: [UIView] = [text(submission.string("title"), 22, display: true), text(submission.string("caption"), 15, color: Palette.muted), text("Status: \(submission.string("status", fallback: "Pending"))", 14, color: Palette.teal)]
                if !submission.string("cover_path").isEmpty { views.insert(remoteImage(submission.string("cover_path"), store: store, height: 170), at: 0) }
                views.append(action("Play private submission", icon: "icon-video", filled: false) { [weak self] in
                    guard let self else { return }
                    var clip = submission
                    clip["publisher_id"] = .string(self.store.userID)
                    clip["is_private"] = .bool(true)
                    self.push(ClipFeedController(store: self.store, clips: [clip], initialIndex: 0))
                })
                views.append(action("Delete submission", icon: "icon-trash", filled: false) { [weak self] in
                    guard let self else { return }
                    self.confirm("Delete submission?", message: "This removes your submitted video and its review entry.", destructive: true) {
                        self.run { try await self.store.perform("submission.delete", ["submission_id": .string(submission.id)]) }
                    }
                })
                content.addArrangedSubview(card(views))
            }
        }
        if clips.isEmpty && selection < 2 { empty(selection == 0 ? "Collect your travel stories" : "Nothing liked yet", selection == 0 ? "Published videos will appear here after review." : "Like a video to keep it in this collection.") }
        for (index, clip) in clips.enumerated() {
            content.addArrangedSubview(card([remoteImage(clip.string("cover_path"), store: store, height: 180), action(clip.string("title"), icon: "icon-shorts", filled: false) { [weak self] in
                guard let self else { return }; self.push(ClipFeedController(store: self.store, clips: clips, initialIndex: index))
            }]))
        }
        if selection == 0 { content.addArrangedSubview(action("Share a travel video", icon: "icon-add") { [weak self] in guard let self else { return }; self.push(CreationController(store: self.store)) }) }
    }
    private func empty(_ title: String, _ detail: String) { content.addArrangedSubview(card([text(title, 24, display: true), text(detail, color: Palette.muted)])) }
}

@MainActor
final class PublicProfileController: TravelScreen {
    private let profileID: String
    init(store: TravelStore, profileID: String) { self.profileID = profileID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func render() {
        super.render(); title = "Traveler profile"
        guard let profile = profileID == store.userID ? store.profile : store.rows("profiles").first(where: { $0.id == profileID }) else {
            content.addArrangedSubview(text("This profile is unavailable.", color: Palette.muted)); return
        }
        if !profile.string("avatar_path").isEmpty { content.addArrangedSubview(remoteImage(profile.string("avatar_path"), store: store, height: 200)) }
        content.addArrangedSubview(text(profile.string("display_name", fallback: "Traveler"), 32, display: true))
        content.addArrangedSubview(text(profile.string("bio"), color: Palette.muted))
        if profile.bool("is_editorial") { content.addArrangedSubview(text("Editorial publisher · not a member account", 14, color: Palette.teal)) }
        let published = store.rows("clips").filter { $0.string("publisher_id") == profileID }
        let followers = store.rows("follows").filter { $0.string("following_id") == profileID }.count
        let following = store.rows("follows").filter { $0.string("follower_id") == profileID }.count
        content.addArrangedSubview(text("\(published.count) works · \(followers) followers · \(following) following", 14, color: Palette.teal))
        if profileID != store.userID {
            let follows = store.rows("follows").contains { $0.string("following_id") == profileID && $0.string("follower_id") == store.userID }
            let blocked = store.rows("blocks").contains { $0.string("blocked_id") == profileID && $0.string("blocker_id") == store.userID }
            let followButton = action(follows ? "Unfollow" : "Follow", icon: "icon-heart") { [weak self] in
                guard let self else { return }
                self.run { try await self.store.perform("relationship.follow", ["profile_id": .string(self.profileID), "enabled": .bool(!follows)]) }
            }
            followButton.isEnabled = follows || !isBlocked(profileID, store: store)
            content.addArrangedSubview(followButton)
            if !profile.bool("is_editorial") {
                let message = action("Message", icon: "icon-chats", filled: false) { [weak self] in
                    guard let self else { return }
                    self.run {
                        let result = try await self.store.perform("chat.direct", ["profile_id": .string(self.profileID)])
                        let id = result.string("conversation_id")
                        guard !id.isEmpty else { throw SocialError.missingConversation }
                        self.push(ConversationController(store: self.store, conversationID: id))
                    }
                }
                message.isEnabled = !isBlocked(profileID, store: store)
                content.addArrangedSubview(message)
            }
            content.addArrangedSubview(action(blocked ? "Unblock" : "Block", icon: "icon-block", filled: false) { [weak self] in
                guard let self else { return }
                self.confirm(blocked ? "Unblock traveler?" : "Block traveler?", message: blocked ? "They may interact with you again." : "Messaging and social interactions with this profile will be restricted.", destructive: !blocked) {
                    self.run { try await self.store.perform("safety.block", ["profile_id": .string(self.profileID), "enabled": .bool(!blocked)]) }
                }
            })
            content.addArrangedSubview(action("Report profile", icon: "icon-report", filled: false) { [weak self] in guard let self else { return }; self.push(ReportController(store: self.store, kind: "profile", targetID: self.profileID)) })
        }
        for (index, clip) in published.enumerated() {
            content.addArrangedSubview(card([remoteImage(clip.string("cover_path"), store: store, height: 170), action(clip.string("title"), filled: false) { [weak self] in
                guard let self else { return }; self.push(ClipFeedController(store: self.store, clips: published, initialIndex: index))
            }]))
        }
    }
}
