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
        struct Catalog: Decodable { let tiers: [CoinOffer] }
        offers = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)).tiers
    }

    override func tearDownWithError() throws {
        session?.clearTransactions()
        if let directory, FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testNineProductsCreditOnceAndPersist() async throws {
        let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
        let products = try await Product.products(for: offers.map(\.productID))
        XCTAssertEqual(products.count, 9)
        var expected = 0
        for offer in offers {
            let product = try XCTUnwrap(products.first { $0.id == offer.productID })
            XCTAssertEqual(product.type, .consumable)
            XCTAssertEqual(product.price, prices[offer.productID])
            let outcome = try await product.purchase(options: [.appAccountToken(account)])
            guard case .success(let result) = outcome else { XCTFail("Expected successful local purchase"); return }
            let state = try await wallet.deliver(result, account: account)
            expected += offer.coins
            XCTAssertEqual(state.balance, expected)
            let duplicate = try await wallet.deliver(result, account: account)
            XCTAssertEqual(duplicate.balance, expected)
            let reopened = LocalStoreKitWallet(directory: directory, offers: offers)
            XCTAssertEqual(try reopened.state(account: account).balance, expected)
        }
        XCTAssertEqual(expected, 172400)
        XCTAssertEqual(try wallet.state(account: account).entries.count, 9)
    }

    func testWrongAccountCannotReceivePurchase() async throws {
        let offer = try XCTUnwrap(offers.first)
        let fetched = try await Product.products(for: [offer.productID])
        let product = try XCTUnwrap(fetched.first)
        guard case .success(let result) = try await product.purchase(options: [.appAccountToken(account)]) else { XCTFail("Missing transaction"); return }
        let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
        let other = UUID()
        do { _ = try await wallet.deliver(result, account: other); XCTFail("Wrong account accepted") }
        catch LocalStoreKitWallet.Failure.invalidTransaction { }
        XCTAssertEqual(try wallet.state(account: other).balance, 0)
        let delivered = try await wallet.deliver(result, account: account)
        XCTAssertEqual(delivered.balance, offer.coins)
    }

    func testGuideSpendingUsesPurchasedBalanceAndPersistsAccess() async throws {
        let offer = try XCTUnwrap(offers.first { $0.coins == 400 })
        let products = try await Product.products(for: [offer.productID])
        let product = try XCTUnwrap(products.first)
        guard case .success(let result) = try await product.purchase(options: [.appAccountToken(account)]) else {
            XCTFail("Missing transaction"); return
        }
        let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
        _ = try await wallet.deliver(result, account: account)
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
        let redelivered = try await reopened.deliver(result, account: account)
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

    func testCancellationDoesNotCredit() async throws {
        let offer = try XCTUnwrap(offers.first)
        let fetched = try await Product.products(for: [offer.productID])
        let product = try XCTUnwrap(fetched.first)
        if #available(iOS 17.0, *) {
            try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
            let result = try await product.purchase(options: [.appAccountToken(account)])
            guard case .userCancelled = result else { XCTFail("Expected cancellation"); return }
            let wallet = LocalStoreKitWallet(directory: directory, offers: offers)
            XCTAssertEqual(try wallet.state(account: account).balance, 0)
        } else { throw XCTSkip("Error injection requires iOS 17") }
    }
}
