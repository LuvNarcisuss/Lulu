#if DEBUG
import Foundation
import StoreKit

/// Xcode-only coins are never submitted to, or spent against, the production wallet.
@MainActor
final class LocalStoreKitWallet {
    struct Entry: Codable {
        let transactionID: String
        let productID: String
        let coins: Int
        let date: Date
    }
    struct GuidePurchase: Codable {
        let guide: Record
        let coins: Int
        let date: Date
    }
    struct State: Codable {
        let account: UUID
        var entries: [String: Entry] = [:]
        // Optional for compatibility with existing credit-only ledgers.
        var guidePurchases: [String: GuidePurchase]?
        var unlocks: [String: GuidePurchase] { guidePurchases ?? [:] }
        var creditedCoins: Int { entries.values.reduce(0) { $0 + $1.coins } }
        var balance: Int { creditedCoins - unlocks.values.reduce(0) { $0 + $1.coins } }
    }
    enum Failure: Error { case invalidTransaction, inconsistentLedger, unknownProduct, invalidGuide }
    // SpringBoard relaunches do not carry Xcode's Run environment.
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["LULU_LOCAL_STOREKIT"] != "0" }
    private let directory: URL
    private let offers: [String: Int]

    init(directory: URL? = nil, offers: [CoinOffer]) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LuluLocalStoreKit", isDirectory: true)
        self.offers = offers.reduce(into: [:]) { amounts, offer in
            amounts[offer.productID] = offer.coins
            amounts[offer.originalProductID] = offer.coins
        }
    }

    func state(account: UUID) throws -> State {
        let url = file(account)
        guard FileManager.default.fileExists(atPath: url.path) else { return State(account: account) }
        let value = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        guard value.account == account,
              value.entries.allSatisfy({ $0.key == $0.value.transactionID && $0.value.coins > 0 }),
              value.unlocks.allSatisfy({ $0.key == $0.value.guide.id && $0.value.coins > 0 }) else {
            throw Failure.inconsistentLedger
        }
        let credits = try total(value.entries.values.map(\.coins))
        let debits = try total(value.unlocks.values.map(\.coins))
        guard debits <= credits else { throw Failure.inconsistentLedger }
        return value
    }

    @discardableResult
    func credit(_ transaction: SKPaymentTransaction, account: UUID) throws -> State {
        let payment = transaction.payment
        guard transaction.transactionState == .purchased, payment.quantity == 1,
              let id = transaction.transactionIdentifier, !id.isEmpty,
              let username = payment.applicationUsername, UUID(uuidString: username) == account else {
            throw Failure.invalidTransaction
        }
        let productID = payment.productIdentifier
        guard let coins = offers[productID], coins > 0 else { throw Failure.unknownProduct }
        var next = try state(account: account)
        if let previous = next.entries[id] {
            guard previous.productID == productID, previous.coins == coins else { throw Failure.inconsistentLedger }
        } else {
            guard next.creditedCoins <= Int.max - coins else { throw Failure.inconsistentLedger }
            next.entries[id] = Entry(transactionID: id, productID: productID, coins: coins,
                                     date: transaction.transactionDate ?? Date())
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: file(account), options: .atomic)
        }
        return next
    }

    @discardableResult
    func unlock(_ guide: Record, price: Int, account: UUID) throws -> State {
        guard price > 0, LocalGuideFixtures.guides.contains(guide) else { throw Failure.invalidGuide }
        var next = try state(account: account)
        if next.unlocks[guide.id] != nil { return next }
        guard next.balance >= price else {
            throw GuidePurchaseFailure.insufficientCoins(balance: next.balance, price: price)
        }
        var purchases = next.unlocks
        purchases[guide.id] = GuidePurchase(guide: guide, coins: price, date: Date())
        next.guidePurchases = purchases
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Balance debit and content entitlement commit together before UI publication.
        try JSONEncoder().encode(next).write(to: file(account), options: .atomic)
        return next
    }

    private func total(_ amounts: [Int]) throws -> Int {
        var result = 0
        for amount in amounts {
            let sum = result.addingReportingOverflow(amount)
            guard !sum.overflow else { throw Failure.inconsistentLedger }
            result = sum.partialValue
        }
        return result
    }

    private func file(_ account: UUID) -> URL { directory.appendingPathComponent(account.uuidString.lowercased() + ".json") }
}
/// Project-owned editorial catalog copies for isolated Xcode purchase acceptance only.
/// Never used in Release or to fetch paid member content from the production backend.
@MainActor
enum LocalGuideFixtures {
    static let guides: [Record] = {
        let data = Data(contents.utf8)
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }()
    private static let contents = #"""
[
  {
    "id": "a0af4e11-2fee-5be6-8418-aea0df526e5c",
    "place_id": "3581e286-25db-5eff-848e-10b50af25ac1",
    "title": "Paris by the Seine: Field Notes",
    "intro": "Riverside walks, grand avenues and small neighborhood streets make a Paris day worth leaving open-ended.",
    "sections": [
      {
        "title": "A day with room to wander",
        "body": "Start with one landmark, then follow the river rather than racing between distant attractions. Pair a monument with a small neighborhood walk for a more varied day."
      },
      {
        "title": "Plan the practical details",
        "body": "The official tourism office links district walks, transport options and accessibility information. Confirm arrangements for each attraction directly before you go; booking and access can change."
      }
    ],
    "source_name": "Paris je t'aime",
    "source_url": "https://parisjetaime.com/eng/",
    "reading_minutes": 2
  },
  {
    "id": "777ba655-213e-5b4e-b855-92a6ccb93408",
    "place_id": "a42c1b6c-7fcc-51b7-837d-0ee7e3375fbe",
    "title": "Colosseum and Ancient Rome: Field Notes",
    "intro": "Roman stonework and the surrounding archaeological landscape tell a story far larger than one amphitheater.",
    "sections": [
      {
        "title": "Build around your entry slot",
        "body": "Begin with the official archaeological park website and choose the visit that matches your interests. Colosseum entry uses a reserved time, so plan other stops around that commitment."
      },
      {
        "title": "Give the wider site time",
        "body": "The Roman Forum and Palatine form a much broader visit than a quick photograph outside the arena. Read what your selected ticket includes and allow time for walking between areas."
      }
    ],
    "source_name": "Parco archeologico del Colosseo",
    "source_url": "https://colosseo.it/en/opening-times-and-tickets/",
    "reading_minutes": 2
  },
  {
    "id": "1de34275-77c1-5a3a-91a0-ee8fb9826717",
    "place_id": "24f0be99-d029-54ae-8584-f9a14f0e17a6",
    "title": "Venice Canal Walks: Field Notes",
    "intro": "Quiet canal corners and weathered bridges reward a slow route through Venice beyond the busiest passages.",
    "sections": [
      {
        "title": "Move at the city's pace",
        "body": "Use smaller streets to discover artisan workshops and everyday corners of Venice. On narrow routes, walk to the right in single file so residents and other visitors can pass."
      },
      {
        "title": "Respect a living place",
        "body": "Choose proper rest areas, look after waterways and historic spaces, and sort waste responsibly. Check the official city site for current access requirements rather than relying on an old itinerary."
      }
    ],
    "source_name": "Venezia Unica",
    "source_url": "https://www.veneziaunica.it/en/sustainable-venice/enjoy-respect-venezia",
    "reading_minutes": 2
  },
  {
    "id": "b0cb3252-5cc5-5078-a5e5-fb7b6a831abe",
    "place_id": "71cbb70e-1413-5fb9-85bc-9c8857fb36ce",
    "title": "Lisbon Hills and Trams: Field Notes",
    "intro": "Trams, tiled streets and hilltop viewpoints give Lisbon an inviting rhythm for a flexible city day.",
    "sections": [
      {
        "title": "Choose a small area",
        "body": "Build a walk around one Lisbon neighborhood, adding a viewpoint or cultural stop along the way. The official tourism site organizes experiences by area and interest."
      },
      {
        "title": "Plan the connections",
        "body": "Consult the official getting-around information before combining trams, walking and farther-away sights. Keep time for slopes and pauses; a short map distance can still make a full afternoon."
      }
    ],
    "source_name": "Turismo de Lisboa",
    "source_url": "https://www.visitlisboa.com/en",
    "reading_minutes": 2
  },
  {
    "id": "8d69926f-a1cc-5419-8021-f71955ca36d2",
    "place_id": "4ef64bb4-498a-55ab-8a24-e244e49252ec",
    "title": "Swiss Alps: Field Notes",
    "intro": "Mountain rail journeys, snowy ridges and walking routes offer different ways into Switzerland's Alpine landscapes.",
    "sections": [
      {
        "title": "Pick the right kind of day",
        "body": "Choose between a scenic rail journey, a valley walk and a demanding mountain route before adding stops. Distances on a map do not describe the effort of an Alpine trail."
      },
      {
        "title": "Leave a flexible margin",
        "body": "Use the official hiking information to compare routes and preparation. Mountain weather and service availability affect plans, so keep another activity available if conditions change."
      }
    ],
    "source_name": "Switzerland Tourism",
    "source_url": "https://www.myswitzerland.com/en-us/experiences/summer-autumn/hiking/",
    "reading_minutes": 2
  },
  {
    "id": "c87245b5-6c29-5629-a957-93116d29553e",
    "place_id": "7117c66f-51a0-5b19-94dc-ebb4a4841f28",
    "title": "Tower Bridge and the Thames: Field Notes",
    "intro": "Blue suspension spans, riverside paths and a working bridge create an absorbing London riverside stop.",
    "sections": [
      {
        "title": "See it from both banks",
        "body": "A riverside walk gives space to appreciate the towers and suspension spans. If you want to go inside, consult the official visitor page and book the experience that fits your day."
      },
      {
        "title": "Look beyond the photograph",
        "body": "The visitor experience includes high-level walkways and the Victorian Engine Rooms. Check accessibility information and current bridge lift details before arranging a tightly timed visit."
      }
    ],
    "source_name": "Tower Bridge",
    "source_url": "https://www.towerbridge.org.uk/",
    "reading_minutes": 2
  },
  {
    "id": "36d14ba6-f206-5c1e-b578-1e6e733e61c6",
    "place_id": "35ffded9-bbbc-5988-8630-cc9d5df64ee9",
    "title": "Park Guell, Barcelona: Field Notes",
    "intro": "Curving architecture, planted slopes and city views turn Park Guell into a distinctive Barcelona walk.",
    "sections": [
      {
        "title": "Plan before the climb",
        "body": "The park limits visitor capacity, so check availability before setting your day's route. Its opening times change with the season; use current official information for your date."
      },
      {
        "title": "Slow down inside",
        "body": "Leave time to notice details and the relationship between architecture and planting. The official site offers route, services, transport and guided-visit information to help shape a comfortable visit."
      }
    ],
    "source_name": "Park Guell Official Website",
    "source_url": "https://parkguell.barcelona/en/planifica-la-teva-visita",
    "reading_minutes": 2
  },
  {
    "id": "bee1d55a-f90c-5aef-b5b5-b1f4f4865656",
    "place_id": "aa21212b-b0d0-58ce-99be-ee3834bddf6d",
    "title": "Santorini Caldera Villages: Field Notes",
    "intro": "Whitewashed settlements, volcanic cliffs and the Aegean horizon reveal Santorini's layered island landscape.",
    "sections": [
      {
        "title": "Look beyond one viewpoint",
        "body": "Fira and Oia sit within a wider volcanic island landscape. Combine a caldera view with another settlement or one of the island's contrasting beaches rather than building a day around a single image."
      },
      {
        "title": "Taste the landscape",
        "body": "The island's volcanic soil supports distinctive crops, including vines, small tomatoes and yellow split peas. Use the official destination information to explore food and cultural stops at an unhurried pace."
      }
    ],
    "source_name": "Greek National Tourism Organisation",
    "source_url": "https://www.visitgreece.gr/en/islands/cyclades/santorini",
    "reading_minutes": 2
  },
  {
    "id": "a7dd9e42-8919-5441-8528-99581e884b24",
    "place_id": "9c269449-085f-5cb3-ade1-652f28ca8e53",
    "title": "Iceland Waterfalls: Field Notes",
    "intro": "A countrywide starting point for waterfall journeys. The photograph shows Dynjandi; video locations remain as credited by their creators.",
    "sections": [
      {
        "title": "Let conditions set the route",
        "body": "Weather can change quickly, and a beautiful scene does not show whether a road or path is suitable today. Consult current travel conditions before committing to a long drive."
      },
      {
        "title": "Keep the view at a distance",
        "body": "Waterfall rocks can be slippery and some hazards are difficult to see. Respect signs, fences and marked paths. For longer independent outdoor trips, prepare suitable equipment and leave a travel plan."
      }
    ],
    "source_name": "Visit Iceland",
    "source_url": "https://www.visiticeland.com/article/safe-travel-in-iceland/",
    "reading_minutes": 2
  },
  {
    "id": "18231422-934f-5718-b0ff-47099a22d510",
    "place_id": "ea21d48f-af5a-5cf1-9435-5690e8edd4fc",
    "title": "New York City: Field Notes",
    "intro": "Street-level energy and skyline views make New York a city best explored one neighborhood at a time.",
    "sections": [
      {
        "title": "Think in neighborhoods",
        "body": "Pick a neighborhood as the anchor for a morning or afternoon. A small number of nearby stops leaves more time for streets, food and unexpected discoveries."
      },
      {
        "title": "Keep exploring",
        "body": "The city extends across five boroughs. Consult the official tourism site for current ideas and practical planning, then check the individual venue's own information for reservations and access."
      }
    ],
    "source_name": "NYC Tourism + Conventions",
    "source_url": "https://www.nyctourism.com/",
    "reading_minutes": 2
  },
  {
    "id": "6fbff3dc-f149-5c7f-8ba7-633e8f67bc29",
    "place_id": "17a7552b-5573-5f31-a932-99214eca2db1",
    "title": "Yosemite Valley: Field Notes",
    "intro": "Granite walls, waterfalls, forests and the Merced River frame an extraordinary Sierra Nevada valley.",
    "sections": [
      {
        "title": "Prepare before arriving",
        "body": "Use the National Park Service planning pages for current conditions, road access and reservation requirements. Lodging and camping need advance thought, while mobile coverage can be limited."
      },
      {
        "title": "Stay with the landscape",
        "body": "Observe wildlife from a distance and never feed it. Near rivers and waterfalls, stay back from fast water and slippery rocks. Choose a walk that matches your preparation and available daylight."
      }
    ],
    "source_name": "National Park Service",
    "source_url": "https://www.nps.gov/yose/planyourvisit/index.htm",
    "reading_minutes": 2
  },
  {
    "id": "bd63ff90-3dd1-595d-b175-5e8764fbb355",
    "place_id": "4d3613c5-fd86-558f-b635-8c8e7484cc86",
    "title": "Moraine Lake, Banff: Field Notes",
    "intro": "Turquoise water and the Valley of the Ten Peaks make Moraine Lake a memorable Canadian Rockies destination.",
    "sections": [
      {
        "title": "Start with access",
        "body": "Lake Louise and Moraine Lake are popular and need planning. The official Parks Canada page explains available transport and shuttle reservations; confirm the arrangements for your own travel date."
      },
      {
        "title": "Make room in the day",
        "body": "Allow time for connections and potential queues rather than packing a lake visit between tight commitments. Separate park entry from transport planning and use the official information for current requirements."
      }
    ],
    "source_name": "Parks Canada",
    "source_url": "https://parks.canada.ca/pn-np/ab/banff/visit/parkbus/louise",
    "reading_minutes": 2
  }
]
"""#
}
#endif
