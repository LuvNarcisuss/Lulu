import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension TravelNoticeScreen {
    func showBlockSuccess() {
        notice("You can unblock this traveler in Settings under Blocked profiles.", title: "Traveler blocked")
    }
}

@MainActor
func memberName(_ id: String, store: TravelStore) -> String {
    if id == store.userID { return store.profile.string("display_name", fallback: "You") }
    return store.rows("profiles").first { $0.id == id }?.string("display_name", fallback: "Traveler") ?? "Traveler"
}

@MainActor
func isBlocked(_ id: String, store: TravelStore) -> Bool {
    store.rows("blocks").contains {
        ($0.string("blocker_id") == store.userID && $0.string("blocked_id") == id) ||
        ($0.string("blocked_id") == store.userID && $0.string("blocker_id") == id)
    }
}

@MainActor
func chatPreference(_ id: String, store: TravelStore) -> Record {
    store.rows("chat_preferences").first { $0.string("conversation_id") == id && $0.string("user_id") == store.userID } ?? Record()
}

@MainActor
func conversationName(_ record: Record, store: TravelStore) -> String {
    if record.bool("is_group") { return record.string("title", fallback: "Travel group") }
    return record.strings("member_ids").filter { $0 != store.userID }.map { memberName($0, store: store) }.joined(separator: ", ")
}

@MainActor
func choiceStrip(_ titles: [String], selected: Int, changed: @escaping (Int) -> Void) -> UIView {
    let stack = line([], spacing: 8)
    for (index, title) in titles.enumerated() {
        let button = action(title, filled: index == selected) { changed(index) }
        if index == selected { button.accessibilityTraits.insert(.selected) }
        stack.addArrangedSubview(button)
    }
    let scroll = UIScrollView()
    scroll.showsHorizontalScrollIndicator = false
    scroll.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
        stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
        stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
    ])
    return scroll
}

@MainActor
func clearStack(_ stack: UIStackView) {
    stack.arrangedSubviews.forEach { item in stack.removeArrangedSubview(item); item.removeFromSuperview() }
}

@MainActor
func multilineInput(_ placeholder: String, height: CGFloat = 110) -> UITextView {
    let field = UITextView()
    field.font = FontBook.font(16)
    field.adjustsFontForContentSizeCategory = true
    field.backgroundColor = Palette.paper
    field.textColor = Palette.ink
    field.layer.cornerRadius = 14
    field.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
    field.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
    field.accessibilityLabel = placeholder
    return field
}

/// Reads the provider's temporary file while it remains valid, before returning bounded JPEG bytes.
func loadTravelPhoto(_ provider: NSItemProvider, completion: @escaping (Result<Data, Error>) -> Void) {
    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
        do {
            if let error { throw error }
            guard let url else { throw PhotoImportError.unreadable }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size > 0, size <= 30 * 1024 * 1024 else { throw PhotoImportError.tooLarge }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1600,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary),
                  let bytes = UIImage(cgImage: image).jpegData(compressionQuality: 0.82),
                  bytes.count <= 5 * 1024 * 1024 else { throw PhotoImportError.unreadable }
            completion(.success(bytes))
        } catch { completion(.failure(error)) }
    }
}

enum PhotoImportError: LocalizedError {
    case unreadable, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: return "This photo could not be read. Please choose another image."
        case .tooLarge: return "Choose a photo smaller than 30 MB."
        }
    }
}

@MainActor
final class TravelerAvatarView: UIImageView {
    private var loading: Task<Void, Never>?
    init(profile: Record?, store: TravelStore, side: CGFloat) {
        super.init(frame: .zero)
        image = UIImage(named: "icon-profile")
        backgroundColor = Palette.cream
        contentMode = .scaleAspectFill
        clipsToBounds = true; layer.cornerRadius = side * 0.28
        widthAnchor.constraint(equalToConstant: side).isActive = true
        heightAnchor.constraint(equalToConstant: side).isActive = true
        isAccessibilityElement = false
        guard let path = profile?.string("avatar_path"), !path.isEmpty else { return }
        loading = Task { [weak self] in
            do {
                let url = try await store.mediaURL(path)
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 6 * 1024 * 1024,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 180
                      ] as CFDictionary) else { return }
                self?.image = UIImage(cgImage: thumbnail)
            } catch { }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { loading?.cancel() }
}

@MainActor
func conversationAvatar(_ conversation: Record, store: TravelStore) -> UIView {
    func profile(_ id: String) -> Record? {
        id == store.userID ? store.profile : store.rows("profiles").first { $0.id == id && !$0.bool("is_editorial") }
    }
    if !conversation.bool("is_group") {
        let id = conversation.strings("member_ids").first { $0 != store.userID } ?? ""
        return TravelerAvatarView(profile: profile(id), store: store, side: 62)
    }
    let members = Array(Set(conversation.strings("member_ids"))).sorted().compactMap(profile).prefix(9)
    guard !members.isEmpty else {
        let image = UIImageView(image: UIImage(named: "icon-group"))
        image.contentMode = .scaleAspectFit
        image.widthAnchor.constraint(equalToConstant: 62).isActive = true
        image.heightAnchor.constraint(equalToConstant: 62).isActive = true
        return image
    }
    let profiles = Array(members)
    let count = profiles.count <= 4 ? 2 : 3
    let side = (CGFloat(62) - CGFloat(count - 1) * 2) / CGFloat(count)
    let grid = column([], spacing: 2)
    grid.widthAnchor.constraint(equalToConstant: 62).isActive = true
    for offset in stride(from: 0, to: profiles.count, by: count) {
        let row = line([], spacing: 2); row.distribution = .fillEqually
        for index in offset..<min(offset + count, profiles.count) { row.addArrangedSubview(TravelerAvatarView(profile: profiles[index], store: store, side: side)) }
        while row.arrangedSubviews.count < count { row.addArrangedSubview(UIView()) }
        grid.addArrangedSubview(row)
    }
    grid.accessibilityLabel = "Group members"
    return grid
}

@MainActor
func recentChatTime(_ timestamp: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    guard let date else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a" : "MMM d"
    return formatter.string(from: date)
}

@MainActor
func orderedDiscovery(_ records: [Record], order: [String]) -> [Record] {
    let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
    return records.enumerated().sorted {
        let left = positions[$0.element.id] ?? (order.count + $0.offset)
        let right = positions[$1.element.id] ?? (order.count + $1.offset)
        return left < right
    }.map { $0.element }
}

@MainActor
func nextDiscoveryOrder(_ records: [Record], after previousID: String?) -> [String] {
    let ids = records.map(\.id)
    guard ids.count > 1, let previousID, let previous = ids.firstIndex(of: previousID) else { return ids }
    let start = (previous + 1) % ids.count
    return Array(ids[start...]) + Array(ids[..<start])
}

@MainActor
func publisherAvatar(_ profileID: String, store: TravelStore, size: CGFloat = 44, onOpen: @escaping () -> Void) -> UIButton {
    let profile = profileID == store.userID ? store.profile : store.rows("profiles").first { $0.id == profileID }
    let path = profile?.string("avatar_path") ?? ""
    let avatar = remoteImage(path, store: store, height: size, radius: size / 2)
    if path.isEmpty {
        avatar.image = UIImage(named: profile?.bool("is_editorial") == true ? "logo-lulu" : "icon-profile")
        avatar.contentMode = .scaleAspectFit
    }
    avatar.backgroundColor = Palette.cream
    avatar.isUserInteractionEnabled = false
    avatar.translatesAutoresizingMaskIntoConstraints = false
    let button = UIButton(type: .custom)
    button.addSubview(avatar)
    NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: size), button.heightAnchor.constraint(equalToConstant: size),
        avatar.leadingAnchor.constraint(equalTo: button.leadingAnchor), avatar.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        avatar.topAnchor.constraint(equalTo: button.topAnchor), avatar.bottomAnchor.constraint(equalTo: button.bottomAnchor)
    ])
    button.accessibilityLabel = "Open profile for " + (profile?.string("display_name") ?? "traveler")
    button.addAction(UIAction { _ in onOpen() }, for: .touchUpInside)
    return button
}

@MainActor
func publisherIdentity(_ profileID: String, store: TravelStore, onOpen: @escaping () -> Void) -> UIView {
    let name = action(memberName(profileID, store: store), filled: false, onOpen)
    name.configuration?.background.backgroundColor = .clear
    name.configuration?.contentInsets = .init(top: 4, leading: 0, bottom: 4, trailing: 0)
    name.contentHorizontalAlignment = .leading
    return line([publisherAvatar(profileID, store: store, onOpen: onOpen), name], spacing: 8)
}

/// A passive caption overlay; the enclosing cover remains the only tap target.
@MainActor
func attachWorkCaption(to cover: UIButton, location: String? = nil, likes: Int?) {
    let heart = UIImageView(image: UIImage(named: "icon-heart")?.withRenderingMode(.alwaysTemplate))
    heart.tintColor = UIColor(red: 1, green: 0.25, blue: 0.28, alpha: 1)
    heart.contentMode = .scaleAspectFit
    heart.widthAnchor.constraint(equalToConstant: 18).isActive = true
    heart.heightAnchor.constraint(equalToConstant: 18).isActive = true
    let count = text(likes.map { $0.formatted() } ?? "—", 14, color: .white)
    count.numberOfLines = 1
    let likesRow = line([heart, count, UIView()], spacing: 5)
    var views: [UIView] = []
    if let location {
        let label = text(location, 12, color: .white)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        views.append(label)
    }
    views.append(likesRow)
    let caption = column(views, spacing: 2)
    caption.isLayoutMarginsRelativeArrangement = true
    caption.directionalLayoutMargins = .init(top: 7, leading: 9, bottom: 8, trailing: 9)
    caption.backgroundColor = UIColor.black.withAlphaComponent(0.48)
    caption.isUserInteractionEnabled = false
    caption.accessibilityElementsHidden = true
    caption.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(caption)
    NSLayoutConstraint.activate([
        caption.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
        caption.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
        caption.bottomAnchor.constraint(equalTo: cover.bottomAnchor)
    ])
    cover.accessibilityHint = likes.map { "\($0) likes" } ?? "Likes unavailable"
}
