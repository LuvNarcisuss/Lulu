import UIKit

@MainActor
private struct PublishedProfileWorks {
    let clips: [Record]
    let guides: [(offer: Record, place: Record)]

    init(profileID: String, store: TravelStore) {
        clips = store.rows("clips").filter { $0.string("publisher_id") == profileID }
        let places = Dictionary(store.rows("places").map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guides = store.guideOffers.compactMap { offer in
            guard offer.string("status") == "published", let place = places[offer.string("place_id")],
                  guidePublisherID(place: place, offer: offer, store: store) == profileID else { return nil }
            return (offer, place)
        }
    }

    func receivedLikes(in store: TravelStore) -> Int? {
        guard store.hasCoinState else { return nil }
        var total = 0
        for (kind, ids) in [("clips", clips.map(\.id)), ("guides", guides.map { $0.offer.string("guide_id") })] {
            for id in ids {
                guard let likes = store.contentLikeCount(kind: kind, id: id) else { return nil }
                let (sum, overflow) = total.addingReportingOverflow(likes)
                guard !overflow else { return nil }
                total = sum
            }
        }
        return total
    }
}

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
        let works = PublishedProfileWorks(profileID: store.userID, store: store)
        let likes = works.receivedLikes(in: store)?.formatted() ?? "—"
        let stats = "\(likes) likes · \(following) following · \(followers) followers"
        content.addArrangedSubview(profileCover(profile, stats: stats))
        let walletTitle = store.payments.walletBalance.map { "Wallet · \($0.formatted()) coins" } ?? "Wallet"
        content.addArrangedSubview(action(walletTitle, icon: "icon-wallet") { [weak self] in guard let self else { return }; self.push(WalletController(store: self.store)) })
        content.addArrangedSubview(collectionTabs())
        var clips: [Record] = []
        switch selection {
        case 0: clips = works.clips
        case 1:
            let ids = Set(store.rows("likes").filter { $0.string("user_id") == store.userID }.map { $0.string("clip_id") })
            clips = store.rows("clips").filter { ids.contains($0.id) }
        case 2:
            let ids = Set(store.rows("saved_clips").filter { $0.string("user_id") == store.userID }.map { $0.string("clip_id") })
            clips = store.rows("clips").filter { ids.contains($0.id) }
            let placeIDs = Set(store.rows("saved_places").filter { $0.string("user_id") == store.userID }.map { $0.string("place_id") })
            let savedPlaces = store.visiblePlaces.filter { placeIDs.contains($0.id) }
            for place in savedPlaces {
                let open = { [weak self] in
                    guard let self else { return }
                    self.openPlaceGuide(place.id, store: self.store)
                }
                var views: [UIView] = [
                    destinationGuideCover(place, store: store, height: 150, onOpen: open),
                    action(place.string("name"), icon: "icon-location", filled: false, open)
                ]
                if let publisherID = guidePublisherID(place: place, offer: nil, store: store) {
                    views.append(publisherIdentity(publisherID, store: store) { [weak self] in
                        guard let self else { return }
                        self.push(PublicProfileController(store: self.store, profileID: publisherID))
                    })
                }
                content.addArrangedSubview(destinationGuideCard(views, onOpen: open))
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
        ], color: Palette.paper.withAlphaComponent(0.60))
        details.layer.borderColor = Palette.line.withAlphaComponent(0.25).cgColor

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
    private var selectedWorks = 0
    private var statistics: Record?
    private var statisticsFailed = false
    private var loadingStatistics = false
    init(store: TravelStore, profileID: String) { self.profileID = profileID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { [weak self] in await self?.loadStatistics() }
    }

    private func loadStatistics() async {
        guard !loadingStatistics else { return }
        loadingStatistics = true
        defer { loadingStatistics = false }
        do {
            statistics = try await store.profileStatistics(profileID)
            statisticsFailed = false
            updateProblem(nil, for: "statistics")
        } catch is CancellationError { return }
        catch {
            statistics = nil
            statisticsFailed = true
            updateProblem("Profile statistics could not be loaded.", for: "statistics")
        }
        render()
    }

    override func render() {
        super.render(); title = "Traveler profile"
        guard let profile = profileID == store.userID ? store.profile : store.rows("profiles").first(where: { $0.id == profileID }) else {
            navigationItem.rightBarButtonItem = nil
            updateProblem("This profile is unavailable.", for: "profile"); return
        }
        updateProblem(nil, for: "profile")
        let avatar = remoteImage(profile.string("avatar_path"), store: store, height: 76, radius: 38)
        avatar.widthAnchor.constraint(equalToConstant: 76).isActive = true
        if profile.string("avatar_path").isEmpty {
            avatar.image = UIImage(named: profile.bool("is_editorial") ? "logo-lulu" : "icon-profile")
            avatar.contentMode = .scaleAspectFit
        }
        avatar.accessibilityLabel = "Profile photo"
        let name = text(profile.string("display_name", fallback: "Traveler"), 27, display: true)
        let bio = text(profile.string("bio", fallback: "A new travel story begins here."), 16, color: Palette.muted)
        var identity: [UIView] = [line([avatar, column([name, bio], spacing: 6)])]
        if profile.bool("is_editorial") { identity.append(text(profile.bool("avatar_is_illustrative") ? "Editorial collection · Illustrative portrait" : "Editorial collection", 13, color: Palette.teal)) }
        content.addArrangedSubview(card(identity))

        let works = PublishedProfileWorks(profileID: profileID, store: store)
        let blocked = isBlocked(profileID, store: store)
        let likes = blocked ? nil : works.receivedLikes(in: store)
        let metrics = line([], spacing: 4)
        metrics.distribution = .fillEqually
        for (label, count) in [("Likes", likes), ("Following", statistics?.int("following")), ("Followers", statistics?.int("followers"))] {
            let value = text(count?.formatted() ?? "—", 28, display: true)
            let caption = text(label, 12, color: Palette.muted)
            value.textAlignment = .center; caption.textAlignment = .center
            let item = column([value, caption], spacing: 4)
            item.isAccessibilityElement = true
            item.accessibilityLabel = label
            item.accessibilityValue = count?.formatted() ?? "Unavailable"
            if label == "Likes" { item.accessibilityHint = "Received on published shorts and guides" }
            metrics.addArrangedSubview(item)
        }
        content.addArrangedSubview(metrics)
        let needsWorkCounts = !blocked && likes == nil
        if statisticsFailed || needsWorkCounts {
            content.addArrangedSubview(action("Retry statistics", filled: false) { [weak self] in
                guard let self else { return }
                self.updateProblem(nil, for: "statistics")
                self.run {
                    if needsWorkCounts {
                        try await self.store.refresh()
                        try await self.store.refreshCoinState()
                    }
                    await self.loadStatistics()
                }
            })
        }
        if profileID != store.userID { addRelationshipActions(profile) }
        else { navigationItem.rightBarButtonItem = nil }

        let categories = line([], spacing: 24)
        for (index, title) in ["Shorts", "Guides"].enumerated() {
            let heading = UIButton(type: .custom)
            heading.setTitle(title, for: .normal)
            heading.setTitleColor(selectedWorks == index ? Palette.ink : Palette.muted, for: .normal)
            heading.titleLabel?.font = FontBook.font(25, display: true)
            heading.titleLabel?.adjustsFontForContentSizeCategory = true
            heading.contentHorizontalAlignment = .leading
            heading.setContentHuggingPriority(.required, for: .horizontal)
            heading.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            heading.accessibilityLabel = title
            if selectedWorks == index { heading.accessibilityTraits.insert(.selected) }
            heading.addAction(UIAction { [weak self] _ in
                guard let self, self.selectedWorks != index else { return }
                self.selectedWorks = index
                self.render()
            }, for: .touchUpInside)
            categories.addArrangedSubview(heading)
        }
        categories.addArrangedSubview(UIView())
        content.addArrangedSubview(categories)
        if selectedWorks == 0 {
            let published = blocked ? [] : works.clips
            if published.isEmpty { content.addArrangedSubview(text("No published videos to show.", color: Palette.muted)) }
            let videos = published.enumerated().map { index, clip -> UIView in
                let open = { [weak self] in
                    guard let self else { return }
                    self.push(ClipFeedController(store: self.store, clips: published, initialIndex: index))
                }
                let cover = UIButton(type: .custom)
                cover.layer.cornerRadius = 18
                cover.clipsToBounds = true
                cover.accessibilityLabel = "Play " + clip.string("title")
                let photo = remoteImage(clip.string("cover_path"), store: store, height: 1, radius: 0)
                photo.constraints.filter { $0.firstAttribute == .height }.forEach { $0.isActive = false }
                photo.contentMode = .scaleAspectFill
                photo.isUserInteractionEnabled = false
                photo.isAccessibilityElement = false
                photo.translatesAutoresizingMaskIntoConstraints = false
                cover.addSubview(photo)
                NSLayoutConstraint.activate([
                    cover.heightAnchor.constraint(equalTo: cover.widthAnchor, multiplier: 4.0 / 3.0),
                    photo.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
                    photo.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
                    photo.topAnchor.constraint(equalTo: cover.topAnchor),
                    photo.bottomAnchor.constraint(equalTo: cover.bottomAnchor)
                ])
                attachWorkCaption(to: cover, likes: store.contentLikeCount(kind: "clips", id: clip.id))
                cover.addAction(UIAction { _ in open() }, for: .touchUpInside)
                return cover
            }
            appendGrid(videos)
            return
        }

        let reported = Set(store.rows("reports").filter { $0.string("target_kind") == "guide" }.map { $0.string("target_id") })
        let guides = works.guides.filter { guide in
            !blocked && !reported.contains(guide.offer.string("guide_id")) && !store.hiddenPlaceIDs.contains(guide.place.id)
        }
        if !store.hasCoinState {
            content.addArrangedSubview(action("Load guides", icon: "icon-refresh", filled: false) { [weak self] in
                guard let self else { return }; self.run { try await self.store.refreshCoinState() }
            })
        } else if guides.isEmpty { content.addArrangedSubview(text("No published guides to show.", color: Palette.muted)) }
        appendGrid(guides.map { guide in
            let (offer, place) = guide
            let open = { [weak self] in
                guard let self else { return }
                self.openPlaceGuide(place.id, store: self.store, guideID: offer.string("guide_id"))
            }
            return destinationGuideCard([
                destinationGuideCover(place, store: store, height: 160, offer: offer, showsWorkCaption: true, onOpen: open)
            ], onOpen: open)
        })
    }

    private func appendGrid(_ tiles: [UIView]) {
        let columns = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 2
        for start in stride(from: 0, to: tiles.count, by: columns) {
            let row = line(Array(tiles[start..<min(start + columns, tiles.count)]), spacing: 12)
            row.alignment = .top; row.distribution = .fillEqually
            if row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
            content.addArrangedSubview(row)
        }
    }

    private func addRelationshipActions(_ profile: Record) {
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: iconButton("icon-report", label: "Report profile") { [weak self] in
            guard let self else { return }; self.push(ReportController(store: self.store, kind: "profile", targetID: self.profileID))
        })
        let follows = store.rows("follows").contains { $0.string("following_id") == profileID && $0.string("follower_id") == store.userID }
        let blocked = store.rows("blocks").contains { $0.string("blocked_id") == profileID && $0.string("blocker_id") == store.userID }
        let follow = action(follows ? "Following" : "Follow", icon: follows ? "icon-check" : "icon-add", filled: !follows) { [weak self] in
            guard let self else { return }
            self.run {
                try await self.store.perform("relationship.follow", ["profile_id": .string(self.profileID), "enabled": .bool(!follows)])
                await self.loadStatistics()
            }
        }
        follow.isEnabled = follows || !isBlocked(profileID, store: store)
        let message = action("Message", icon: "icon-chats", filled: false) { [weak self] in
            guard let self else { return }
            self.run {
                let result = try await self.store.perform("chat.direct", ["profile_id": .string(self.profileID)])
                let id = result.string("conversation_id")
                guard !id.isEmpty else { throw SocialError.missingConversation }
                self.push(ConversationController(store: self.store, conversationID: id))
            }
        }
        message.isEnabled = !profile.bool("is_editorial") && !isBlocked(profileID, store: store)
        if profile.bool("is_editorial") { message.accessibilityHint = "This editorial collection does not accept private messages" }
        let block = iconButton("icon-block", label: blocked ? "Unblock traveler" : "Block traveler") { [weak self] in
            guard let self else { return }
            self.confirm(blocked ? "Unblock traveler?" : "Block traveler?", message: blocked ? "They may interact with you again." : "Messaging and social interactions with this profile will be restricted.", destructive: !blocked) {
                self.run {
                    try await self.store.perform("safety.block", ["profile_id": .string(self.profileID), "enabled": .bool(!blocked)])
                    if !blocked { self.showBlockSuccess() }
                    try await self.store.refreshCoinState()
                    await self.loadStatistics()
                }
            }
        }
        let primary = line([follow, message], spacing: 8)
        primary.distribution = .fillEqually
        content.addArrangedSubview(line([primary, block], spacing: 8))
    }
}
