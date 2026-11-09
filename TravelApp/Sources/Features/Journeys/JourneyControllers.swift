import UIKit

final class JourneysController: TravelScreen {
    override func viewDidLoad() {
        title = "Journeys"
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: iconButton("icon-add", label: "Create journey") { [weak self] in guard let self else { return }; self.push(JourneyEditorController(store: self.store)) })
    }
    override func render() {
        super.render()
        content.addArrangedSubview(text("Make room\nfor the detour.", 36, display: true))
        content.addArrangedSubview(text("A little structure. Plenty of possibility.", 17, color: Palette.muted))
        let journeys = store.rows("journeys")
        if journeys.isEmpty {
            let mark = UIImageView(image: UIImage(named: "icon-journeys"))
            mark.contentMode = .scaleAspectFit
            mark.heightAnchor.constraint(equalToConstant: 90).isActive = true
            content.addArrangedSubview(card([mark, text("Your next chapter starts here", 26, display: true), text("Collect places, sketch your days, and keep the practical details in one private travel book.", 17), action("Plan a journey", icon: "icon-add") { [weak self] in guard let self else { return }; self.push(JourneyEditorController(store: self.store)) }]))
        }
        for journey in journeys {
            let days = journey.records("days")
            let stopCount = days.reduce(0) { $0 + $1.records("stops").count }
            let firstPlaceID = days.flatMap { $0.records("stops") }.first?.string("place_id")
            var views: [UIView] = []
            if let place = store.rows("places").first(where: { $0.id == firstPlaceID }) {
                views.append(remoteImage(place.string("photo_path"), store: store, height: 165))
            }
            views.append(text(journey.string("title"), 28, display: true))
            views.append(text("\(journey.string("start_date")) — \(journey.string("end_date"))", 15, color: Palette.muted))
            views.append(text("\(days.count) days · \(stopCount) places · \(journey.string("currency", fallback: "USD")) \(String(format: "%.0f", journey.number("budget"))) estimated budget", 14, color: Palette.muted))
            views.append(action("Open travel book", icon: "icon-journeys", filled: false) { [weak self] in guard let self else { return }; self.push(JourneyDetailController(store: self.store, journeyID: journey.id)) })
            content.addArrangedSubview(card(views))
        }
        content.addArrangedSubview(action("Find places for your journey", icon: "icon-explore", filled: false) { [weak self] in guard let self else { return }; self.push(ExploreController(store: self.store)) })
    }
}

final class JourneyEditorController: TravelScreen {
    private let original: Record?
    private let initialPlaceID: String?
    private let nameField = input("Journey name")
    private let startField = input("YYYY-MM-DD")
    private let endField = input("YYYY-MM-DD")
    private let budgetField = input("Estimated budget")
    private let currencyField = input("Currency (for example USD)")
    private let notes = UITextView()
    init(store: TravelStore, journey: Record? = nil, initialPlaceID: String? = nil) {
        original = journey; self.initialPlaceID = initialPlaceID
        super.init(store: store)
        automaticRefresh = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        let today = Self.dateString(Date())
        nameField.text = original?.string("title")
        startField.text = original?.string("start_date", fallback: today) ?? today
        endField.text = original?.string("end_date", fallback: today) ?? today
        budgetField.text = original.map { String($0.number("budget")) } ?? "0"
        currencyField.text = original?.string("currency", fallback: "USD") ?? "USD"
        notes.text = original?.string("notes") ?? ""
        notes.font = FontBook.font(17)
        notes.backgroundColor = Palette.paper
        notes.layer.cornerRadius = 16
        notes.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        notes.heightAnchor.constraint(equalToConstant: 160).isActive = true
        notes.accessibilityLabel = "Journey notes"
        budgetField.keyboardType = .decimalPad
        currencyField.autocapitalizationType = .allCharacters
        [startField, endField].forEach { $0.autocorrectionType = .no; $0.keyboardType = .numbersAndPunctuation }
        super.viewDidLoad()
    }
    override func render() {
        super.render()
        title = original == nil ? "New journey" : "Edit journey"
        content.addArrangedSubview(text(original == nil ? "Where will you wander?" : "The practical details", 32, display: true))
        for (label, field) in [("Journey name", nameField), ("First day", startField), ("Last day", endField), ("Estimated budget", budgetField), ("Currency", currencyField)] {
            content.addArrangedSubview(column([text(label, 14, color: Palette.muted), field], spacing: 6))
        }
        content.addArrangedSubview(text("Notes", 20, display: true))
        content.addArrangedSubview(notes)
        content.addArrangedSubview(text("Your journey is private. Budgets are your own estimates and do not create reservations or payments. Up to 30 days per journey.", 14, color: Palette.muted))
        content.addArrangedSubview(action("Save journey", icon: "icon-check") { [weak self] in self?.save() })
    }
    private func save(allowTrim: Bool = false) {
        let title = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let start = startField.text ?? ""
        let end = endField.text ?? ""
        let formatter = Self.formatter()
        let currency = (currencyField.text ?? "").uppercased()
        guard !title.isEmpty, title.count <= 80, let first = formatter.date(from: start), let last = formatter.date(from: end),
              Self.dateString(first) == start, Self.dateString(last) == end, first <= last,
              let budget = Double((budgetField.text ?? "").replacingOccurrences(of: ",", with: ".")), budget.isFinite, budget >= 0, budget <= 100_000_000,
              currency.count == 3, currency.allSatisfy({ $0.isASCII && $0.isLetter }), notes.text.count <= 5000 else {
            notice("Enter a journey name up to 80 characters, valid dates in YYYY-MM-DD format, a nonnegative budget, a three-letter currency and notes up to 5,000 characters."); return
        }
        let count = Self.calendar().dateComponents([.day], from: first, to: last).day ?? 0
        guard count < 30 else { notice("Choose a journey of 30 days or fewer."); return }
        let id = original?.id ?? UUID().uuidString.lowercased()
        var journey = original ?? Record(["id": .string(id), "checklist": .array([])])
        journey["title"] = .string(title); journey["start_date"] = .string(start); journey["end_date"] = .string(end)
        journey["currency"] = .string(currency); journey["budget"] = .number(budget); journey["notes"] = .string(notes.text)
        let oldDays = original?.records("days") ?? []
        let retainedCount = count + 1
        if !allowTrim, oldDays.count > retainedCount,
           oldDays.dropFirst(retainedCount).contains(where: { !$0.records("stops").isEmpty || !$0.string("note").isEmpty }) {
            confirm("Shorten this journey?", message: "The final \(oldDays.count - retainedCount) days and their saved stops and notes will be removed.", destructive: true) { [weak self] in self?.save(allowTrim: true) }
            return
        }
        var days: [JSONValue] = []
        for offset in 0...count {
            guard let date = Self.calendar().date(byAdding: .day, value: offset, to: first) else { continue }
            var day = oldDays.indices.contains(offset) ? oldDays[offset] : Record(["id": .string(UUID().uuidString.lowercased()), "title": .string("Day \(offset + 1)"), "stops": .array([]), "note": .string("")])
            day["date"] = .string(Self.dateString(date))
            if original == nil, offset == 0, let initialPlaceID {
                day["stops"] = .array([Record(["id": .string(UUID().uuidString.lowercased()), "place_id": .string(initialPlaceID), "note": .string("")]).json])
            }
            days.append(day.json)
        }
        journey["days"] = .array(days)
        let payload = journey.values
        run { [weak self] in
            guard let self else { return }
            try await self.store.perform("journey.save", payload)
            if self.original == nil {
                let detail = JourneyDetailController(store: self.store, journeyID: id)
                if let navigation = self.navigationController {
                    var stack = navigation.viewControllers
                    stack.removeLast(); stack.append(detail)
                    navigation.setViewControllers(stack, animated: true)
                }
            } else { self.navigationController?.popViewController(animated: true) }
        }
    }
    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar
    }
    static func formatter() -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = calendar()
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false; return formatter
    }
    static func dateString(_ date: Date) -> String { formatter().string(from: date) }
}

final class JourneyDetailController: TravelScreen {
    private let journeyID: String
    private var selectedDay = 0
    init(store: TravelStore, journeyID: String) { self.journeyID = journeyID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func render() {
        super.render()
        guard let journey = store.rows("journeys").first(where: { $0.id == journeyID }) else {
            content.addArrangedSubview(text("This journey is unavailable.", 24, display: true)); return
        }
        title = "Travel book"
        content.addArrangedSubview(text(journey.string("title"), 36, display: true))
        content.addArrangedSubview(text(journey.string("start_date") + " — " + journey.string("end_date"), 16, color: Palette.muted))
        content.addArrangedSubview(line([
            action("Edit details", icon: "icon-edit", filled: false) { [weak self] in guard let self else { return }; self.push(JourneyEditorController(store: self.store, journey: journey)) },
            action("Share plan", icon: "icon-share", filled: false) { [weak self] in self?.sharePlan(journey) }
        ]))
        let days = journey.records("days")
        selectedDay = min(selectedDay, max(0, days.count - 1))
        if !days.isEmpty {
            let titles = days.enumerated().map { "Day \($0.offset + 1)" }
            content.addArrangedSubview(chips(titles, selected: titles[selectedDay]) { [weak self] value in self?.selectedDay = titles.firstIndex(of: value) ?? 0; self?.render() })
            let day = days[selectedDay]
            content.addArrangedSubview(text(day.string("date") + " · " + day.string("title"), 22, display: true))
            let stops = day.records("stops")
            if stops.isEmpty { content.addArrangedSubview(card([text("Leave a little space", 24, display: true), text("Add a saved place or discover somewhere new.", 16, color: Palette.muted)])) }
            for (index, stop) in stops.enumerated() {
                let place = store.rows("places").first { $0.id == stop.string("place_id") }
                var views: [UIView] = [text("\(index + 1). " + (place?.string("name") ?? "Unavailable place"), 23, display: true)]
                if let place {
                    views.insert(remoteImage(place.string("photo_path"), store: store, height: 150), at: 0)
                    views.append(action("Open place", icon: "icon-location", filled: false) { [weak self] in guard let self else { return }; self.push(PlaceController(store: self.store, placeID: place.id)) })
                }
                if !stop.string("note").isEmpty { views.append(text(stop.string("note"), 16)) }
                views.append(action("Edit stop note", icon: "icon-edit", filled: false) { [weak self] in
                    guard let self else { return }
                    self.push(TextNoteController(store: self.store, heading: "Stop note", value: stop.string("note")) { [weak self] value in
                        guard let self, let current = self.currentJourney else { return }
                        var currentDays = current.records("days")
                        guard currentDays.indices.contains(self.selectedDay) else { return }
                        var currentStops = currentDays[self.selectedDay].records("stops")
                        guard let location = currentStops.firstIndex(where: { $0.id == stop.id }) else { return }
                        currentStops[location]["note"] = .string(value)
                        currentDays[self.selectedDay]["stops"] = .array(currentStops.map(\.json))
                        var next = current; next["days"] = .array(currentDays.map(\.json))
                        try await self.store.perform("journey.save", next.values)
                    })
                })
                let earlier = action("Earlier", filled: false) { [weak self] in self?.moveStop(stop.id, offset: -1) }
                let later = action("Later", filled: false) { [weak self] in self?.moveStop(stop.id, offset: 1) }
                earlier.isEnabled = index > 0; later.isEnabled = index < stops.count - 1
                views.append(line([earlier, later, iconButton("icon-trash", label: "Remove stop") { [weak self] in self?.removeStop(stop.id) }]))
                content.addArrangedSubview(card(views))
            }
            content.addArrangedSubview(action("Add a stop", icon: "icon-add") { [weak self] in guard let self else { return }; self.push(JourneyPlacePickerController(store: self.store, journeyID: self.journeyID, dayIndex: self.selectedDay)) })
            content.addArrangedSubview(action("Day notes", icon: "icon-edit", filled: false) { [weak self] in
                guard let self else { return }
                self.push(TextNoteController(store: self.store, heading: "Day notes", value: day.string("note")) { [weak self] value in
                    guard let self, var current = self.currentJourney else { return }
                    var days = current.records("days"); guard days.indices.contains(self.selectedDay) else { return }
                    days[self.selectedDay]["note"] = .string(value); current["days"] = .array(days.map(\.json))
                    try await self.store.perform("journey.save", current.values)
                })
            })
            if !day.string("note").isEmpty { content.addArrangedSubview(card([text(day.string("note"), 17)])) }
        }
        content.addArrangedSubview(text("Pack the essentials", 28, display: true))
        for item in journey.records("checklist") {
            content.addArrangedSubview(line([
                action(item.string("title"), icon: item.bool("done") ? "icon-check" : "icon-save", filled: false) { [weak self] in self?.toggleItem(item.id) },
                iconButton("icon-trash", label: "Remove checklist item") { [weak self] in self?.removeItem(item.id) }
            ]))
        }
        content.addArrangedSubview(action("Add checklist item", icon: "icon-add", filled: false) { [weak self] in
            guard let self else { return }
            self.push(TextNoteController(store: self.store, heading: "Checklist item", value: "", limit: 120) { [weak self] value in
                guard let self, var current = self.currentJourney else { return }
                var items = current.records("checklist"); items.append(Record(["id": .string(UUID().uuidString.lowercased()), "title": .string(value), "done": .bool(false)]))
                current["checklist"] = .array(items.map(\.json)); try await self.store.perform("journey.save", current.values)
            })
        })
        content.addArrangedSubview(card([
            text("A little peace of mind", 25, display: true),
            text("Estimated budget: \(journey.string("currency")) \(String(format: "%.2f", journey.number("budget")))", 18),
            text(journey.string("notes", fallback: "Keep booking references, packing reminders and small discoveries in your private notes."), 16, color: Palette.muted)
        ]))
        content.addArrangedSubview(action("Delete journey", icon: "icon-trash", filled: false) { [weak self] in
            self?.confirm("Delete this journey?", message: "Its itinerary, checklist and notes will be permanently removed.", destructive: true) { [weak self] in
                guard let self else { return }; self.run { try await self.store.perform("journey.delete", ["journey_id": .string(self.journeyID)]); self.navigationController?.popViewController(animated: true) }
            }
        })
    }
    private var currentJourney: Record? { store.rows("journeys").first { $0.id == journeyID } }
    private func editDay(_ edit: (inout [Record]) -> Void) {
        guard var journey = currentJourney else { return }
        var days = journey.records("days"); guard days.indices.contains(selectedDay) else { return }
        var stops = days[selectedDay].records("stops"); edit(&stops)
        days[selectedDay]["stops"] = .array(stops.map(\.json)); journey["days"] = .array(days.map(\.json))
        let payload = journey.values
        run { [weak self] in guard let self else { return }; try await self.store.perform("journey.save", payload) }
    }
    private func moveStop(_ id: String, offset: Int) {
        editDay { stops in guard let index = stops.firstIndex(where: { $0.id == id }), stops.indices.contains(index + offset) else { return }; stops.swapAt(index, index + offset) }
    }
    private func removeStop(_ id: String) { editDay { $0.removeAll { $0.id == id } } }
    private func toggleItem(_ id: String) {
        guard var current = currentJourney else { return }
        var items = current.records("checklist"); guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index]["done"] = .bool(!items[index].bool("done")); current["checklist"] = .array(items.map(\.json))
        let payload = current.values; run { [weak self] in guard let self else { return }; try await self.store.perform("journey.save", payload) }
    }
    private func removeItem(_ id: String) {
        guard var current = currentJourney else { return }
        current["checklist"] = .array(current.records("checklist").filter { $0.id != id }.map(\.json))
        let payload = current.values; run { [weak self] in guard let self else { return }; try await self.store.perform("journey.save", payload) }
    }
    private func sharePlan(_ journey: Record) {
        var parts = [journey.string("title"), journey.string("start_date") + " — " + journey.string("end_date")]
        for day in journey.records("days") {
            parts.append(day.string("date"))
            for stop in day.records("stops") {
                if let place = store.rows("places").first(where: { $0.id == stop.string("place_id") }) { parts.append("• " + place.string("name")) }
            }
        }
        share([parts.joined(separator: "\n")])
    }
}

final class TextNoteController: TravelScreen {
    private let heading: String
    private let value: String
    private let limit: Int
    private let saveWork: (String) async throws -> Void
    private let editor = UITextView()
    init(store: TravelStore, heading: String, value: String, limit: Int = 5000, save: @escaping (String) async throws -> Void) {
        self.heading = heading; self.value = value; self.limit = limit; saveWork = save
        super.init(store: store); automaticRefresh = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        editor.text = value; editor.font = FontBook.font(18); editor.backgroundColor = Palette.paper; editor.layer.cornerRadius = 18
        editor.textContainerInset = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        editor.heightAnchor.constraint(equalToConstant: 260).isActive = true; editor.accessibilityLabel = heading
        super.viewDidLoad()
    }
    override func render() {
        super.render(); title = heading
        content.addArrangedSubview(text(heading, 32, display: true)); content.addArrangedSubview(editor)
        content.addArrangedSubview(text("Up to \(limit) characters", 14, color: Palette.muted))
        content.addArrangedSubview(action("Save", icon: "icon-check") { [weak self] in
            guard let self else { return }
            let value = self.editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count <= self.limit, self.limit != 120 || !value.isEmpty else { self.notice("Please enter a valid note within the character limit."); return }
            self.run { try await self.saveWork(value); self.navigationController?.popViewController(animated: true) }
        })
    }
}

final class JourneyPickerController: TravelScreen {
    private let placeID: String
    init(store: TravelStore, placeID: String) { self.placeID = placeID; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func render() {
        super.render(); title = "Add to journey"
        content.addArrangedSubview(text("Which chapter?", 32, display: true))
        content.addArrangedSubview(action("Create a new journey", icon: "icon-add") { [weak self] in guard let self else { return }; self.push(JourneyEditorController(store: self.store, initialPlaceID: self.placeID)) })
        for journey in store.rows("journeys") {
            for (index, day) in journey.records("days").enumerated() {
                content.addArrangedSubview(action(journey.string("title") + " · " + day.string("title"), icon: "icon-journeys", filled: false) { [weak self] in
                    guard let self else { return }; self.run {
                        try await addJourneyStop(store: self.store, journeyID: journey.id, dayIndex: index, placeID: self.placeID)
                        self.navigationController?.popViewController(animated: true)
                    }
                })
            }
        }
    }
}

final class JourneyPlacePickerController: TravelScreen {
    private let journeyID: String
    private let dayIndex: Int
    init(store: TravelStore, journeyID: String, dayIndex: Int) { self.journeyID = journeyID; self.dayIndex = dayIndex; super.init(store: store) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func render() {
        super.render(); title = "Add a stop"
        let saved = Set(store.rows("saved_places").map { $0.string("place_id") })
        let places = store.rows("places").sorted { saved.contains($0.id) && !saved.contains($1.id) }
        content.addArrangedSubview(text("A place along the way", 31, display: true))
        for place in places {
            content.addArrangedSubview(action(place.string("name") + (saved.contains(place.id) ? " · Saved" : ""), icon: "icon-location", filled: false) { [weak self] in
                guard let self else { return }; self.run {
                    try await addJourneyStop(store: self.store, journeyID: self.journeyID, dayIndex: self.dayIndex, placeID: place.id)
                    self.navigationController?.popViewController(animated: true)
                }
            })
        }
    }
}

@MainActor private func addJourneyStop(store: TravelStore, journeyID: String, dayIndex: Int, placeID: String) async throws {
    guard var journey = store.rows("journeys").first(where: { $0.id == journeyID }) else { throw JourneyError.missing }
    var days = journey.records("days"); guard days.indices.contains(dayIndex) else { throw JourneyError.missing }
    var stops = days[dayIndex].records("stops")
    guard !stops.contains(where: { $0.string("place_id") == placeID }) else { throw JourneyError.duplicate }
    stops.append(Record(["id": .string(UUID().uuidString.lowercased()), "place_id": .string(placeID), "note": .string("")]))
    days[dayIndex]["stops"] = .array(stops.map(\.json)); journey["days"] = .array(days.map(\.json))
    try await store.perform("journey.save", journey.values)
}

private enum JourneyError: LocalizedError {
    case missing, duplicate
    var errorDescription: String? { self == .missing ? "This journey or day is no longer available." : "This place is already on this day's itinerary." }
}
