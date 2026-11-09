import Foundation
import StoreKit

struct DiamondOffer: Decodable {
    let diamonds: Int
    let productID: String
}

/// Catalog discovery only. Charging remains disabled until authoritative delivery is implemented.
@MainActor
final class PaymentCatalogAdapter: NSObject, SKProductsRequestDelegate {
    private struct Configuration: Decodable { let tiers: [DiamondOffer] }
    private(set) var offers: [DiamondOffer] = []
    private(set) var prices: [String: String] = [:]
    private(set) var message = "Products are not configured."
    private(set) var loading = false
    private var request: SKProductsRequest?
    private var timeout: Task<Void, Never>?
    var onChange: (() -> Void)?

    override init() {
        super.init()
        if let url = Bundle.main.url(forResource: "PaymentCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let catalog = try? JSONDecoder().decode(Configuration.self, from: data) {
            offers = catalog.tiers.filter { $0.diamonds > 0 }
        }
    }
    func load() {
        guard !loading else { return }
        prices = [:]
        let ids = Set(offers.map(\.productID).filter { !$0.isEmpty })
        guard !ids.isEmpty else {
            message = "Diamond purchases are unavailable. Owned product identifiers and verified server delivery have not been configured."
            onChange?(); return
        }
        guard SKPaymentQueue.canMakePayments() else {
            message = "Purchases are restricted on this device."
            onChange?(); return
        }
        loading = true; message = "Loading Apple product availability…"
        let request = SKProductsRequest(productIdentifiers: ids)
        self.request = request
        request.delegate = self
        request.start(); onChange?()
        timeout = Task { [weak self, weak request] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, let request, self.request === request else { return }
            request.cancel(); request.delegate = nil
            self.request = nil; self.loading = false
            self.message = "Apple product lookup timed out. Please retry."
            self.onChange?()
        }
    }
    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor [weak self] in
            guard let self, self.request === request else { return }
            self.timeout?.cancel(); self.timeout = nil
            for product in response.products {
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = product.priceLocale
                if let price = formatter.string(from: product.price) { self.prices[product.productIdentifier] = price }
            }
            self.request = nil; request.delegate = nil; self.loading = false
            self.message = response.products.isEmpty ? "No configured products are available from Apple. Please retry after catalog setup." : "Apple prices loaded. Purchases remain disabled until verified server delivery is configured."
            if !response.invalidProductIdentifiers.isEmpty { self.message += " Some product identifiers were not recognized by Apple." }
            self.onChange?()
        }
    }
    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.request === request else { return }
            self.timeout?.cancel(); self.timeout = nil
            self.request = nil; request.delegate = nil; self.loading = false
            self.message = "Apple product lookup failed: \(error.localizedDescription)"
            self.onChange?()
        }
    }
    deinit { timeout?.cancel(); request?.cancel() }
}
