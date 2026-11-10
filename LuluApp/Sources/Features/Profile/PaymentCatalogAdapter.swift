import Combine
import Foundation
import StoreKit

struct CoinOffer: Decodable {
    let coins: Int
    let productID: String
}

@MainActor
final class PaymentCatalogAdapter {
    private struct Configuration: Decodable { let tiers: [CoinOffer] }
    private weak var store: TravelStore?
    private var products: [String: Product] = [:]
    private var updates: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var delivering: Set<UInt64> = []
    private var serverReady = false
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

    func load() {
        guard !loading, !purchasing, let store else { return }
        loading = true
        message = "Loading Apple coin packages…"
        revision += 1
        Task { [weak self, weak store] in
            guard let self, let store else { return }
            let account = store.userID
            async let readiness = store.coinPurchasesAvailable()
            do {
                let available = try await Product.products(for: self.offers.map(\.productID))
                let ready = await readiness
                guard store.userID == account else { self.reset(); return }
                self.products = Dictionary(uniqueKeysWithValues: available.filter { $0.type == .consumable }.map { ($0.id, $0) })
                self.serverReady = ready
                if self.products.isEmpty {
                    self.message = "Apple has no available coin packages for this storefront."
                } else if !ready {
                    self.message = "Coin purchases are temporarily unavailable."
                } else {
                    self.message = "Choose a coin package."
                }
            } catch {
                guard store.userID == account else { self.reset(); return }
                self.products.removeAll()
                self.serverReady = false
                self.message = "Apple coin packages could not be loaded. Please retry."
            }
            self.loading = false
            self.revision += 1
            self.recoverUnfinished()
        }
    }

    func price(for offer: CoinOffer) -> String? { products[offer.productID]?.displayPrice }

    func canBuy(_ offer: CoinOffer) -> Bool {
        !loading && !purchasing && serverReady && AppStore.canMakePayments && products[offer.productID] != nil
    }

    func buy(_ offer: CoinOffer) {
        guard canBuy(offer), let product = products[offer.productID],
              let store, let account = UUID(uuidString: store.userID) else { return }
        purchasing = true
        message = "Opening Apple purchase…"
        revision += 1
        Task { [weak self, weak store] in
            guard let self, let store else { return }
            defer { self.purchasing = false; self.revision += 1 }
            guard await store.coinPurchasesAvailable(), store.userID.lowercased() == account.uuidString.lowercased() else {
                self.serverReady = false
                self.message = "Coin purchases are temporarily unavailable."
                return
            }
            do {
                switch try await product.purchase(options: [.appAccountToken(account)]) {
                case .success(let result):
                    if try await self.deliver(result) {
                        self.message = "Coins added to your wallet."
                    }
                case .pending:
                    self.message = "The purchase is pending Apple approval."
                case .userCancelled:
                    self.message = "Purchase cancelled."
                @unknown default:
                    self.message = "Apple returned an unknown purchase status."
                }
            } catch {
                self.message = "The purchase could not be confirmed. Retry to check for unfinished purchases."
            }
        }
    }

    func recoverUnfinished() {
        guard recovery == nil else { return }
        recovery = Task { [weak self] in
            for await result in Transaction.unfinished {
                guard let self else { return }
                await self.deliverUpdate(result)
            }
            self?.recovery = nil
        }
    }

    func reset() {
        products.removeAll()
        loading = false
        serverReady = false
        message = "Loading coin packages…"
        revision += 1
    }

    private func deliverUpdate(_ result: VerificationResult<Transaction>) async {
        do {
            if try await deliver(result) {
                message = "Coins added to your wallet."
                revision += 1
            }
        } catch {
            message = "A purchase is awaiting verification. Retry from the wallet."
            revision += 1
        }
    }

    private func deliver(_ result: VerificationResult<Transaction>) async throws -> Bool {
        guard case .verified(let transaction) = result,
              transaction.productType == .consumable,
              offers.contains(where: { $0.productID == transaction.productID }),
              let store, store.isAuthenticated,
              let account = UUID(uuidString: store.userID), transaction.appAccountToken == account,
              delivering.insert(transaction.id).inserted else { return false }
        defer { delivering.remove(transaction.id) }
        try await store.deliverCoinPurchase(result.jwsRepresentation, account: account)
        await transaction.finish()
        try? await store.refreshCoinState()
        return true
    }

    deinit {
        updates?.cancel()
        recovery?.cancel()
    }
}
