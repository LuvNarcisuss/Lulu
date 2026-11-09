import UIKit
import MapKit
import SafariServices

private final class DestinationPin: NSObject, MKAnnotation {
    let place: Record
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: place.number("latitude"), longitude: place.number("longitude")) }
    var title: String? { place.string("name") }
    var subtitle: String? { place.string("city") + ", " + place.string("country") }
    init(_ place: Record) { self.place = place }
}

final class ExploreController: TravelScreen, MKMapViewDelegate {
    private let map = MKMapView()
    private let results = column(spacing: 16)
    private var query = ""
    private var region = "All"
    private var category = "All places"
    private var showSearch = false
    private var mappedIDs: [String] = []
    private var showingMap = true
    override func viewDidLoad() {
        title = "Explore"
        map.delegate = self
        map.showsCompass = false
        map.showsScale = false
        map.layer.cornerRadius = 26
        map.clipsToBounds = true
        map.heightAnchor.constraint(equalToConstant: 300).isActive = true
        super.viewDidLoad()
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: iconButton("icon-search", label: "Search destinations") { [weak self] in self?.showSearch.toggle(); self?.query = ""; self?.render() }),
            UIBarButtonItem(customView: iconButton("icon-refresh", label: "Refresh destinations") { [weak self] in guard let self else { return }; self.run { try await self.store.refresh() } })
        ]
    }
    override func render() {
        super.render()
        content.addArrangedSubview(text("Somewhere\nworth going.", 37, display: true))
        content.addArrangedSubview(text("Find your next small adventure on the map.", 16, color: Palette.muted))
        if showSearch {
            let search = input("Search places, cities or countries", value: query)
            search.clearButtonMode = .whileEditing
            search.addAction(UIAction { [weak self, weak search] _ in self?.query = search?.text ?? ""; self?.renderResults() }, for: .editingChanged)
            content.addArrangedSubview(search)
        }
        content.addArrangedSubview(chips(["All", "Europe", "North America"], selected: region) { [weak self] value in self?.region = value; self?.render() })
        content.addArrangedSubview(chips(["All places", "City", "Coast", "Nature", "Culture"], selected: category) { [weak self] value in self?.category = value; self?.render() })
        let mapToggle = action(showingMap ? "Show destination list" : "Show destination map", icon: showingMap ? "icon-location" : "icon-map", filled: false) { [weak self] in self?.showingMap.toggle(); self?.render() }
        content.addArrangedSubview(mapToggle)
        if showingMap { content.addArrangedSubview(map) }
        content.addArrangedSubview(results)
        renderResults()
    }
    private var destinations: [Record] {
        store.rows("places").filter { place in
            (region == "All" || place.string("region") == region) &&
            matchesCategory(place.string("category")) &&
            (query.isEmpty || [place.string("name"), place.string("city"), place.string("country")].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    private func matchesCategory(_ value: String) -> Bool {
        switch category {
        case "All places": return true
        case "Nature": return ["Nature", "Mountains", "National Park"].contains(value)
        case "Culture": return ["Heritage", "Architecture"].contains(value)
        case "Coast": return ["Coast", "Waterfront"].contains(value)
        default: return value == category
        }
    }
    private func renderResults() {
        results.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let places = destinations
        results.addArrangedSubview(text("\(places.count) places to explore", 21, display: true))
        if places.isEmpty {
            results.addArrangedSubview(card([text("No places found", 23, display: true), text("Try another region or a shorter search.", 16, color: Palette.muted)]))
        }
        for place in places {
            let photo = remoteImage(place.string("photo_path"), store: store, height: 185)
            photo.accessibilityLabel = place.string("name")
            results.addArrangedSubview(card([
                photo,
                line([text(place.string("name"), 24, display: true), text(place.string("category"), 13, color: Palette.muted)]),
                text(place.string("city") + ", " + place.string("country"), 15, color: Palette.muted),
                text(place.string("summary"), 16),
                action("Explore this place", icon: "icon-route", filled: false) { [weak self] in guard let self else { return }; self.push(PlaceController(store: self.store, placeID: place.id)) }
            ]))
        }
        let ids = places.map(\.id)
        guard ids != mappedIDs else { return }
        mappedIDs = ids
        map.removeAnnotations(map.annotations)
        let pins = places.map(DestinationPin.init)
        map.addAnnotations(pins)
        if !pins.isEmpty { map.showAnnotations(pins, animated: !UIAccessibility.isReduceMotionEnabled) }
    }
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is DestinationPin else { return nil }
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: "destination") ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "destination")
        view.annotation = annotation
        view.image = UIImage(named: "icon-location")?.preparingThumbnail(of: CGSize(width: 38, height: 44))
        view.canShowCallout = true
        view.rightCalloutAccessoryView = iconButton("icon-route", label: "Open destination") { [weak self, weak view] in
            guard let self, let pin = view?.annotation as? DestinationPin else { return }
            self.push(PlaceController(store: self.store, placeID: pin.place.id))
        }
        return view
    }
}

final class PlaceController: TravelScreen {
    private let placeID: String
    init(store: TravelStore, placeID: String) { self.placeID = placeID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func render() {
        super.render()
        guard let place = store.rows("places").first(where: { $0.id == placeID }) else {
            content.addArrangedSubview(text("This place is no longer available.", 22, display: true)); return
        }
        title = place.string("city", fallback: "Destination")
        content.addArrangedSubview(remoteImage(place.string("photo_path"), store: store, height: 275, radius: 28))
        content.addArrangedSubview(text(place.string("name"), 36, display: true))
        content.addArrangedSubview(text(place.string("city") + " · " + place.string("country") + " · " + place.string("category"), 15, color: Palette.muted))
        content.addArrangedSubview(text(place.string("summary"), 18))
        let saved = store.rows("saved_places").contains { $0.string("place_id") == placeID }
        content.addArrangedSubview(line([
            action(saved ? "Saved" : "Save place", icon: "icon-save", filled: false) { [weak self] in
                guard let self else { return }
                self.run { try await self.store.perform("place.save", ["place_id": .string(self.placeID), "enabled": .bool(!saved)]) }
            },
            action("Add to journey", icon: "icon-journeys") { [weak self] in guard let self else { return }; self.push(JourneyPickerController(store: self.store, placeID: self.placeID)) }
        ]))
        content.addArrangedSubview(card([
            text("Before you go", 24, display: true),
            text(place.string("best_time", fallback: "Plan around the weather and current local advice."), 16),
            text(place.string("practical_tip", fallback: "Check the official destination website before setting out."), 16, color: Palette.muted),
            action("Directions in Maps", icon: "icon-map", filled: false) {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.number("latitude"), longitude: place.number("longitude"))))
                item.name = place.string("name")
                item.openInMaps()
            }
        ]))
        let guides = store.rows("guides").filter { $0.string("place_id") == placeID }
        content.addArrangedSubview(text("A good way to explore", 28, display: true))
        for guide in guides {
            var views: [UIView] = [text(guide.string("title"), 25, display: true), text(guide.string("intro"), 17)]
            for section in guide.records("sections") {
                views.append(text(section.string("title"), 20, display: true))
                views.append(text(section.string("body"), 16))
            }
            views.append(text("Original travel notes informed by \(guide.string("source_name")). Conditions, reservations and opening times can change.", 13, color: Palette.muted))
            views.append(action("Read the official guide", icon: "icon-globe", filled: false) { [weak self] in self?.openSource(guide.string("source_url")) })
            content.addArrangedSubview(card(views))
        }
        let clips = store.rows("clips").filter { $0.string("place_id") == placeID }
        if !clips.isEmpty {
            content.addArrangedSubview(text("See it in motion", 27, display: true))
            for (index, clip) in clips.enumerated() {
                content.addArrangedSubview(action(clip.string("title"), icon: "icon-shorts", filled: false) { [weak self] in guard let self else { return }; self.push(ClipFeedController(store: self.store, clips: clips, initialIndex: index)) })
            }
        }
        content.addArrangedSubview(action("Share this destination", icon: "icon-share", filled: false) { [weak self] in
            guard let self else { return }
            var values: [Any] = [place.string("name") + " — " + place.string("summary")]
            if let url = URL(string: place.string("source_url")), url.scheme == "https" { values.append(url) }
            self.share(values)
        })
    }
    private func openSource(_ value: String) {
        guard let url = URL(string: value), url.scheme == "https" else { notice("The source link is unavailable."); return }
        present(SFSafariViewController(url: url), animated: true)
    }
}

@MainActor func chips(_ items: [String], selected: String, change: @escaping (String) -> Void) -> UIView {
    let scroll = UIScrollView()
    scroll.showsHorizontalScrollIndicator = false
    let stack = line(spacing: 8)
    for item in items {
        let button = action(item, filled: item == selected) { change(item) }
        stack.addArrangedSubview(button)
    }
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
        stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
    ])
    return scroll
}
