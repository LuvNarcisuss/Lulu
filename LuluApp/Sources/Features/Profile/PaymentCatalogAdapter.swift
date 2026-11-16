import Combine
import Foundation
import StoreKit

struct CoinOffer: Decodable {
    let coins: Int
    let productID: String
}

enum GuidePurchaseFailure: LocalizedError {
    case insufficientCoins(balance: Int, price: Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .insufficientCoins(let balance, let price):
            return "Your balance is \(balance) coins. This guide costs \(price) coins."
        case .message(let message): return message
        }
    }
}

@MainActor
final class PaymentCatalogAdapter {
    private struct Configuration: Decodable { let tiers: [CoinOffer] }
    private weak var store: TravelStore?
    private var products: [String: Product] = [:]
    private var updates: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var recoveryID = UUID()
    private var delivering: Set<UInt64> = []
    private var serverReady = false
    private(set) var appleEnvironment: String?
    private var environmentTask: Task<String, Error>?
    private var deliveryDiagnostic = "not_checked"
    private var checkoutMessage = "Purchases are temporarily unavailable. Tap a package to retry."
    private var loadTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()
    private var loadedAccount = ""
    private var catalogPhase = "idle"
    private var lastErrorCode = "none"
    private(set) var offers: [CoinOffer] = []
    private(set) var message = "Loading coin packages…"
    private(set) var loading = false
    private(set) var purchasing = false
    @Published private(set) var revision = 0

    init(store: TravelStore) {
        self.store = store
        if let url = Bundle.main.url(forResource: "PaymentCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let catalog = try? JSONDecoder().decode(Configuration.self, from: data) {
            offers = catalog.tiers.filter { $0.coins > 0 && !$0.productID.isEmpty }
        }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.deliverUpdate(result)
            }
        }
    }

    var isLocalStoreKit: Bool {
        #if DEBUG
        return LocalStoreKitWallet.isEnabled || appleEnvironment == "Xcode"
        #else
        return false
        #endif
    }
    #if DEBUG
    private lazy var localWallet = LocalStoreKitWallet(offers: offers)
    #endif

    var isSandbox: Bool { appleEnvironment == "Sandbox" }

    func resolveEnvironment() async throws -> String {
        if isLocalStoreKit { appleEnvironment = "Xcode"; return "Xcode" }
        if let appleEnvironment { return appleEnvironment }
        if let environmentTask { return try await environmentTask.value }
        let task = Task<String, Error> {
            // Receipt location selects a ledger only; the server separately verifies
            // Apple's signed transaction before any coins are credited.
            if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { return "Sandbox" }
            let result = try await AppTransaction.shared
            guard case .verified(let app) = result else {
                throw GuidePurchaseFailure.message("Apple could not verify this installation. Please retry.")
            }
            switch app.environment {
            case .sandbox: return "Sandbox"
            case .production: return "Production"
            case .xcode:
                #if DEBUG
                return "Xcode"
                #else
                throw GuidePurchaseFailure.message("Install Lulu from TestFlight or the App Store to purchase coins.")
                #endif
            default: throw GuidePurchaseFailure.message("This Apple purchase environment is unavailable.")
            }
        }
        environmentTask = task
        defer { environmentTask = nil }
        let value = try await task.value
        appleEnvironment = value
        return value
    }

    var walletBalance: Int? {
        #if DEBUG
        if isLocalStoreKit {
            guard let id = store?.userID, let account = UUID(uuidString: id) else { return nil }
            return try? localWallet.state(account: account).balance
        }
        #endif
        guard let store, store.hasCoinState else { return nil }
        return store.balance
    }

    var walletActivity: [Record] {
        #if DEBUG
        if isLocalStoreKit {
            guard let id = store?.userID, let account = UUID(uuidString: id),
                  let state = try? localWallet.state(account: account) else { return [] }
            let credits = state.entries.values.map { entry in
                (entry.date, Record(["amount": .number(Double(entry.coins)), "description": .string("Local StoreKit coin purchase"),
                                     "created_at": .string(ISO8601DateFormatter().string(from: entry.date))]))
            }
            let debits = state.unlocks.values.map { entry in
                (entry.date, Record(["amount": .number(Double(-entry.coins)), "description": .string(entry.guide.string("title")),
                                     "created_at": .string(ISO8601DateFormatter().string(from: entry.date))]))
            }
            return (credits + debits).sorted { $0.0 > $1.0 }.map { $0.1 }
        }
        #endif
        return store?.coinActivity ?? []
    }

    func refreshWallet() async throws {
        _ = try await resolveEnvironment()
        #if DEBUG
        if isLocalStoreKit {
            guard let id = store?.userID, let account = UUID(uuidString: id) else { return }
            _ = try localWallet.state(account: account)
            revision += 1
            return
        }
        #endif
        try await store?.refreshCoinState()
    }

    func hasGuideAccess(to offer: Record) -> Bool {
        guard let store, store.isAuthenticated else { return false }
        if offer.int("price_coins") == 0 || offer.bool("unlocked") || offer.string("author_id") == store.userID { return true }
        #if DEBUG
        if isLocalStoreKit, let account = UUID(uuidString: store.userID),
           let state = try? localWallet.state(account: account) {
            return state.unlocks[offer.string("guide_id")] != nil
        }
        #endif
        return false
    }

    func localGuideContent(for offer: Record) -> Record? {
        if isSandbox { return store?.sandboxGuides.first { $0.id == offer.string("guide_id") } }
        #if DEBUG
        if isLocalStoreKit, let store, store.isAuthenticated,
           offer.string("author_id").isEmpty, offer.string("status") == "published",
           let account = UUID(uuidString: store.userID),
           let state = try? localWallet.state(account: account),
           let guide = state.unlocks[offer.string("guide_id")]?.guide,
           guide.string("place_id") == offer.string("place_id") { return guide }
        #endif
        return nil
    }

    func unlockGuide(_ guideID: String, expectedPrice: Int) async throws {
        guard let store, store.isAuthenticated else { throw CancellationError() }
        let accountID = store.userID
        try await store.refreshCoinState()
        guard store.isAuthenticated, store.userID == accountID else { throw CancellationError() }
        guard let offer = store.guideOffers.first(where: { $0.string("guide_id") == guideID }),
              offer.string("status") == "published" else {
            throw GuidePurchaseFailure.message("This guide is unavailable.")
        }
        if hasGuideAccess(to: offer) {
            if localGuideContent(for: offer) == nil { try await store.refresh() }
            return
        }
        let price = offer.int("price_coins")
        guard price > 0, price == expectedPrice else {
            throw GuidePurchaseFailure.message("The guide price changed. Open it again to confirm the new price.")
        }
        guard let balance = walletBalance else {
            throw GuidePurchaseFailure.message("Your coin balance could not be loaded. Please try again.")
        }
        guard balance >= price else { throw GuidePurchaseFailure.insufficientCoins(balance: balance, price: price) }
        #if DEBUG
        if isLocalStoreKit {
            guard let account = UUID(uuidString: accountID), offer.string("author_id").isEmpty,
                  let guide = LocalGuideFixtures.guides.first(where: {
                      $0.id == guideID && $0.string("place_id") == offer.string("place_id")
                  }) else {
                throw GuidePurchaseFailure.message("This guide is not available for local StoreKit testing. No coins were spent.")
            }
            _ = try localWallet.unlock(guide, price: price, account: account)
            revision += 1
            return
        }
        #endif
        do {
            try await store.perform("guide.unlock", ["target_guide": .string(guideID),
                                                    "expected_price": .number(Double(price))])
        } catch {
            // A concurrent purchase on another device can exhaust the server balance.
            if error.localizedDescription == "Not enough coins" {
                try await store.refreshCoinState()
                guard store.isAuthenticated, store.userID == accountID else { throw CancellationError() }
                throw GuidePurchaseFailure.insufficientCoins(balance: store.balance, price: price)
            }
            throw error
        }
        guard store.isAuthenticated, store.userID == accountID else { throw CancellationError() }
        do {
            try await store.refreshCoinState()
            try await store.refresh()
        } catch is CancellationError { throw CancellationError() }
        catch {
            throw GuidePurchaseFailure.message("Your payment was saved. Open this guide again to load it without paying twice.")
        }
    }

    private func checkoutReady(_ store: TravelStore) async -> Bool {
        do {
            let environment = try await resolveEnvironment()
            #if DEBUG
            if environment == "Xcode" {
                guard let account = UUID(uuidString: store.userID) else { return false }
                _ = try localWallet.state(account: account)
                deliveryDiagnostic = "local_ready"
                return true
            }
            #endif
            let status = try await store.coinPurchaseStatus(environment: environment)
            deliveryDiagnostic = status.string("code", fallback: "invalid_response")
            checkoutMessage = status.string("message", fallback: "Purchases are temporarily unavailable. Tap a package to retry.")
            return status.bool("available") && status.string("environment") == environment
        } catch {
            let failure = error as NSError
            deliveryDiagnostic = "\(failure.domain):\(failure.code)"
            checkoutMessage = "The purchase service could not be reached. Check your connection and tap a package to retry."
            return false
        }
    }

    func load() {
        guard !loading, !purchasing, let store, store.isAuthenticated else { return }
        let requestID = UUID()
        generation = requestID
        let account = store.userID
        loadedAccount = account
        loading = true
        serverReady = false
        catalogPhase = "loading"
        lastErrorCode = "none"
        message = "Loading Apple coin packages…"
        revision += 1
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard let self, self.generation == requestID, self.loading else { return }
            self.generation = UUID()
            self.loadTask?.cancel()
            self.loadTask = nil
            self.loading = false
            self.serverReady = false
            self.catalogPhase = "timedOut"
            self.message = "Loading took too long. Check your connection and retry."
            self.revision += 1
        }
        loadTask = Task { [weak self, weak store] in
            guard let self, let store else { return }
            async let readiness = self.checkoutReady(store)
            do {
                let available = try await Product.products(for: self.offers.map(\.productID))
                let ready = await readiness
                guard self.generation == requestID, store.isAuthenticated, store.userID == account else { return }
                let requested = Set(self.offers.map(\.productID))
                self.products = available.reduce(into: [:]) { result, product in
                    if requested.contains(product.id), product.type == .consumable { result[product.id] = product }
                }
                self.serverReady = ready
                self.catalogPhase = self.products.isEmpty ? "unavailable" : (self.products.count == requested.count ? "ready" : "partial")
                if !AppStore.canMakePayments {
                    self.message = "In-app purchases are restricted on this device."
                } else if self.products.isEmpty {
                    self.message = "Apple returned no coin packages. Please retry later."
                } else if !ready {
                    self.message = self.checkoutMessage
                } else if self.products.count < requested.count {
                    self.message = "Some packages are unavailable. You can purchase any available package."
                } else {
                    self.message = "Choose a coin package."
                }
            } catch {
                guard self.generation == requestID, store.userID == account else { return }
                self.products.removeAll()
                self.serverReady = false
                self.catalogPhase = "failed"
                let failure = error as NSError
                self.lastErrorCode = "\(failure.domain):\(failure.code)"
                self.message = "Apple coin packages could not be loaded. Please retry."
            }
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.loadTask = nil
            self.loading = false
            self.revision += 1
            if self.serverReady { self.recoverUnfinished() }
        }
    }

    func buttonTitle(for offer: CoinOffer) -> String {
        if loading { return "Loading…" }
        return price(for: offer) ?? "Unavailable"
    }

    var diagnostics: String {
        let requested = Set(offers.map(\.productID))
        let returned = Set(products.keys)
        var lines: [String] = []
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        lines.append("Bundle: " + (Bundle.main.bundleIdentifier ?? "unknown"))
        lines.append("Version: " + version)
        lines.append("Catalog: " + catalogPhase)
        lines.append("Local StoreKit wallet: \(isLocalStoreKit)")
        lines.append("Payments allowed: \(AppStore.canMakePayments)")
        lines.append("Delivery ready: \(serverReady)")
        lines.append("Apple environment: " + (appleEnvironment ?? "unknown"))
        lines.append("Delivery diagnostic: " + deliveryDiagnostic)
        lines.append("Requested: " + requested.sorted().joined(separator: ", "))
        lines.append("Returned: " + returned.sorted().joined(separator: ", "))
        lines.append("Missing: " + requested.subtracting(returned).sorted().joined(separator: ", "))
        lines.append("Error: " + lastErrorCode)
        lines.append("Catalog availability and verified delivery are checked separately.")
        return lines.joined(separator: "\n")
    }

    func price(for offer: CoinOffer) -> String? { products[offer.productID]?.displayPrice }

    func canBuy(_ offer: CoinOffer) -> Bool {
        !loading && !purchasing && serverReady && store?.isAuthenticated == true && store?.userID == loadedAccount && AppStore.canMakePayments && products[offer.productID] != nil
    }

    func buy(_ offer: CoinOffer) {
        guard canBuy(offer), let product = products[offer.productID],
              let store, let account = UUID(uuidString: store.userID) else { return }
        let purchaseGeneration = generation
        purchasing = true
        message = "Opening Apple purchase…"
        revision += 1
        Task { [weak self, weak store] in
            guard let self, let store else { return }
            defer {
                if self.generation == purchaseGeneration { self.purchasing = false; self.revision += 1 }
            }
            let ready = await self.checkoutReady(store)
            guard self.generation == purchaseGeneration, store.isAuthenticated,
                  store.userID.lowercased() == account.uuidString.lowercased() else { return }
            guard ready, AppStore.canMakePayments else {
                self.serverReady = false
                self.message = "Coin purchases are temporarily unavailable."
                return
            }
            do {
                let outcome = try await product.purchase(options: [.appAccountToken(account)])
                guard self.generation == purchaseGeneration, store.userID == self.loadedAccount else { return }
                switch outcome {
                case .success(let result):
                    let committed = try await self.deliver(result)
                    guard self.generation == purchaseGeneration else { return }
                    self.message = committed ? "Coins added to your wallet." : "Your purchase is awaiting confirmation. Check pending purchases shortly."
                case .pending:
                    self.message = "The purchase is pending Apple approval."
                case .userCancelled:
                    self.message = "Purchase cancelled."
                @unknown default:
                    self.message = "Apple returned an unknown purchase status."
                }
            } catch {
                guard self.generation == purchaseGeneration else { return }
                self.message = "The purchase could not be confirmed. Retry to check for unfinished purchases."
            }
        }
    }

    func recoverUnfinished() {
        guard recovery == nil, store?.isAuthenticated == true else { return }
        let recoveryToken = UUID()
        recoveryID = recoveryToken
        recovery = Task { [weak self] in
            for await result in Transaction.unfinished {
                guard let self, !Task.isCancelled, self.recoveryID == recoveryToken else { return }
                await self.deliverUpdate(result)
            }
            if self?.recoveryID == recoveryToken { self?.recovery = nil }
        }
    }

    func reset() {
        generation = UUID()
        loadTask?.cancel(); loadTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        recoveryID = UUID()
        recovery?.cancel(); recovery = nil
        loadedAccount = ""
        purchasing = false
        catalogPhase = "idle"
        lastErrorCode = "none"
        products.removeAll()
        loading = false
        serverReady = false
        message = "Loading coin packages…"
        revision += 1
    }

    private func deliverUpdate(_ result: VerificationResult<Transaction>) async {
        let session = generation
        do {
            if try await deliver(result), generation == session {
                message = "Coins added to your wallet."
                revision += 1
            }
        } catch {
            guard generation == session else { return }
            message = "A purchase is awaiting verification. Retry from the wallet."
            revision += 1
        }
    }

    private func deliver(_ result: VerificationResult<Transaction>) async throws -> Bool {
        guard case .verified(let transaction) = result else { throw PurchaseFailure.unverified }
        guard transaction.productType == .consumable,
              transaction.purchasedQuantity == 1, transaction.revocationDate == nil,
              offers.contains(where: { $0.productID == transaction.productID }),
              let store, store.isAuthenticated,
              let account = UUID(uuidString: store.userID), transaction.appAccountToken == account,
              delivering.insert(transaction.id).inserted else { return false }
        defer { delivering.remove(transaction.id) }
        #if DEBUG
        if isLocalStoreKit {
            _ = try await localWallet.deliver(result, account: account)
            return true
        }
        #endif
        let transactionEnvironment: String
        switch transaction.environment {
        case .sandbox: transactionEnvironment = "Sandbox"
        case .production: transactionEnvironment = "Production"
        default: throw PurchaseFailure.unverified
        }
        try await store.deliverCoinPurchase(result.jwsRepresentation, account: account, environment: transactionEnvironment)
        await transaction.finish()
        try? await store.refreshCoinState()
        return true
    }

    private enum PurchaseFailure: Error { case unverified }

    deinit {
        loadTask?.cancel()
        timeoutTask?.cancel()
        updates?.cancel()
        recovery?.cancel()
    }
}
