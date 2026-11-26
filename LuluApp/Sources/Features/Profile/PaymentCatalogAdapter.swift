import Combine
import Foundation
import StoreKit

struct CoinOffer {
    let coins: Int
    let productID: String
    let originalProductID: String

    func matches(_ identifier: String) -> Bool {
        identifier == productID || identifier == originalProductID
    }
}

struct CoinCatalog: Decodable {
    private struct Tier: Decodable {
        let coins: Int
        let productID: String
        let localProductID: String?
    }
    private let tiers: [Tier]

    func offers(localStoreKit: Bool) -> [CoinOffer] {
        tiers.compactMap { tier in
            let identifier = localStoreKit ? (tier.localProductID ?? tier.productID) : tier.productID
            guard tier.coins > 0, !identifier.isEmpty else { return nil }
            return CoinOffer(coins: tier.coins, productID: identifier, originalProductID: tier.productID)
        }
    }
}

enum CoinWalletEnvironment: String {
    case production = "Production"
    case sandbox = "Sandbox"
    case xcode = "Xcode"

    static func installation(receiptURL: URL?, localTesting: Bool, bundleID: String) -> Self {
        if localTesting { return .xcode }
        // This owner-authorized test app can only use the hosted sandbox wallet.
        if bundleID == "im.seex.sao2" { return .sandbox }
        return receiptURL?.lastPathComponent == "sandboxReceipt" ? .sandbox : .production
    }

    var statePath: String {
        self == .sandbox ? "rest/v1/rpc/travel_sandbox_coin_state" : "rest/v1/rpc/travel_coin_state"
    }
}

struct CoinWalletRouting {
    private(set) var environment: CoinWalletEnvironment?

    mutating func useInstallation(_ installation: CoinWalletEnvironment) -> CoinWalletEnvironment {
        if let environment { return environment }
        environment = installation
        return installation
    }

    mutating func acknowledge(_ response: Record) -> CoinWalletEnvironment? {
        guard response.bool("committed"),
              let confirmed = CoinWalletEnvironment(rawValue: response.string("environment")),
              confirmed != .xcode else { return nil }
        environment = confirmed
        return confirmed
    }
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
final class PaymentCatalogAdapter: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    private weak var store: TravelStore?
    private var products: [String: SKProduct] = [:]
    private var invalidProductIDs: Set<String> = []
    private var productRequest: SKProductsRequest?
    private var paymentQueue: SKPaymentQueue?
    private var activePayment: SKPayment?
    private var activeTransaction: SKPaymentTransaction?
    private var recovery: Task<Void, Never>?
    private var recoveryRequested = false
    private var sessionID = UUID()
    private var serverReady = false
    #if DEBUG && targetEnvironment(simulator)
    private var localSessionReady = false
    #endif
    private var walletRouting = CoinWalletRouting()
    private let receiptReader = StoreReceiptReader()
    var appleEnvironment: String? { walletRouting.environment?.rawValue }
    private var deliveryDiagnostic = "not_checked"
    private var checkoutMessage = "Purchases are temporarily unavailable. Tap a package to retry."
    private var loadTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()
    private var loadedAccount = ""
    private var catalogPhase = "idle"
    private var lastErrorCode = "none"
    private(set) var offers: [CoinOffer] = []
    enum Feedback {
        case status(String)
        case problem(String)
    }
    private(set) var feedback: Feedback = .status("Loading coin packages…")
    private(set) var loading = false
    private(set) var purchasing = false
    @Published private(set) var revision = 0

    init(store: TravelStore) {
        self.store = store
        super.init()
        if let url = Bundle.main.url(forResource: "PaymentCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let catalog = try? JSONDecoder().decode(CoinCatalog.self, from: data) {
            offers = catalog.offers(localStoreKit: isLocalStoreKit)
        }
    }

    func startObservingPayments() {
        guard paymentQueue == nil else { return }
        let queue = SKPaymentQueue.default()
        paymentQueue = queue
        queue.add(self)
    }

    var isLocalStoreKit: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return LocalStoreKitWallet.isEnabled
        #else
        return false
        #endif
    }
    #if DEBUG
    private lazy var localWallet = LocalStoreKitWallet(offers: offers)
    #endif

    var isSandbox: Bool { walletRouting.environment == .sandbox }

    func resolveEnvironment() -> CoinWalletEnvironment {
        let installation = CoinWalletEnvironment.installation(
            receiptURL: Bundle.main.appStoreReceiptURL, localTesting: isLocalStoreKit,
            bundleID: Bundle.main.bundleIdentifier ?? "")
        return walletRouting.useInstallation(installation)
    }

    func acknowledgeCoinDelivery(_ response: Record) -> CoinWalletEnvironment? {
        walletRouting.acknowledge(response)
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
        _ = resolveEnvironment()
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
            let environment = resolveEnvironment()
            #if DEBUG && targetEnvironment(simulator)
            if environment == .xcode {
                guard let account = UUID(uuidString: store.userID) else { return false }
                if !localSessionReady {
                    guard let result = try? await AppTransaction.shared, case .verified(let app) = result,
                          app.environment == .xcode, app.bundleID == Bundle.main.bundleIdentifier else {
                        deliveryDiagnostic = "local_session_missing"
                        checkoutMessage = "Run Lulu from Xcode with LuluCoins.storekit selected to start local purchases."
                        return false
                    }
                    localSessionReady = true
                }
                _ = try localWallet.state(account: account)
                deliveryDiagnostic = "local_ready"
                return true
            }
            #endif
            let status = try await store.coinPurchaseStatus(environment: environment.rawValue)
            deliveryDiagnostic = status.string("code", fallback: "invalid_response")
            checkoutMessage = status.string("message", fallback: "Purchases are temporarily unavailable. Tap a package to retry.")
            return status.bool("available") && status.string("environment") == environment.rawValue
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
        loadedAccount = store.userID
        loading = true
        serverReady = false
        products.removeAll()
        invalidProductIDs.removeAll()
        catalogPhase = "loading"
        lastErrorCode = "none"
        feedback = .status("Loading Apple coin packages…")
        revision += 1

        let request = SKProductsRequest(productIdentifiers: Set(offers.map(\.productID)))
        productRequest = request
        request.delegate = self
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard let self, self.generation == requestID, self.loading else { return }
            self.generation = UUID()
            self.stopCatalogLoading()
            self.catalogPhase = "timedOut"
            self.feedback = .problem("Loading took too long. Check your connection and retry.")
            self.revision += 1
        }
        request.start()
    }

    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor [weak self] in
            guard let self, self.productRequest === request,
                  let store = self.store, store.isAuthenticated, store.userID == self.loadedAccount else { return }
            let requestID = self.generation
            request.delegate = nil
            self.productRequest = nil
            let requested = Set(self.offers.map(\.productID))
            self.invalidProductIDs = requested.intersection(response.invalidProductIdentifiers)
            let available = response.products.reduce(into: [String: SKProduct]()) { result, product in
                if requested.contains(product.productIdentifier) { result[product.productIdentifier] = product }
            }
            self.loadTask = Task { [weak self, weak store] in
                guard let self, let store else { return }
                let ready = await self.checkoutReady(store)
                guard self.generation == requestID, store.isAuthenticated, store.userID == self.loadedAccount else { return }
                self.products = available
                self.serverReady = ready
                self.catalogPhase = available.isEmpty ? "unavailable" : (available.count == requested.count ? "ready" : "partial")
                if !SKPaymentQueue.canMakePayments() {
                    self.feedback = .problem("In-app purchases are restricted on this device.")
                } else if available.isEmpty {
                    self.feedback = .problem("Apple returned no coin packages. Please retry later.")
                } else if !ready {
                    self.feedback = .problem(self.checkoutMessage)
                } else if available.count < requested.count {
                    self.feedback = .problem("Some packages are unavailable. You can purchase any available package.")
                } else {
                    self.feedback = .status("Choose a coin package.")
                }
                self.loadTask = nil
                self.stopCatalogLoading()
                self.revision += 1
                if ready { self.recoverUnfinished() }
            }
        }
    }

    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.productRequest === request else { return }
            self.stopCatalogLoading()
            self.catalogPhase = "failed"
            let failure = error as NSError
            self.lastErrorCode = "\(failure.domain):\(failure.code)"
            self.feedback = .problem("Apple coin packages could not be loaded. Please retry.")
            self.revision += 1
        }
    }

    private func stopCatalogLoading() {
        productRequest?.delegate = nil
        productRequest?.cancel()
        productRequest = nil
        loadTask?.cancel()
        loadTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        loading = false
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
        lines.append("Delivery method: StoreKit 1 app receipt")
        lines.append("Catalog: " + catalogPhase)
        lines.append("Local StoreKit wallet: \(isLocalStoreKit)")
        lines.append("Payments allowed: \(SKPaymentQueue.canMakePayments())")
        lines.append("Delivery ready: \(serverReady)")
        lines.append("Apple environment: " + (appleEnvironment ?? "unknown"))
        lines.append("Delivery diagnostic: " + deliveryDiagnostic)
        lines.append("Requested: " + requested.sorted().joined(separator: ", "))
        lines.append("Returned: " + returned.sorted().joined(separator: ", "))
        lines.append("Missing: " + requested.subtracting(returned).sorted().joined(separator: ", "))
        lines.append("Invalid IDs from Apple: " + invalidProductIDs.sorted().joined(separator: ", "))
        lines.append("Error: " + lastErrorCode)
        lines.append("Catalog availability and verified delivery are checked separately.")
        return lines.joined(separator: "\n")
    }

    func price(for offer: CoinOffer) -> String? {
        guard let product = products[offer.productID] else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price)
    }

    func canBuy(_ offer: CoinOffer) -> Bool {
        !loading && !purchasing && serverReady && store?.isAuthenticated == true
            && store?.userID == loadedAccount && SKPaymentQueue.canMakePayments()
            && products[offer.productID] != nil
    }

    func buy(_ offer: CoinOffer) {
        guard canBuy(offer), let product = products[offer.productID],
              let store, let account = UUID(uuidString: store.userID) else { return }
        startObservingPayments()
        guard let queue = paymentQueue else { return }
        let session = sessionID
        purchasing = true
        feedback = .status("Opening Apple purchase…")
        revision += 1
        Task { [weak self, weak store] in
            guard let self, let store else { return }
            let ready = await self.checkoutReady(store)
            guard self.sessionID == session, store.isAuthenticated,
                  UUID(uuidString: store.userID) == account else { return }
            guard ready, SKPaymentQueue.canMakePayments() else {
                self.serverReady = false
                self.endCheckout(.problem("Coin purchases are temporarily unavailable."))
                return
            }
            let payment = SKMutablePayment(product: product)
            payment.applicationUsername = account.uuidString
            let alreadyQueued = queue.transactions.contains { transaction in
                self.matchesPayment(transaction.payment, payment) &&
                    (transaction.transactionState == .purchasing || transaction.transactionState == .deferred ||
                     transaction.transactionState == .purchased)
            }
            guard !alreadyQueued else {
                self.endCheckout(.problem("A purchase for this package is already pending."))
                self.recoverUnfinished()
                return
            }
            self.activePayment = payment
            queue.add(payment)
        }
    }

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor [weak self] in
            guard let self, self.paymentQueue === queue else { return }
            for transaction in transactions { self.handle(transaction, in: queue) }
        }
    }

    private func handle(_ transaction: SKPaymentTransaction, in queue: SKPaymentQueue) {
        guard offers.contains(where: { $0.matches(transaction.payment.productIdentifier) }) else { return }
        let isActive = activePayment.map { matchesPayment(transaction.payment, $0) } ?? false
        switch transaction.transactionState {
        case .purchasing:
            break
        case .deferred:
            if isActive { endCheckout(.status("The purchase is pending Apple approval.")) }
        case .failed:
            let error = transaction.error as? SKError
            queue.finishTransaction(transaction)
            if isActive {
                endCheckout(error?.code == .paymentCancelled
                    ? .status("Purchase cancelled.")
                    : .problem("Apple could not complete the purchase. Please retry."))
            }
        case .purchased:
            if isActive { activeTransaction = transaction }
            recoverUnfinished()
        case .restored:
            // The catalog contains only consumables, which have no restorable entitlement.
            queue.finishTransaction(transaction)
        @unknown default:
            if isActive { endCheckout(.problem("Apple returned an unknown purchase status. Check pending purchases shortly.")) }
        }
    }

    private func matchesPayment(_ first: SKPayment, _ second: SKPayment) -> Bool {
        first.productIdentifier == second.productIdentifier &&
            first.applicationUsername?.lowercased() == second.applicationUsername?.lowercased()
    }

    private func endCheckout(_ feedback: Feedback) {
        activePayment = nil
        activeTransaction = nil
        purchasing = false
        self.feedback = feedback
        revision += 1
    }

    func recoverUnfinished() {
        guard store?.isAuthenticated == true else { return }
        startObservingPayments()
        recoveryRequested = true
        guard recovery == nil else { return }
        recovery = Task { [weak self] in
            guard let self else { return }
            defer { self.recovery = nil }
            var finished = Set<String>()
            repeat {
                self.recoveryRequested = false
                let completed = await self.deliverUnfinished(session: self.sessionID, excluding: finished)
                finished.formUnion(completed)
            } while self.recoveryRequested && !Task.isCancelled
        }
    }

    private func deliverUnfinished(session: UUID, excluding finished: Set<String>) async -> Set<String> {
        guard let store, store.isAuthenticated, let account = UUID(uuidString: store.userID),
              let queue = paymentQueue else { return [] }
        var delivered = Set<String>()
        var awaitingConfirmation = false
        var creditedPayment: SKPayment?
        let checkoutAtStart = activeTransaction
        for transaction in queue.transactions {
            guard !Task.isCancelled, sessionID == session else { return delivered }
            let payment = transaction.payment
            guard transaction.transactionState == .purchased, payment.quantity == 1,
                  let transactionID = transaction.transactionIdentifier, !transactionID.isEmpty,
                  !finished.contains(transactionID), !delivered.contains(transactionID),
                  offers.contains(where: { $0.matches(payment.productIdentifier) }) else { continue }
            // Do not deliver a queued purchase associated with another local account.
            // The server also checks Apple's account token when the receipt includes it.
            if let username = payment.applicationUsername, !username.isEmpty,
               UUID(uuidString: username) != account { continue }
            #if DEBUG && targetEnvironment(simulator)
            if isLocalStoreKit, !localSessionReady {
                guard await checkoutReady(store), sessionID == session else { return delivered }
            }
            #endif
            let checkoutPayment: SKPayment? = activePayment.flatMap { payment in
                guard matchesPayment(transaction.payment, payment) else { return nil }
                return payment
            }
            do {
                try await deliver(transaction, transactionID: transactionID, account: account, in: store)
                guard sessionID == session else { return delivered }
                queue.finishTransaction(transaction)
                delivered.insert(transactionID)
                if let checkoutPayment { creditedPayment = checkoutPayment }
            } catch {
                guard sessionID == session else { return delivered }
                awaitingConfirmation = true
                if let checkoutPayment, activePayment === checkoutPayment {
                    endCheckout(.problem("Your purchase is awaiting confirmation. Check pending purchases shortly."))
                }
            }
        }
        guard !Task.isCancelled, sessionID == session else { return delivered }
        if let creditedPayment, activePayment === creditedPayment {
            endCheckout(.status("Coins added to your wallet."))
        } else if let checkoutAtStart, activeTransaction === checkoutAtStart, !recoveryRequested {
            endCheckout(.problem("Your purchase is awaiting confirmation. Check pending purchases shortly."))
        } else if !purchasing, !loading {
            if !delivered.isEmpty {
                feedback = .status("Coins added to your wallet.")
                revision += 1
            } else if awaitingConfirmation {
                feedback = .problem("A purchase is awaiting confirmation. Check pending purchases shortly.")
                revision += 1
            }
        }
        return delivered
    }

    func reset() {
        sessionID = UUID()
        generation = UUID()
        walletRouting = CoinWalletRouting()
        stopCatalogLoading()
        recoveryRequested = false
        receiptReader.cancel()
        loadedAccount = ""
        catalogPhase = "idle"
        lastErrorCode = "none"
        products.removeAll()
        invalidProductIDs.removeAll()
        serverReady = false
        endCheckout(.status("Loading coin packages…"))
    }

    private func deliver(_ transaction: SKPaymentTransaction, transactionID: String,
                         account: UUID, in store: TravelStore) async throws {
        #if DEBUG && targetEnvironment(simulator)
        if isLocalStoreKit {
            _ = try localWallet.credit(transaction, account: account)
            return
        }
        #endif
        let receipt = try await receiptReader.encodedReceipt()
        try await store.deliverCoinPurchase(transactionID: transactionID,
                                            productID: transaction.payment.productIdentifier,
                                            receipt: receipt, account: account)
    }

    deinit {
        paymentQueue?.remove(self)
        productRequest?.delegate = nil
        productRequest?.cancel()
        loadTask?.cancel()
        timeoutTask?.cancel()
        recovery?.cancel()
    }
}

/// Read receipts only after a purchased callback; first sandbox installs may have none.
@MainActor
private final class StoreReceiptReader: NSObject, SKRequestDelegate {
    private var request: SKReceiptRefreshRequest?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?

    func encodedReceipt() async throws -> String {
        if let receipt = readReceipt() { return receipt }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard self.continuation == nil else {
                continuation.resume(throwing: ReceiptReadFailure.message("Apple receipt refresh is already in progress."))
                return
            }
            self.continuation = continuation
            let request = SKReceiptRefreshRequest()
            self.request = request
            request.delegate = self
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                self?.complete(.failure(ReceiptReadFailure.message("Apple receipt refresh timed out. Check pending purchases shortly.")))
            }
            request.start()
        }
        guard let receipt = readReceipt() else {
            throw ReceiptReadFailure.message("Apple has not provided the purchase receipt. Check pending purchases shortly.")
        }
        return receipt
    }

    private func readReceipt() -> String? {
        guard let url = Bundle.main.appStoreReceiptURL,
              let data = try? Data(contentsOf: url), !data.isEmpty, data.count <= 1_050_000 else { return nil }
        return data.base64EncodedString()
    }

    nonisolated func requestDidFinish(_ request: SKRequest) {
        Task { @MainActor [weak self] in
            guard let self, self.request === request else { return }
            self.complete(.success(()))
        }
    }

    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.request === request else { return }
            self.complete(.failure(error))
        }
    }

    func cancel() { complete(.failure(CancellationError())) }

    private func complete(_ result: Result<Void, Error>) {
        request?.delegate = nil
        request?.cancel()
        request = nil
        timeout?.cancel()
        timeout = nil
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}


private enum ReceiptReadFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}
