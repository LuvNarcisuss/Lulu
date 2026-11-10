import Combine
import UIKit

@MainActor
final class WalletController: TravelScreen {
    private var catalog: PaymentCatalogAdapter { store.payments }
    private var catalogObservation: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        catalogObservation = catalog.$revision.dropFirst().sink { [weak self] _ in self?.render() }
        catalog.load()
        Task { try? await store.refreshCoinState() }
    }

    override func render() {
        super.render()
        title = "Wallet"
        let wallet = UIImageView(image: UIImage(named: "icon-wallet"))
        wallet.contentMode = .scaleAspectFit
        wallet.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let balance = store.hasCoinState ? String(store.balance) : "—"
        content.addArrangedSubview(card([wallet, text(balance, 40, display: true), text("Coin balance", 16, color: Palette.muted)], color: Palette.cream))
        content.addArrangedSubview(text("Buy coins", 27, display: true))
        content.addArrangedSubview(text(catalog.message, 15, color: Palette.muted))

        for offset in stride(from: 0, to: catalog.offers.count, by: 3) {
            let row = line([], spacing: 8)
            row.distribution = .fillEqually
            row.alignment = .fill
            for offer in catalog.offers[offset..<min(offset + 3, catalog.offers.count)] {
                let price = catalog.price(for: offer)
                let purchase = action(price ?? "Unavailable", filled: catalog.canBuy(offer)) { [weak self] in self?.catalog.buy(offer) }
                purchase.configuration?.contentInsets = .init(top: 8, leading: 2, bottom: 8, trailing: 2)
                purchase.isEnabled = catalog.canBuy(offer)
                purchase.accessibilityLabel = "\(offer.coins) coins, \(price ?? "unavailable")"
                let amount = text(offer.coins.formatted(), 19, display: true)
                amount.textAlignment = .center
                let caption = text("coins", 14, color: Palette.muted)
                caption.textAlignment = .center
                let package = column([amount, caption, purchase], spacing: 5)
                package.backgroundColor = Palette.paper
                package.layer.cornerRadius = 15
                package.isLayoutMarginsRelativeArrangement = true
                package.directionalLayoutMargins = .init(top: 9, leading: 4, bottom: 4, trailing: 4)
                row.addArrangedSubview(package)
            }
            content.addArrangedSubview(row)
        }
        let retry = action(catalog.loading ? "Loading products…" : "Retry Apple products", icon: "icon-refresh", filled: false) { [weak self] in
            self?.catalog.load()
        }
        retry.isEnabled = !catalog.loading && !catalog.purchasing
        content.addArrangedSubview(retry)
        content.addArrangedSubview(text("History", 26, display: true))
        content.addArrangedSubview(action("Refresh wallet", icon: "icon-refresh", filled: false) { [weak self] in
            guard let self else { return }
            self.run { try await self.store.refreshCoinState() }
        })
        if store.hasCoinState && store.coinActivity.isEmpty {
            content.addArrangedSubview(text("No wallet activity yet.", color: Palette.muted))
        }
        for item in store.coinActivity {
            let amount = item.int("amount")
            content.addArrangedSubview(card([
                text(item.string("description"), 19, display: true),
                text("\(amount > 0 ? "+" : "")\(amount) coins", color: Palette.teal),
                text(item.string("created_at"), 12, color: Palette.muted)
            ]))
        }
    }
}
