import UIKit
import MapKit
import MapLibre
import SafariServices

private final class DestinationPin: NSObject, MLNAnnotation {
    let place: Record
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: place.number("latitude"), longitude: place.number("longitude")) }
    var title: String? { place.string("name") }
    var subtitle: String? { place.string("city") + ", " + place.string("country") }
    init(_ place: Record) { self.place = place }
}

final class ExploreController: TravelScreen, MLNMapViewDelegate, UIPopoverPresentationControllerDelegate {
    override var usesScrolling: Bool { false }
    private let mapStyleURL = Bundle.main.url(forResource: "ExploreMapStyle", withExtension: "json")
    private lazy var map: MLNMapView = {
        if let mapStyleURL { return MLNMapView(frame: .zero, styleURL: mapStyleURL) }
        return MLNMapView(frame: .zero, styleJSON: #"{"version":8,"sources":{},"layers":[]}"#)
    }()
    private let list = UIScrollView()
    private let results = column(spacing: 16)
    private let pane = UIView()
    private lazy var filterButton: UIButton = iconButton("icon-filter", label: "Destination filters") { [weak self] in
        guard let self else { return }
        self.showFilters(from: self.filterButton)
    }
    private let mapStatus = text("No places found", 16)
    private lazy var retryMap = action("Retry map", icon: "icon-refresh", filled: false) { [weak self] in
        self?.map.reloadStyle(nil)
    }
    private lazy var mapNotice = card([mapStatus, retryMap])
    private let mapSelection = column()
    private var mapLoadFailed = false
    private var noMapResults = false
    private var query = ""
    private var region = "All"
    private var category = "All places"
    private var showSearch = false
    private var mappedIDs: [String] = []
    private var needsPinFit = false
    private var showingMap = true
    override func viewDidLoad() {
        title = "Explore"
        content.spacing = 12
        mapLoadFailed = mapStyleURL == nil
        map.delegate = self
        map.showsCompassView = false
        map.showsScale = false
        map.layer.cornerRadius = 26
        map.clipsToBounds = true
        configurePanes()
        super.viewDidLoad()
        let bottom = content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        bottom.priority = .defaultHigh
        bottom.isActive = true
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: iconButton("icon-search", label: "Search destinations") { [weak self] in self?.showSearch.toggle(); self?.query = ""; self?.render() }),
            UIBarButtonItem(customView: iconButton("icon-refresh", label: "Refresh destinations") { [weak self] in guard let self else { return }; self.run {
                try await self.store.refresh()
                try await self.store.refreshCoinState()
            } })
        ]
    }
    private func configurePanes() {
        list.keyboardDismissMode = .interactive
        list.contentInsetAdjustmentBehavior = .never
        for child in [map, list] as [UIView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            pane.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
                child.topAnchor.constraint(equalTo: pane.topAnchor),
                child.bottomAnchor.constraint(equalTo: pane.bottomAnchor)
            ])
        }
        results.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(results)
        let listContent = list.contentLayoutGuide
        for overlay in [mapNotice, mapSelection] {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            pane.addSubview(overlay)
        }
        NSLayoutConstraint.activate([
            results.leadingAnchor.constraint(equalTo: listContent.leadingAnchor),
            results.trailingAnchor.constraint(equalTo: listContent.trailingAnchor),
            results.topAnchor.constraint(equalTo: listContent.topAnchor),
            results.bottomAnchor.constraint(equalTo: listContent.bottomAnchor),
            results.widthAnchor.constraint(equalTo: list.frameLayoutGuide.widthAnchor),
            mapNotice.topAnchor.constraint(equalTo: pane.topAnchor, constant: 16),
            mapNotice.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            mapNotice.widthAnchor.constraint(lessThanOrEqualTo: pane.widthAnchor, constant: -32),
            mapSelection.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 12),
            mapSelection.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -12),
            mapSelection.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -44)
        ])
    }

    override func render() {
        if presentedViewController is DestinationFiltersController {
            renderResults()
            return
        }
        super.render()
        if showSearch {
            let search = input("Search places, cities or countries", value: query)
            search.clearButtonMode = .whileEditing
            search.addAction(UIAction { [weak self, weak search] _ in self?.query = search?.text ?? ""; self?.renderResults() }, for: .editingChanged)
            content.addArrangedSubview(search)
        }
        let mapToggle = action(showingMap ? "Show list" : "Show map", icon: showingMap ? "icon-location" : "icon-map", filled: false) { [weak self] in
            guard let self else { return }
            self.showingMap.toggle()
            if !self.showingMap, let selected = self.map.selectedAnnotations.first {
                self.map.deselectAnnotation(selected, animated: false)
            }
            self.render()
        }
        mapToggle.accessibilityLabel = showingMap ? "Show destination list" : "Show destination map"
        filterButton.accessibilityValue = "\(region == "All" ? "All regions" : region), \(category)"
        let hasFilters = region != "All" || category != "All places"
        filterButton.backgroundColor = hasFilters ? Palette.ochre.withAlphaComponent(0.6) : Palette.paper
        content.addArrangedSubview(line([mapToggle, filterButton], spacing: 8))
        content.addArrangedSubview(pane)
        map.isHidden = !showingMap
        list.isHidden = showingMap
        mapSelection.isHidden = !showingMap || mapSelection.arrangedSubviews.isEmpty
        renderResults()
    }

    private func showFilters(from button: UIButton) {
        guard presentedViewController == nil else { return }
        view.endEditing(true)
        let filters = DestinationFiltersController(region: region, category: category) { [weak self] region, category in
            guard let self, self.region != region || self.category != category else { return }
            self.region = region
            self.category = category
            self.list.setContentOffset(.zero, animated: false)
            self.render()
        }
        filters.loadViewIfNeeded()
        if let popover = filters.popoverPresentationController {
            popover.sourceView = button
            popover.sourceRect = button.bounds
            popover.permittedArrowDirections = .up
            popover.backgroundColor = Palette.cream
            popover.delegate = self
        }
        present(filters, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard showingMap, needsPinFit, !map.bounds.isEmpty, let annotations = map.annotations else { return }
        needsPinFit = false
        if let single = annotations.first, annotations.count == 1 {
            map.setCenter(single.coordinate, zoomLevel: 13, animated: !UIAccessibility.isReduceMotionEnabled)
        } else {
            map.showAnnotations(annotations, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
    private var destinations: [Record] {
        store.visiblePlaces.filter { place in
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
        let places = destinations
        noMapResults = places.isEmpty
        updateMapNotice()
        if showingMap {
            let ids = places.map(\.id)
            guard ids != mappedIDs else { return }
            mappedIDs = ids
            if let annotations = map.annotations { map.removeAnnotations(annotations) }
            clearMapSelection()
            map.addAnnotations(places.map(DestinationPin.init))
            needsPinFit = !places.isEmpty
            view.setNeedsLayout()
        } else {
            renderList(places)
        }
    }

    private func renderList(_ places: [Record]) {
        results.arrangedSubviews.forEach { $0.removeFromSuperview() }
        results.addArrangedSubview(text("\(places.count) places to explore", 21, display: true))
        if places.isEmpty {
            results.addArrangedSubview(card([text("No places found", 23, display: true), text("Try another region or a shorter search.", 16, color: Palette.muted)]))
        }
        for place in places {
            let openGuide = { [weak self] in
                guard let self else { return }
                self.push(PlaceController(store: self.store, placeID: place.id))
            }
            let photo = remoteImage(place.string("photo_path"), store: store, height: 185)
            let cover = UIButton(type: .custom)
            cover.accessibilityLabel = "Open guide for " + place.string("name")
            cover.addAction(UIAction { _ in openGuide() }, for: .touchUpInside)
            photo.translatesAutoresizingMaskIntoConstraints = false
            cover.addSubview(photo)
            NSLayoutConstraint.activate([
                photo.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
                photo.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
                photo.topAnchor.constraint(equalTo: cover.topAnchor),
                photo.bottomAnchor.constraint(equalTo: cover.bottomAnchor)
            ])
            var views: [UIView] = [
                cover,
                line([text(place.string("name"), 24, display: true), text(place.string("category"), 13, color: Palette.muted)]),
                text(place.string("city") + ", " + place.string("country"), 15, color: Palette.muted),
                text(place.string("summary"), 16)
            ]
            let prices = store.guideOffers.filter { $0.string("place_id") == place.id && $0.string("status") == "published" }.map { $0.int("price_coins") }
            if let lowest = prices.min() {
                let summary = lowest > 0 ? "Guides from \(lowest) coins" : (prices.contains { $0 > 0 } ? "Free and paid guides" : "Free guides")
                views.append(text(summary, 14, color: Palette.teal))
            }
            views.append(action("Explore this place", icon: "icon-route", filled: false, openGuide))
            results.addArrangedSubview(card(views))
        }
    }
    private func updateMapNotice() {
        mapStatus.text = mapLoadFailed ? "Street map unavailable" : "No places found"
        retryMap.isHidden = !mapLoadFailed || mapStyleURL == nil
        mapNotice.isHidden = !showingMap || (!mapLoadFailed && !noMapResults)
    }

    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
        mapLoadFailed = true
        updateMapNotice()
    }

    func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
        mapLoadFailed = mapStyleURL == nil
        updateMapNotice()
    }

    func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
        if let cached = mapView.dequeueReusableAnnotationImage(withIdentifier: "destination") { return cached }
        guard let image = UIImage(named: "icon-location")?.preparingThumbnail(of: CGSize(width: 38, height: 44)) else { return nil }
        return MLNAnnotationImage(image: image, reuseIdentifier: "destination")
    }

    func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
        guard let pin = annotation as? DestinationPin else { return }
        clearMapSelection()
        let open = iconButton("icon-route", label: "Open destination") { [weak self] in
            guard let self else { return }
            self.push(PlaceController(store: self.store, placeID: pin.place.id))
        }
        let summary = column([
            text(pin.place.string("name"), 21, display: true),
            text(pin.subtitle ?? "", 14, color: Palette.muted)
        ], spacing: 4)
        mapSelection.addArrangedSubview(card([line([summary, open])]))
        mapSelection.isHidden = !showingMap
    }

    func mapView(_ mapView: MLNMapView, didDeselect annotation: MLNAnnotation) {
        clearMapSelection()
    }

    private func clearMapSelection() {
        mapSelection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        mapSelection.isHidden = true
    }
}

private final class DestinationFiltersController: UIViewController {
    private let region: String
    private let category: String
    private let onSelect: (String, String) -> Void

    init(region: String, category: String, onSelect: @escaping (String, String) -> Void) {
        self.region = region
        self.category = category
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.cream
        let body = column(spacing: 6)
        body.addArrangedSubview(text("Region", 17, display: true))
        body.addArrangedSubview(options(["All", "Europe", "North America"], selected: region) { [weak self] value in
            guard let self else { return }
            self.choose(region: value, category: self.category)
        })
        body.addArrangedSubview(text("Category", 17, display: true))
        for row in [["All places", "City", "Coast"], ["Nature", "Culture"]] {
            body.addArrangedSubview(options(row, selected: category) { [weak self] value in
                guard let self else { return }
                self.choose(region: self.region, category: value)
            })
        }

        body.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(body)
        let margins = view.layoutMarginsGuide
        view.insetsLayoutMarginsFromSafeArea = false
        view.directionalLayoutMargins = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: margins.topAnchor),
            body.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: margins.bottomAnchor)
        ])
        let width: CGFloat = 284
        let size = body.systemLayoutSizeFitting(
            CGSize(width: width - 24, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        preferredContentSize = CGSize(width: width, height: ceil(size.height) + 24)
    }

    private func choose(region: String, category: String) {
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [onSelect] in onSelect(region, category) }
    }

    private func options(_ titles: [String], selected: String, change: @escaping (String) -> Void) -> UIStackView {
        let buttons = titles.map { title in
            let label = title == "North America" ? "N. America" : title
            let button = action(label, filled: title == selected) { change(title) }
            button.configuration?.contentInsets = .init(top: 7, leading: 6, bottom: 7, trailing: 6)
            button.accessibilityLabel = title == "All" ? "All regions" : title
            if title == selected { button.accessibilityTraits.insert(.selected) }
            return button
        }
        let row = line(buttons, spacing: 5)
        row.alignment = .fill
        row.distribution = .fillEqually
        return row
    }
}

final class PlaceController: TravelScreen {
    private let placeID: String
    init(store: TravelStore, placeID: String) { self.placeID = placeID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func render() {
        super.render()
        guard let place = store.visiblePlaces.first(where: { $0.id == placeID }) else {
            navigationItem.rightBarButtonItems = nil
            content.addArrangedSubview(text("This guide is unavailable. You can restore hidden guides in Settings.", 22, display: true))
            return
        }
        title = place.string("city", fallback: "Destination")
        let report = iconButton("icon-report", label: "Report guide") { [weak self] in
            guard let self else { return }
            self.push(ReportController(store: self.store, kind: "place", targetID: self.placeID))
        }
        let hide = iconButton("icon-block", label: "Hide guide") { [weak self] in self?.hideGuide() }
        navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: hide), UIBarButtonItem(customView: report)]
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
        content.addArrangedSubview(text("A good way to explore", 28, display: true))
        let guides = store.rows("guides").filter { $0.string("place_id") == placeID }
        let offers = store.guideOffers.filter {
            $0.string("place_id") == placeID &&
            ($0.string("status") == "published" || $0.string("author_id") == store.userID) &&
            ($0.string("author_id").isEmpty || !isBlocked($0.string("author_id"), store: store))
        }
        if store.hasCoinState {
            let reported = Set(store.rows("reports").filter { $0.string("target_kind") == "guide" }.map { $0.string("target_id") })
            for offer in offers where !reported.contains(offer.string("guide_id")) {
                let guide = guides.first { $0.id == offer.string("guide_id") }
                content.addArrangedSubview(guideCard(offer, guide: guide))
            }
        } else {
            for guide in guides {
                content.addArrangedSubview(card(guideContent(guide)))
            }
            content.addArrangedSubview(action("Refresh guide prices", icon: "icon-refresh", filled: false) { [weak self] in
                guard let self else { return }
                self.run { try await self.store.refreshCoinState() }
            })
        }
        content.addArrangedSubview(action("Write a guide for this place", icon: "icon-add", filled: false) { [weak self] in
            guard let self else { return }
            self.push(GuideEditorController(store: self.store, place: place))
        })
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
    private func guideCard(_ offer: Record, guide: Record?) -> UIView {
        let author = offer.string("author_id")
        let mine = author == store.userID
        let guideID = offer.string("guide_id")
        let price = offer.int("price_coins")
        var views: [UIView] = []
        if !author.isEmpty {
            views.append(text(memberName(author, store: store), 15, color: Palette.muted))
        }
        if mine {
            views.append(text("Status: " + offer.string("status").capitalized, 14, color: Palette.muted))
        }
        let priceLabel = price == 0 ? "Free" : (offer.bool("unlocked") ? "Unlocked" : "\(price) coins")
        views.append(text(priceLabel, 14, color: Palette.teal))
        if let guide {
            views += guideContent(guide)
        } else {
            views.append(text(offer.string("title"), 24, display: true))
            views.append(text(offer.string("preview"), 16))
            if price > 0 && !offer.bool("unlocked") && !mine {
                let afford = store.balance >= price
                views.append(action(afford ? "Unlock for \(price) coins" : "Get coins to unlock", icon: "icon-wallet") { [weak self] in
                    guard let self else { return }
                    if afford { self.unlockGuide(guideID, price: price) }
                    else { self.push(WalletController(store: self.store)) }
                })
            } else {
                views.append(action("Refresh guide", icon: "icon-refresh", filled: false) { [weak self] in
                    guard let self else { return }
                    self.run { try await self.store.refresh() }
                })
            }
        }
        if mine {
            views.append(action("Edit coin price", icon: "icon-edit", filled: false) { [weak self] in
                guard let self else { return }
                self.push(GuideEditorController(store: self.store, offer: offer))
            })
        } else if !author.isEmpty {
            views.append(action("Guide safety", icon: "icon-more", filled: false) { [weak self] in
                self?.showGuideSafety(guideID: guideID, author: author)
            })
        }
        return card(views)
    }

    private func guideContent(_ guide: Record) -> [UIView] {
        var views: [UIView] = [text(guide.string("title"), 25, display: true), text(guide.string("intro"), 17)]
        for section in guide.records("sections") {
            views.append(text(section.string("title"), 20, display: true))
            views.append(text(section.string("body"), 16))
        }
        let source = guide.string("source_url")
        if !source.isEmpty {
            views.append(text("Original travel notes informed by \(guide.string("source_name")). Conditions, reservations and opening times can change.", 13, color: Palette.muted))
            views.append(action("Read the official guide", icon: "icon-globe", filled: false) { [weak self] in self?.openSource(source) })
        }
        return views
    }

    private func unlockGuide(_ id: String, price: Int) {
        confirm("Unlock this guide?", message: "This will spend \(price) coins from your wallet.", actionTitle: "Unlock guide") { [weak self] in
            guard let self else { return }
            self.run {
                try await self.store.perform("guide.unlock", ["target_guide": .string(id), "expected_price": .number(Double(price))])
            }
        }
    }

    private func showGuideSafety(guideID: String, author: String) {
        let dialog = TravelDialogController(title: "Guide safety", message: "Report this guide or block its author.", choices: [
            ("Report guide", false, { [weak self] in
                guard let self else { return }
                self.push(ReportController(store: self.store, kind: "guide", targetID: guideID))
            }),
            ("Block author", true, { [weak self] in
                guard let self else { return }
                self.run {
                    try await self.store.perform("safety.block", ["profile_id": .string(author), "enabled": .bool(true)])
                    try await self.store.refreshCoinState()
                }
            }),
            ("Cancel", false, {})
        ])
        present(dialog, animated: true)
    }

    private func hideGuide() {
        confirm("Hide this guide?", message: "It will be hidden from your map, guide list and saved guides. You can restore it in Settings.", actionTitle: "Hide guide") { [weak self] in
            guard let self else { return }
            self.run {
                try await self.store.perform("safety.hide_place", ["place_id": .string(self.placeID), "enabled": .bool(true)])
                if self.navigationController?.topViewController === self {
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }
    }

    private func openSource(_ value: String) {
        guard let url = URL(string: value), url.scheme == "https" else { notice("The source link is unavailable."); return }
        present(SFSafariViewController(url: url), animated: true)
    }
}

final class MyGuidesController: TravelScreen {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { try? await store.refreshCoinState() }
    }

    override func render() {
        super.render()
        title = "My guides"
        appendMyGuides()
    }
}

@MainActor
extension TravelScreen {
    func appendMyGuides() {
        let mine = store.guideOffers.filter { $0.string("author_id") == store.userID }
        if mine.isEmpty {
            content.addArrangedSubview(text(store.hasCoinState ? "Choose a destination in Explore to write your first guide." : "Your guides could not be loaded.", color: Palette.muted))
        }
        for offer in mine {
            let price = offer.int("price_coins")
            content.addArrangedSubview(card([
                text(offer.string("title"), 23, display: true),
                text(offer.string("status").capitalized + " · " + (price == 0 ? "Free" : "\(price) coins"), color: Palette.muted),
                action("Edit coin price", icon: "icon-edit", filled: false) { [weak self] in
                    guard let self else { return }
                    self.push(GuideEditorController(store: self.store, offer: offer))
                }
            ]))
        }
        content.addArrangedSubview(action("Refresh guides", icon: "icon-refresh", filled: false) { [weak self] in
            guard let self else { return }
            self.run { try await self.store.refreshCoinState() }
        })
    }
}

private final class GuideEditorController: TravelScreen {
    private let place: Record?
    private let offer: Record?
    private let guideID = UUID().uuidString.lowercased()
    private let guideTitle = input("Guide title")
    private let preview = multilineInput("Short preview", height: 104)
    private let body = multilineInput("Travel notes", height: 210)
    private let price = input("0 for a free guide", value: "0")
    private let rights = UISwitch()

    init(store: TravelStore, place: Record) {
        self.place = place
        offer = nil
        super.init(store: store)
    }

    init(store: TravelStore, offer: Record) {
        place = nil
        self.offer = offer
        super.init(store: store)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        automaticRefresh = false
        price.keyboardType = .numberPad
        if let offer { price.text = String(offer.int("price_coins")) }
        super.viewDidLoad()
    }

    override func render() {
        super.render()
        title = offer == nil ? "Write a guide" : "Edit coin price"
        if let place {
            content.addArrangedSubview(text(place.string("name"), 27, display: true))
            content.addArrangedSubview(guideTitle)
            content.addArrangedSubview(text("Preview · 10 to 500 characters", 14, color: Palette.muted))
            content.addArrangedSubview(preview)
            content.addArrangedSubview(text("Travel notes · 40 to 8,000 characters", 14, color: Palette.muted))
            content.addArrangedSubview(body)
            rights.accessibilityLabel = "I wrote this guide and have the right to publish it"
            content.addArrangedSubview(line([text("I wrote this guide and have the right to publish it.", 14), rights]))
            content.addArrangedSubview(text("Your guide is submitted for review before it appears publicly.", 14, color: Palette.muted))
        } else if let offer {
            content.addArrangedSubview(text(offer.string("title"), 24, display: true))
        }
        content.addArrangedSubview(text("Coin price", 20, display: true))
        content.addArrangedSubview(text("Enter a whole number from 0 to 10,000. A price of 0 makes the guide free.", 15, color: Palette.muted))
        content.addArrangedSubview(price)
        content.addArrangedSubview(action(offer == nil ? "Submit guide" : "Save price", icon: "icon-check") { [weak self] in self?.save() })
    }

    private func save() {
        view.endEditing(true)
        guard let amount = Int(price.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              (0...10000).contains(amount) else {
            notice("Enter a whole coin price from 0 to 10,000.")
            return
        }
        let priceValue = JSONValue.number(Double(amount))
        if let offer {
            run {
                try await self.store.perform("guide.price", ["target_guide": .string(offer.string("guide_id")), "coin_price": priceValue])
                if self.navigationController?.topViewController === self {
                    self.navigationController?.popViewController(animated: true)
                }
            }
            return
        }
        guard let place else { return }
        let name = guideTitle.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let excerpt = preview.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...100).contains(name.count), (10...500).contains(excerpt.count), (40...8000).contains(notes.count), rights.isOn else {
            notice("Check the title, preview, travel notes and publishing confirmation.")
            return
        }
        run {
            try await self.store.perform("guide.submit", [
                "guide_key": .string(self.guideID), "destination": .string(place.id),
                "guide_title": .string(name), "guide_preview": .string(excerpt),
                "guide_body": .string(notes), "coin_price": priceValue
            ])
            if self.navigationController?.topViewController === self {
                self.navigationController?.popViewController(animated: true)
            }
        }
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
