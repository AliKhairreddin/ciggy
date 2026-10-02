//
//  ciggyUITests.swift
//  ciggyUITests
//
//  Created by Ali Khairreddin on 2026-07-14.
//

import XCTest

final class ciggyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testHistoricalDetectionPreview() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        let previewButton = app.buttons["Preview 6 detected in 8 hours"]
        for _ in 0..<5 where previewButton.isHittable == false {
            app.swipeUp()
        }
        XCTAssertTrue(previewButton.isHittable)
        previewButton.tap()

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["6 cigarettes detected"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Accurate"].exists)
        XCTAssertTrue(app.buttons["Adjust count"].exists)
    }

    @MainActor
    func testPhoneLoggingAndUndo() throws {
        let app = XCUIApplication()
        app.launch()
        let count = app.descendants(matching: .any)["today-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let initialLabel = count.label
        let initialCount = try XCTUnwrap(Int(initialLabel.split(separator: " ").first ?? ""))

        app.buttons["phone-log-button"].tap()
        XCTAssertTrue(app.buttons["save-phone-log"].waitForExistence(timeout: 3))
        app.buttons["save-phone-log"].tap()
        XCTAssertTrue(app.buttons["undo-phone-log"].waitForExistence(timeout: 3))
        XCTAssertEqual(count.label, "\(initialCount + 1) cigarettes today")

        app.buttons["undo-phone-log"].tap()
        XCTAssertEqual(count.label, initialLabel)
        app.terminate()
        app.launch()
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, initialLabel)
    }

    @MainActor
    func testCancelPhoneLogDoesNotChangeCount() throws {
        let app = XCUIApplication()
        app.launch()
        let count = app.descendants(matching: .any)["today-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let initialLabel = count.label
        app.buttons["phone-log-button"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(count.label, initialLabel)
    }

    @MainActor
    func testBrandScreensAndGoalPersistence() throws {
        let app = XCUIApplication()
        app.launch()
        capture(app, name: "Today")
        app.tabBars.buttons["Reports"].tap()
        XCTAssertTrue(app.staticTexts["You've got a rhythm."].waitForExistence(timeout: 3))
        capture(app, name: "Reports")
        app.tabBars.buttons["Goals"].tap()
        let value = app.staticTexts["daily-limit-value"]
        XCTAssertTrue(value.waitForExistence(timeout: 3))
        let initialLimit = try XCTUnwrap(Int(value.label))
        let increasing = initialLimit < 100
        app.buttons[increasing ? "Increase daily limit" : "Decrease daily limit"].tap()
        let changedLimit = initialLimit + (increasing ? 1 : -1)
        XCTAssertEqual(value.label, "\(changedLimit)")
        capture(app, name: "Goals")
        let save = app.buttons["Save my goals"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        save.tap()
        app.terminate()
        app.launch()
        app.tabBars.buttons["Goals"].tap()
        XCTAssertTrue(value.waitForExistence(timeout: 3))
        XCTAssertEqual(value.label, "\(changedLimit)")
        app.buttons[increasing ? "Decrease daily limit" : "Increase daily limit"].tap()
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["A little fine-tuning."].waitForExistence(timeout: 3))
        capture(app, name: "Settings")
    }

    @MainActor
    func testLargeTextCanReachPhoneLogging() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let log = app.buttons["phone-log-button"]
        for _ in 0..<8 where !log.isHittable { app.swipeUp() }
        XCTAssertTrue(log.isHittable)
        capture(app, name: "Today with large text")
        log.tap()
        XCTAssertTrue(app.buttons["save-phone-log"].waitForExistence(timeout: 3))
        capture(app, name: "Log with large text")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testAppearanceSwitchesImmediatelyAndPersists() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let appearance = app.segmentedControls["appearance-picker"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.buttons["Cream"].tap()
        XCTAssertTrue(appearance.buttons["Cream"].isSelected)
        capture(app, name: "Cream settings")

        appearance.buttons["Dark"].tap()
        XCTAssertTrue(appearance.buttons["Dark"].isSelected)
        app.tabBars.buttons["Today"].tap()
        capture(app, name: "Dark Today")
        app.terminate()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        XCTAssertTrue(appearance.buttons["Dark"].isSelected)

        appearance.buttons["Follow System"].tap()
        app.terminate()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        XCTAssertTrue(appearance.buttons["Follow System"].isSelected)
        appearance.buttons["Cream"].tap()
        app.tabBars.buttons["Today"].tap()
        capture(app, name: "Cream Today")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
