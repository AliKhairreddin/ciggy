import XCTest

final class CiggyLeaderboardUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testLeagueBrowsingDoesNotJoinAndConsentStartsOff() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["League"].tap()
        XCTAssertTrue(app.staticTexts["Ashtray League."].waitForExistence(timeout: 5))
        let consent = app.switches["league-public-consent"]
        let join = app.buttons["league-join"]
        scrollTo(consent, app: app)
        XCTAssertEqual(consent.value as? String, "0")
        scrollTo(join, app: app)
        XCTAssertFalse(join.isEnabled)
        capture(app, "League consent")
        let picker = app.segmentedControls.firstMatch
        scrollTo(picker, app: app)
        picker.buttons["Last week"].tap()
        XCTAssertTrue(picker.buttons["Last week"].isSelected)
        capture(app, "Previous league season")
        picker.buttons["This week"].tap()
        let rules = app.buttons["League rules & privacy"]
        scrollTo(rules, app: app)
        rules.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Equal totals share a rank")).firstMatch.exists)
    }

    @MainActor
    func testLeagueLargeTextKeepsJoinReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["League"].tap()
        let consent = app.switches["league-public-consent"]
        scrollTo(consent, app: app)
        XCTAssertTrue(consent.isHittable)
        XCTAssertEqual(consent.value as? String, "0")
        let join = app.buttons["league-join"]
        scrollTo(join, app: app)
        XCTAssertTrue(join.exists)
        XCTAssertFalse(join.isEnabled)
        capture(app, "League accessibility text")
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        let pane = app.scrollViews.firstMatch
        for _ in 0..<12 where !element.isHittable { pane.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
