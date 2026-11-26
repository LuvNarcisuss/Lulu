import XCTest
import StoreKit
import StoreKitTest
@testable import TravelApp

@MainActor
final class LocalPurchaseTests: XCTestCase {
    private var session: SKTestSession!
    private var directory: URL!
    private var offers: [CoinOffer] = []
    private var account: UUID!
    private var prices: [String: Decimal] = [:]
    private var observer: StoreKitOneObserver!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LuluCoins", withExtension: "storekit"))
        let data = try Data(contentsOf: fixture)
        let fixtureJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for row in try XCTUnwrap(fixtureJSON["products"] as? [[String: Any]]) {
            let id = try XCTUnwrap(row["productID"] as? String)
            prices[id] = try XCTUnwrap(Decimal(string: try XCTUnwrap(row["displayPrice"] as? String)))
        }
        session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LuluPurchaseTests-" + UUID().uuidString)
        account = UUID()
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PaymentCatalog", withExtension: "json"))
        let catalog = try JSONDecoder().decode(CoinCatalog.self, from: Data(contentsOf: url))
        offers = catalog.offers(localStoreKit: true)
        observer = StoreKitOneObserver()
        SKPaymentQueue.default().add(observer)
    }

    override func tearDownWithError() throws {
        if let observer { SKPaymentQueue.default().remove(observer) }
        session?.clearTransactions()
        if let directory, FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testInstallationReceiptOnlyProvidesAnInitialWalletHint() {
        let sandbox = URL(fileURLWithPath: "/StoreKit/sandboxReceipt")
        XCTAssertEqual(CoinWalletEnvironment.installation(receiptURL: sandbox, localTesting: false, bundleID: "com.lulu.tourtravel"), .sandbox)
        XCTAssertEqual(CoinWalletEnvironment.installation(receiptURL: nil, localTesting: false, bundleID: "com.lulu.tourtravel"), .production)
        XCTAssertEqual(CoinWalletEnvironment.installation(receiptURL: nil, localTesting: false, bundleID: "im.seex.sao2"), .sandbox)
        XCTAssertEqual(CoinWalletEnvironment.installation(receiptURL: nil, localTesting: false, bundleID: "other.app"), .production)
        XCTAssertEqual(CoinWalletEnvironment.installation(receiptURL: sandbox, localTesting: true, bundleID: "im.seex.sao2"), .xcode)
    }

    func testConfirmedSandboxPurchaseSelectsSandboxBalanceAfterProductionInstallLookup() {
        var routing = CoinWalletRouting()
        XCTAssertEqual(routing.useInstallation(.production).statePath, "rest/v1/rpc/travel_coin_state")
        let acknowledgment = Record(["committed": .bool(true), "environment": .string("Sandbox")])
        XCTAssertEqual(routing.acknowledge(acknowledgment), .sandbox)
        XCTAssertEqual(routing.useInstallation(.production).statePath, "rest/v1/rpc/travel_sandbox_coin_state")
        XCTAssertEqual(routing.environment, .sandbox)
    }

    func testFailedOrUnsupportedDeliveryCannotSelectAnotherWallet() {
        var routing = CoinWalletRouting()
        _ = routing.useInstallation(.production)
        XCTAssertNil(routing.acknowledge(Record(["committed": .bool(false), "environment": .string("Sandbox")])))
        XCTAssertNil(routing.acknowledge(Record(["committed": .bool(true), "environment": .string("Xcode")])))
        XCTAssertNil(routing.acknowledge(Record(["committed": .bool(true)])))
        XCTAssertEqual(routing.environment, .production)
    }

    func testNineProductsCreditOnceAndPersist() async throws {
        let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
        let products = await fetchProducts()
        XCTAssertEqual(products.count, 9)
        var expected = 0
        for offer in offers {
            let product = try XCTUnwrap(products.first { $0.productIdentifier == offer.productID })
            XCTAssertEqual(product.price.decimalValue, prices[offer.productID])
            let queued = try await submit(product)
            XCTAssertEqual(queued.transactionState, .purchased)
            XCTAssertEqual(queued.payment.applicationUsername.flatMap { UUID(uuidString: $0) }, account)
            let state = try wallet.credit(queued, account: account)
            expected += offer.coins
            XCTAssertEqual(state.balance, expected)
            let duplicate = try wallet.credit(queued, account: account)
            XCTAssertEqual(duplicate.balance, expected)
            try await finish(queued)
            let reopened = LocalStoreKitWallet(directory: directory, offers: offers)
            XCTAssertEqual(try reopened.state(account: account).balance, expected)
        }
        XCTAssertEqual(expected, 172400)
        XCTAssertEqual(try wallet.state(account: account).entries.count, 9)
    }

    func testWrongAccountCannotReceivePurchase() async throws {
        let products = await fetchProducts()
        let product = try XCTUnwrap(products.first)
        let queued = try await submit(product)
        let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
        let other = UUID()
        do { _ = try wallet.credit(queued, account: other); XCTFail("Wrong account accepted") }
        catch LocalStoreKitWallet.Failure.invalidTransaction { }
        XCTAssertEqual(try wallet.state(account: other).balance, 0)
        let delivered = try wallet.credit(queued, account: account)
        try await finish(queued)
        XCTAssertEqual(delivered.balance, offers.first { $0.productID == product.productIdentifier }?.coins)
    }

    func testGuideSpendingUsesPurchasedBalanceAndPersistsAccess() async throws {
        let offer = try XCTUnwrap(offers.first { $0.coins == 400 })
        let products = await fetchProducts()
        let product = try XCTUnwrap(products.first { $0.productIdentifier == offer.productID })
        let queued = try await submit(product)
        let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
        _ = try wallet.credit(queued, account: account)
        try await finish(queued)
        let guides = LocalGuideFixtures.guides
        let first = try XCTUnwrap(guides.first)
        let second = try XCTUnwrap(guides.dropFirst().first)
        let third = try XCTUnwrap(guides.dropFirst(2).first)
        XCTAssertEqual(try wallet.unlock(first, price: 180, account: account).balance, 220)
        XCTAssertEqual(try wallet.unlock(first, price: 180, account: account).balance, 220)
        let reopened = LocalStoreKitWallet(directory: directory, offers: offers)
        XCTAssertEqual(try reopened.state(account: account).unlocks[first.id]?.guide, first)
        XCTAssertEqual(try reopened.state(account: account).balance, 220)
        XCTAssertEqual(try reopened.unlock(second, price: 220, account: account).balance, 0)
        do {
            _ = try reopened.unlock(third, price: 140, account: account)
            XCTFail("Insufficient balance accepted")
        } catch GuidePurchaseFailure.insufficientCoins(let balance, let price) {
            XCTAssertEqual(balance, 0)
            XCTAssertEqual(price, 140)
        }
        XCTAssertEqual(try reopened.state(account: account).unlocks.count, 2)
        XCTAssertEqual(try reopened.state(account: UUID()).unlocks.count, 0)
        XCTAssertEqual(try reopened.state(account: account).balance, 0)
        // Re-delivery must not restore coins already spent on guides.
        let redelivered = try reopened.credit(queued, account: account)
        XCTAssertEqual(redelivered.balance, 0)
    }

    func testLegacyCreditOnlyLedgerPreservesBalance() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy: [String: Any] = [
            "account": account.uuidString,
            "entries": ["legacy": ["transactionID": "legacy", "productID": offers[0].productID,
                                    "coins": 400, "date": 0]]
        ]
        let file = directory.appendingPathComponent(account.uuidString.lowercased() + ".json")
        try JSONSerialization.data(withJSONObject: legacy).write(to: file, options: .atomic)
        let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
        let state = try wallet.state(account: account)
        XCTAssertEqual(state.balance, 400)
        XCTAssertTrue(state.unlocks.isEmpty)
    }

    func testMissingGuideContentDoesNotDebit() throws {
        let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
        do {
            _ = try wallet.unlock(Record(["id": .string(UUID().uuidString)]), price: 140, account: account)
            XCTFail("Missing local guide accepted")
        } catch LocalStoreKitWallet.Failure.invalidGuide { }
        XCTAssertEqual(try wallet.state(account: account).balance, 0)
        XCTAssertTrue(try wallet.state(account: account).unlocks.isEmpty)
    }

    func testFailedPaymentDoesNotCredit() async throws {
        let products = await fetchProducts()
        let product = try XCTUnwrap(products.first)
        session.failureError = .unknown
        session.failTransactionsEnabled = true
        let queued = try await submit(product)
        XCTAssertEqual(queued.transactionState, .failed)
        let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
        XCTAssertThrowsError(try wallet.credit(queued, account: account))
        XCTAssertEqual(try wallet.state(account: account).balance, 0)
    }

    private func fetchProducts() async -> [SKProduct] {
        let request = SKProductsRequest(productIdentifiers: Set(offers.map(\.productID)))
        let received = expectation(description: "StoreKit 1 product request")
        observer.productReceived = received
        request.delegate = observer
        defer { request.cancel() }
        request.start()
        await fulfillment(of: [received], timeout: 10)
        return observer.products
    }

    private func submit(_ product: SKProduct) async throws -> SKPaymentTransaction {
        let received = expectation(description: "StoreKit 1 purchase callback")
        observer.productID = product.productIdentifier
        observer.transaction = nil
        observer.purchaseReceived = received
        let payment = SKMutablePayment(product: product)
        payment.applicationUsername = account.uuidString
        SKPaymentQueue.default().add(payment)
        await fulfillment(of: [received], timeout: 15)
        return try XCTUnwrap(observer.transaction)
    }

    private func finish(_ transaction: SKPaymentTransaction) async throws {
        let removed = expectation(description: "StoreKit 1 transaction leaves the queue")
        observer.removalID = try XCTUnwrap(transaction.transactionIdentifier)
        observer.transactionRemoved = removed
        SKPaymentQueue.default().finishTransaction(transaction)
        await fulfillment(of: [removed], timeout: 10)
    }
}

@MainActor
private final class StoreKitOneObserver: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    var productReceived: XCTestExpectation?
    var purchaseReceived: XCTestExpectation?
    var transactionRemoved: XCTestExpectation?
    var removalID: String?
    var products: [SKProduct] = []
    var productID: String?
    var transaction: SKPaymentTransaction?

    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor in
            products = response.products
            productReceived?.fulfill()
            productReceived = nil
        }
    }

    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor in
            XCTFail("StoreKit 1 catalog request failed: \(error)")
            productReceived?.fulfill()
            productReceived = nil
        }
    }

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            guard purchaseReceived != nil, let terminal = transactions.first(where: {
                $0.payment.productIdentifier == productID &&
                    ($0.transactionState == .purchased || $0.transactionState == .failed)
            }) else { return }
            transaction = terminal
            purchaseReceived?.fulfill()
            purchaseReceived = nil
        }
    }

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            guard let removalID, transactions.contains(where: { $0.transactionIdentifier == removalID }) else { return }
            transactionRemoved?.fulfill()
            transactionRemoved = nil
        }
    }
}
