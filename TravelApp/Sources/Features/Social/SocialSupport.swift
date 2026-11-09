import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers

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
