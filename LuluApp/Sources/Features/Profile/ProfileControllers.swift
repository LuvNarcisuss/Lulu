import UIKit

@MainActor
final class MeController: TravelScreen {
    private var selection = 0
    override func render() {
        super.render(); title = "Me"
        if navigationItem.rightBarButtonItem == nil {
            let settings = iconButton("icon-settings", label: "Settings") { [weak self] in
                guard let self else { return }
                self.push(SettingsController(store: self.store))
            }
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: settings)
        }
        let profile = store.profile
        let following = store.rows("follows").filter { $0.string("follower_id") == store.userID }.count
        let followers = store.rows("follows").filter { $0.string("following_id") == store.userID }.count
        let works = store.rows("clips").filter { $0.string("publisher_id") == store.userID }
        let stats = "\(works.count) works · \(following) following · \(followers) followers"
        content.addArrangedSubview(profileCover(profile, stats: stats))
        let walletTitle = store.hasCoinState ? "Wallet · \(store.balance.formatted()) coins" : "Wallet"
        content.addArrangedSubview(action(walletTitle, icon: "icon-wallet") { [weak self] in guard let self else { return }; self.push(WalletController(store: self.store)) })
        content.addArrangedSubview(collectionTabs())
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
            let savedPlaces = store.visiblePlaces.filter { placeIDs.contains($0.id) }
            for place in savedPlaces {
                content.addArrangedSubview(card([remoteImage(place.string("photo_path"), store: store, height: 150), action(place.string("name"), icon: "icon-location", filled: false) { [weak self] in
                    guard let self else { return }; self.push(PlaceController(store: self.store, placeID: place.id))
                }]))
            }
            if clips.isEmpty && savedPlaces.isEmpty { empty("Keep places and stories close", "Save a destination or video to find it here.") }
        case 3:
            appendMyGuides()
        case 4:
            appendTravelerCode()
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
    private func collectionTabs() -> UIView {
        let titles = ["Works", "Liked", "Saved", "Guides", "Traveler Code", "Pending"]
        let tabs = line([], spacing: 2)
        tabs.distribution = .fillEqually
        for (index, title) in titles.enumerated() {
            let button = action(title, filled: index == selection) { [weak self] in
                guard let self else { return }
                self.selection = index
                self.render()
                if index == 3 {
                    self.run { try await self.store.refreshCoinState() }
                }
            }
            var configuration = button.configuration
            configuration?.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 2, bottom: 8, trailing: 2)
            configuration?.titleAlignment = .center
            configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var result = incoming
                result.font = FontBook.font(12)
                return result
            }
            button.configuration = configuration
            button.titleLabel?.textAlignment = .center
            if index == selection { button.accessibilityTraits.insert(.selected) }
            tabs.addArrangedSubview(button)
        }
        return tabs
    }

    private func profileCover(_ profile: Record, stats: String) -> UIView {
        let path = profile.string("avatar_path")
        let avatar = remoteImage(path, store: store, height: 64, radius: 32)
        if path.isEmpty {
            avatar.image = UIImage(named: "icon-profile")
            avatar.contentMode = .scaleAspectFit
        }
        avatar.widthAnchor.constraint(equalToConstant: 64).isActive = true
        avatar.layer.borderWidth = 2
        avatar.layer.borderColor = Palette.cream.cgColor
        avatar.accessibilityLabel = "Profile photo"

        let name = text(profile.string("display_name", fallback: "Traveler"), 24, display: true)
        let bio = text(profile.string("bio", fallback: "Your travel story starts here."), 16, color: Palette.muted)
        name.numberOfLines = 1
        name.lineBreakMode = .byTruncatingTail
        bio.numberOfLines = 2
        bio.lineBreakMode = .byTruncatingTail
        let identity = column([name, bio], spacing: 4)
        let details = card([
            line([avatar, identity]),
            text(stats, 14, color: Palette.teal)
        ])

        let cover = UIView()
        cover.layer.cornerRadius = 24
        cover.clipsToBounds = true
        let artwork = UIImageView(image: UIImage(named: "background-welcome"))
        artwork.contentMode = .scaleAspectFill
        artwork.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        artwork.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        for child in [artwork, details] {
            child.translatesAutoresizingMaskIntoConstraints = false
            cover.addSubview(child)
        }
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: cover.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            artwork.bottomAnchor.constraint(equalTo: cover.bottomAnchor),
            details.topAnchor.constraint(equalTo: cover.topAnchor, constant: 12),
            details.leadingAnchor.constraint(equalTo: cover.leadingAnchor, constant: 12),
            details.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: -12),
            details.bottomAnchor.constraint(equalTo: cover.bottomAnchor, constant: -12)
        ])
        return cover
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
