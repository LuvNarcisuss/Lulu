import UIKit

@MainActor
final class WalletController: TravelScreen {
    private let catalog = PaymentCatalogAdapter()
    override func viewDidLoad() {
        super.viewDidLoad()
        catalog.onChange = { [weak self] in self?.render() }
        catalog.load()
    }
    override func render() {
        super.render(); title = "Wallet"
        let diamond = UIImageView(image: UIImage(named: "icon-diamond"))
        diamond.contentMode = .scaleAspectFit
        diamond.heightAnchor.constraint(equalToConstant: 64).isActive = true
        content.addArrangedSubview(card([diamond, text("\(store.balance)", 42, display: true), text("Diamond balance", 16, color: Palette.muted)], color: Palette.cream))
        content.addArrangedSubview(text("A little extra for your travels", 27, display: true))
        content.addArrangedSubview(text(catalog.message, 15, color: Palette.muted))
        if catalog.offers.isEmpty { content.addArrangedSubview(text("No diamond packages are configured.", color: Palette.muted)) }
        for offset in stride(from: 0, to: catalog.offers.count, by: 2) {
            let row = line([], spacing: 12); row.distribution = .fillEqually; row.alignment = .fill
            for offer in catalog.offers[offset..<min(offset + 2, catalog.offers.count)] {
                let price = catalog.prices[offer.productID]
                let purchase = action(price ?? "Unavailable", filled: false) { }
                purchase.isEnabled = false
                purchase.accessibilityLabel = "\(offer.diamonds) diamonds, \(price ?? "unavailable"), purchases disabled"
                row.addArrangedSubview(card([text("\(offer.diamonds)", 27, display: true), text("diamonds", 14, color: Palette.muted), purchase]))
            }
            if row.arrangedSubviews.count == 1 { row.addArrangedSubview(UIView()) }
            content.addArrangedSubview(row)
        }
        let retry = action(catalog.loading ? "Loading products…" : "Retry product availability", icon: "icon-refresh", filled: false) { [weak self] in self?.catalog.load() }
        retry.isEnabled = !catalog.loading
        content.addArrangedSubview(retry)
        content.addArrangedSubview(text("History", 26, display: true))
        content.addArrangedSubview(action("Refresh wallet history", icon: "icon-refresh", filled: false) { [weak self] in guard let self else { return }; self.run { try await self.store.refresh() } })
        let activity = store.rows("wallet_activity").filter { $0.string("owner_id") == store.userID }.sorted { $0.string("created_at") > $1.string("created_at") }
        if activity.isEmpty { content.addArrangedSubview(text("No wallet activity yet. New accounts start with zero diamonds.", color: Palette.muted)) }
        for item in activity {
            content.addArrangedSubview(card([text(item.string("description", fallback: item.string("kind")), 19, display: true), text("\(item.int("amount")) diamonds", color: Palette.teal), text(item.string("created_at"), 12, color: Palette.muted)]))
        }
        content.addArrangedSubview(text("Only verified transactions can change your balance. No purchase is started from an unavailable package. Consumable diamonds cannot be restored through a device-only restore action.", 13, color: Palette.muted))
    }
}
