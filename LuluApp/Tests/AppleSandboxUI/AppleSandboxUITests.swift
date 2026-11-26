import XCTest

/// Opt-in device acceptance. Never confirms a payment unless the app has
/// identified Apple's Sandbox environment. Native account prompts require the owner.
final class AppleSandboxUITests: XCTestCase {
    func testNineSandboxPackages() throws {
        try purchasePackages([400, 800, 2450, 5150, 10800, 17000, 29400, 42700, 63700])
    }

    func testFirstSandboxPackage() throws {
        try purchasePackages([400])
    }

    private func purchasePackages(_ coinAmounts: [Int]) throws {
        guard ProcessInfo.processInfo.environment["LULU_SANDBOX_UI_TESTS"] == "1" else {
            throw XCTSkip("Enable LULU_SANDBOX_UI_TESTS only for authorized Apple sandbox acceptance.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        try openProfileAfterOwnerSignIn(app)
        let wallet = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wallet")).firstMatch
        XCTAssertTrue(wallet.waitForExistence(timeout: 15)); wallet.tap()
        let status = app.staticTexts["wallet.status"]
        let problem = app.alerts["Lulu"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            problem.exists || (status.exists && status.label == "Choose a coin package.")
        }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 45) == .completed, !problem.exists else {
            capture(app, name: "Catalog or delivery blocked")
            let reason = problem.exists ? problem.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ") : "Catalog timed out."
            XCTFail("Checkout unavailable: \(reason)")
            return
        }
        XCTAssertEqual(status.value as? String, "Sandbox", "Never purchase in Production or Xcode in this test.")
        let initial = Int(app.staticTexts["wallet.balance"].label) ?? -1
        XCTAssertGreaterThanOrEqual(initial, 0)
        var expected = initial
        var failures: [String] = []
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for coins in coinAmounts {
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
            let terminal = ["Coins added to your wallet.", "Purchase cancelled.", "The purchase is pending Apple approval."]
            let delivered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                problem.exists || (status.exists && terminal.contains(status.label))
            }, object: nil)
            guard XCTWaiter.wait(for: [delivered], timeout: 120) == .completed else {
                capture(system, name: "Purchase blocked \(coins)")
                capture(app, name: "Wallet after blocked purchase \(coins)")
                XCTFail("Sandbox purchase not completed for \(coins) coins."); return
            }
            if problem.exists {
                capture(app, name: "Wallet alert for \(coins) coins")
                let reason = problem.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
                failures.append("\(coins): \(reason)")
                problem.buttons["OK"].tap()
                continue
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
        try openProfileAfterOwnerSignIn(app)
        let reopened = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wallet")).firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 15)); reopened.tap()
        let persisted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", String(expected)), object: app.staticTexts["wallet.balance"])
        XCTAssertEqual(XCTWaiter.wait(for: [persisted], timeout: 30), .completed)
    }

    private func openProfileAfterOwnerSignIn(_ app: XCUIApplication) throws {
        let profile = app.buttons["Me"]
        guard profile.waitForExistence(timeout: 120) else {
            throw NSError(domain: "LuluAppleSandboxUITests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Complete email sign-in and consent on the device after each launch."
            ])
        }
        profile.tap()
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " hierarchy"; tree.lifetime = .keepAlways; add(tree)
    }
}
