import UIKit

final class ShortsController: ClipFeedController {
    init(store: TravelStore) {
        super.init(store: store, discovery: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class ShortsSearchController: TravelScreen {
    private var query = ""
    private var region = "All places"
    private let gallery = column(spacing: 14)
    private var discoveryOrder: [String] = []
    override func viewDidLoad() {
        title = "Search videos"
        super.viewDidLoad()
        let refresh = UIRefreshControl()
        refresh.tintColor = Palette.teal
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            guard let self else { return }
            let previous = self.clips.first?.id
            self.run {
                defer { refresh?.endRefreshing() }
                try await self.store.refresh()
                self.discoveryOrder = nextDiscoveryOrder(self.clips, after: previous)
                self.renderGallery()
            }
        }, for: .valueChanged)
        scroll.refreshControl = refresh
    }
    override func render() {
        super.render()
        let field = input("Search destinations or videos", value: query)
        field.addAction(UIAction { [weak self, weak field] _ in
            self?.query = field?.text ?? ""
            self?.renderGallery()
        }, for: .editingChanged)
        content.addArrangedSubview(field)
        content.addArrangedSubview(chips(["All places", "Europe", "North America", "Saved"], selected: region) { [weak self] value in self?.region = value; self?.render() })
        content.addArrangedSubview(gallery)
        renderGallery()
    }
    private var clips: [Record] {
        let saved = Set(store.rows("saved_clips").map { $0.string("clip_id") })
        let blocked = Set(store.rows("blocks").map { $0.string("blocked_id") })
        let reported = Set(store.rows("reports").filter { $0.string("target_kind") == "clip" }.map { $0.string("target_id") })
        let places = store.rows("places")
        let matching = store.rows("clips").filter { clip in
            let place = places.first { $0.id == clip.string("place_id") }
            return !blocked.contains(clip.string("publisher_id")) && !reported.contains(clip.id) &&
            (region == "All places" || (region == "Saved" ? saved.contains(clip.id) : place?.string("region") == region)) &&
            (query.isEmpty || [clip.string("title"), clip.string("caption"), place?.string("name") ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
        return orderedDiscovery(matching, order: discoveryOrder)
    }
    private func renderGallery() {
        gallery.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let videos = clips
        if videos.isEmpty {
            gallery.addArrangedSubview(card([text(region == "Saved" ? "Keep a little inspiration" : "No videos found", 26, display: true), text(region == "Saved" ? "Save a film to return to it before your next trip." : "Try a different search or refresh the collection.", 16, color: Palette.muted)]))
            return
        }
        let columns = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 2
        for start in stride(from: 0, to: videos.count, by: columns) {
            let row = line(spacing: 12); row.alignment = .top; row.distribution = .fillEqually
            for index in start..<min(start + columns, videos.count) {
                let clip = videos[index]
                let tile = column(spacing: 8)
                let photo = remoteImage(clip.string("cover_path"), store: store, height: columns == 1 ? 330 : 215)
                photo.isAccessibilityElement = false
                tile.addArrangedSubview(photo)
                tile.addArrangedSubview(text(clip.string("title"), 18, display: true))
                let place = store.rows("places").first { $0.id == clip.string("place_id") }
                tile.addArrangedSubview(text(place?.string("city") ?? clip.string("category"), 13, color: Palette.muted))
                let open = action("Watch film", icon: "icon-shorts", filled: false) { [weak self] in guard let self else { return }; self.push(ClipFeedController(store: self.store, clips: videos, initialIndex: index)) }
                tile.addArrangedSubview(publisherAvatar(clip.string("publisher_id"), store: store) { [weak self] in
                    guard let self else { return }
                    self.push(PublicProfileController(store: self.store, profileID: clip.string("publisher_id")))
                })
                tile.addArrangedSubview(open)
                row.addArrangedSubview(tile)
            }
            if row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
            gallery.addArrangedSubview(row)
        }
        gallery.addArrangedSubview(text("Recorded travel films. Source credits are available for each video.", 13, color: Palette.muted))
    }
}
