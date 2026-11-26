import Combine
import UIKit

@MainActor
final class WalletController: TravelScreen {
    private var catalog: PaymentCatalogAdapter { store.payments }
    private var catalogObservation: AnyCancellable?
    private var purchaseLoadingView: UIView?
    private let purchaseLoadingIcon = UIImageView(image: UIImage(named: "icon-refresh"))

    override func viewDidLoad() {
        super.viewDidLoad()
        catalogObservation = catalog.$revision.dropFirst().sink { [weak self] _ in self?.render() }
        catalog.load()
        run { try await self.catalog.refreshWallet() }
    }

    override func render() {
        super.render()
        title = "Wallet"
        updatePurchaseLoading()
        let wallet = UIImageView(image: UIImage(named: "icon-coin"))
        wallet.contentMode = .scaleAspectFit
        wallet.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let balance = catalog.walletBalance.map(String.init) ?? "—"
        let balanceLabel = text(balance, 40, display: true)
        balanceLabel.accessibilityIdentifier = "wallet.balance"
        content.addArrangedSubview(card([wallet, balanceLabel, text("Coin balance", 16, color: Palette.muted)], color: Palette.cream))
        if catalog.isLocalStoreKit {
            content.addArrangedSubview(text("Local StoreKit testing · Separate test balance", 13, color: Palette.muted))
        }
        content.addArrangedSubview(text("Buy coins", 27, display: true))
        switch catalog.feedback {
        case .status(let message):
            updateProblem(nil, for: "wallet")
            let statusLabel = text(message, 15, color: Palette.muted)
            statusLabel.accessibilityIdentifier = "wallet.status"
            statusLabel.accessibilityValue = catalog.appleEnvironment ?? "Unknown"
            content.addArrangedSubview(statusLabel)
        case .problem(let message):
            updateProblem(message, for: "wallet")
        }

        for offset in stride(from: 0, to: catalog.offers.count, by: 3) {
            let row = line([], spacing: 8)
            row.distribution = .fillEqually
            row.alignment = .fill
            for offer in catalog.offers[offset..<min(offset + 3, catalog.offers.count)] {
                let price = catalog.price(for: offer)
                let canBuy = catalog.canBuy(offer)
                let amount = text(offer.coins.formatted(), 19, display: true)
                amount.textAlignment = .center
                let priceLabel = text(price ?? catalog.buttonTitle(for: offer), 16,
                                      color: canBuy ? Palette.teal : Palette.muted)
                priceLabel.textAlignment = .center
                let coin = UIImageView(image: UIImage(named: "icon-coin"))
                coin.contentMode = .scaleAspectFit
                coin.heightAnchor.constraint(equalToConstant: 28).isActive = true
                coin.isAccessibilityElement = false
                let details = column([coin, amount, priceLabel], spacing: 5)
                details.isUserInteractionEnabled = false
                details.accessibilityElementsHidden = true
                details.translatesAutoresizingMaskIntoConstraints = false

                let package = UIButton(type: .custom)
                package.backgroundColor = Palette.paper
                package.layer.cornerRadius = 15
                package.isEnabled = !catalog.loading && !catalog.purchasing
                package.isAccessibilityElement = true
                package.accessibilityLabel = "\(offer.coins.formatted()) coins, \(price ?? catalog.buttonTitle(for: offer))"
                package.accessibilityHint = canBuy ? "Opens purchase confirmation." : "Shows availability and retries loading."
                package.accessibilityIdentifier = "wallet.package.\(offer.coins)"
                package.addSubview(details)
                NSLayoutConstraint.activate([
                    details.topAnchor.constraint(equalTo: package.topAnchor, constant: 12),
                    details.leadingAnchor.constraint(equalTo: package.leadingAnchor, constant: 6),
                    details.trailingAnchor.constraint(equalTo: package.trailingAnchor, constant: -6),
                    details.bottomAnchor.constraint(equalTo: package.bottomAnchor, constant: -12),
                    package.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
                ])
                package.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    guard let price = self.catalog.price(for: offer), self.catalog.canBuy(offer) else {
                        self.catalog.load()
                        self.notice("This package is unavailable. Please try again after the catalog reloads.")
                        return
                    }
                    if self.catalog.isLocalStoreKit {
                        self.catalog.buy(offer)
                        return
                    }
                    self.confirm("Buy coins?", message: "Add \(offer.coins.formatted()) coins for \(price)? Apple will ask you to confirm the purchase.") {
                        self.catalog.buy(offer)
                    }
                }, for: .touchUpInside)
                row.addArrangedSubview(package)
            }
            content.addArrangedSubview(row)
        }
        let retry = action(catalog.loading ? "Loading products…" : "Retry Apple products", icon: "icon-refresh", filled: false) { [weak self] in
            self?.catalog.load()
        }
        retry.isEnabled = !catalog.loading && !catalog.purchasing
        content.addArrangedSubview(retry)
        content.addArrangedSubview(action("Check pending purchases", filled: false) { [weak self] in
            self?.catalog.recoverUnfinished()
        })
        #if DEBUG
        let diagnostics = action("Copy store diagnostics", filled: false) { [weak self] in
            guard let self else { return }
            UIPasteboard.general.string = self.catalog.diagnostics
            self.notice("Store diagnostics copied.")
        }
        diagnostics.accessibilityIdentifier = "wallet.diagnostics"
        diagnostics.accessibilityValue = catalog.diagnostics
        content.addArrangedSubview(diagnostics)
        #endif
        content.addArrangedSubview(text("History", 26, display: true))
        content.addArrangedSubview(action("Refresh wallet", icon: "icon-refresh", filled: false) { [weak self] in
            guard let self else { return }
            self.run { try await self.catalog.refreshWallet() }
        })
        if catalog.walletBalance != nil && catalog.walletActivity.isEmpty {
            content.addArrangedSubview(text("No wallet activity yet.", color: Palette.muted))
        }
        for item in catalog.walletActivity {
            let amount = item.int("amount")
            content.addArrangedSubview(card([
                text(item.string("description"), 19, display: true),
                text("\(amount > 0 ? "+" : "")\(amount) coins", color: Palette.teal),
                text(item.string("created_at"), 12, color: Palette.muted)
            ]))
        }
    }

    private func updatePurchaseLoading() {
        guard catalog.purchasing else {
            purchaseLoadingIcon.layer.removeAllAnimations()
            purchaseLoadingView?.isHidden = true
            return
        }
        if purchaseLoadingView == nil {
            purchaseLoadingIcon.contentMode = .scaleAspectFit
            purchaseLoadingIcon.isAccessibilityElement = false
            NSLayoutConstraint.activate([
                purchaseLoadingIcon.widthAnchor.constraint(equalToConstant: 28),
                purchaseLoadingIcon.heightAnchor.constraint(equalToConstant: 28)
            ])
            let label = text("Processing purchase…", 16)
            let panel = card([line([purchaseLoadingIcon, label], spacing: 12)])
            panel.translatesAutoresizingMaskIntoConstraints = false
            panel.isUserInteractionEnabled = false
            panel.isAccessibilityElement = true
            panel.accessibilityLabel = "Processing purchase"
            panel.accessibilityIdentifier = "wallet.purchase-loading"
            view.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                panel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
            ])
            purchaseLoadingView = panel
        }
        guard let panel = purchaseLoadingView else { return }
        panel.isHidden = false
        view.bringSubviewToFront(panel)
        guard purchaseLoadingIcon.layer.animation(forKey: "purchase-loading") == nil else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let animation = CABasicAnimation(keyPath: reduceMotion ? "opacity" : "transform.rotation.z")
        animation.fromValue = reduceMotion ? 0.5 : 0
        animation.toValue = reduceMotion ? 1 : Double.pi * 2
        animation.duration = reduceMotion ? 0.8 : 1.2
        animation.autoreverses = reduceMotion
        animation.repeatCount = .infinity
        purchaseLoadingIcon.layer.add(animation, forKey: "purchase-loading")
    }

}
