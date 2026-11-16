import XCTest

/// Opt-in device acceptance. Never confirms a payment unless the app has
/// identified Apple's Sandbox environment. Native account prompts require the owner.
final class AppleSandboxUITests: XCTestCase {
    func testNineSandboxPackages() throws {
        guard ProcessInfo.processInfo.environment["LULU_SANDBOX_UI_TESTS"] == "1" else {
            throw XCTSkip("Enable LULU_SANDBOX_UI_TESTS only for authorized Apple sandbox acceptance.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.buttons["Start exploring"].waitForExistence(timeout: 8) {
            app.buttons["Agree to the Terms of Service and Privacy Policy"].tap()
            app.buttons["Start exploring"].tap()
        }
        guard app.buttons["Me"].waitForExistence(timeout: 60) else {
            capture(app, name: "Entry blocked")
            XCTFail("Unable to reach Me through real authentication."); return
        }
        app.buttons["Me"].tap()
        let wallet = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wallet")).firstMatch
        XCTAssertTrue(wallet.waitForExistence(timeout: 15)); wallet.tap()
        let status = app.staticTexts["wallet.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Choose a coin package."), object: status)
        guard XCTWaiter.wait(for: [ready], timeout: 45) == .completed else {
            capture(app, name: "Catalog or delivery blocked")
            XCTFail("Checkout unavailable: \(status.label), environment: \(String(describing: status.value))"); return
        }
        XCTAssertEqual(status.value as? String, "Sandbox", "Never purchase in Production or Xcode in this test.")
        let initial = Int(app.staticTexts["wallet.balance"].label) ?? -1
        XCTAssertGreaterThanOrEqual(initial, 0)
        var expected = initial
        var failures: [String] = []
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for coins in [400, 800, 2450, 5150, 10800, 17000, 29400, 42700, 63700] {
            let package = app.buttons["wallet.package.\(coins)"]
            for _ in 0..<10 { if package.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(package.isHittable); package.tap()
            let confirm = app.buttons["Continue"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            let pay = system.buttons["pay-now"]
            guard pay.waitForExistence(timeout: 30) else {
                capture(system, name: "Apple authentication required \(coins)")
                XCTFail("Apple did not present a purchase confirmation button."); return
            }
            let disclaimer = system.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@", "仅用于测试", "for testing", "will not be charged")).firstMatch
            XCTAssertTrue(disclaimer.exists, "Require the native no-charge sandbox disclosure before confirming.")
            capture(system, name: "Native purchase \(coins)")
            pay.tap()
            // Apple Account passwords and side-button confirmation remain owner actions.
            let terminal = ["Coins added to your wallet.", "Purchase cancelled.", "The purchase is pending Apple approval.", "The purchase could not be confirmed. Retry to check for unfinished purchases.", "Your purchase is awaiting confirmation. Check pending purchases shortly."]
            let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label IN %@", terminal), object: status)
            guard XCTWaiter.wait(for: [delivered], timeout: 120) == .completed else {
                capture(system, name: "Purchase blocked \(coins)")
                capture(app, name: "Wallet after blocked purchase \(coins)")
                XCTFail("Sandbox purchase not completed for \(coins) coins."); return
            }
            print("SANDBOX_TIER coins=\(coins) status=\(status.label)")
            if status.label != "Coins added to your wallet." {
                failures.append("\(coins): \(status.label)")
                capture(app, name: "Not credited \(coins)")
                continue
            }
            expected += coins
            for _ in 0..<10 { if app.staticTexts["wallet.balance"].isHittable { break }; app.swipeDown() }
            XCTAssertEqual(app.staticTexts["wallet.balance"].label, String(expected))
            capture(app, name: "Credited \(coins)")
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: " | "))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Me"].waitForExistence(timeout: 60)); app.buttons["Me"].tap()
        let reopened = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wallet")).firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 15)); reopened.tap()
        let persisted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", String(expected)), object: app.staticTexts["wallet.balance"])
        XCTAssertEqual(XCTWaiter.wait(for: [persisted], timeout: 30), .completed)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " hierarchy"; tree.lifetime = .keepAlways; add(tree)
    }
}
