//
//  ciggyUITests.swift
//  ciggyUITests
//
//  Created by Ali Khairreddin on 2026-07-14.
//

import XCTest

final class ciggyUITests: XCTestCase {

    override func setUp() async throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }

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

        openSettings(app)
        let previewButton = app.buttons["Preview 6 detected in 8 hours"]
        for _ in 0..<5 where previewButton.isHittable == false {
            app.swipeUp()
        }
        XCTAssertTrue(previewButton.isHittable)
        previewButton.tap()

        closeSettings(app)
        let detection = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "cigarettes detected today")).firstMatch
        for _ in 0..<8 where !detection.isHittable { app.swipeUp() }
        XCTAssertTrue(detection.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Accurate"].exists)
        XCTAssertTrue(app.buttons["Adjust count"].exists)
    }

    @MainActor
    func testCalibrationRequiresExplicitConsentAndPairing() throws {
        let app = XCUIApplication()
        app.launch()
        openSettings(app)
        let calibration = app.buttons["calibration-settings-link"]
        for _ in 0..<8 where !calibration.isHittable { app.swipeUp() }
        XCTAssertTrue(calibration.isHittable)
        calibration.tap()
        let consent = app.switches["I agree to share my motion for calibration"]
        for _ in 0..<8 where !consent.isHittable { app.swipeUp() }
        XCTAssertTrue(consent.waitForExistence(timeout: 3))
        XCTAssertEqual(consent.value as? String, "0")
        let pair = app.buttons["Pair and start sharing"]
        XCTAssertTrue(pair.exists)
        XCTAssertFalse(pair.isEnabled, "An empty pairing or absent consent must never start sharing.")
    }

    @MainActor
    func testHistoricalCorrectionPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        openSettings(app)
        let preview = app.buttons["Preview 6 detected in 8 hours"]
        for _ in 0..<8 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        closeSettings(app)

        let total = app.descendants(matching: .any)["today-count"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        let countBefore = try XCTUnwrap(Int(total.label.split(separator: " ").first ?? ""))
        let adjust = app.buttons["Adjust count"].firstMatch
        for _ in 0..<10 where !adjust.isHittable { app.swipeUp() }
        XCTAssertTrue(adjust.isHittable)
        adjust.tap()

        let stepper = app.steppers["review-count-stepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 3))
        let originalCount = try XCTUnwrap(Int(stepper.value as? String ?? ""))
        XCTAssertGreaterThan(originalCount, 0)
        stepper.buttons["review-count-stepper-Decrement"].tap()
        XCTAssertEqual(stepper.value as? String, "\(originalCount - 1)")
        let save = app.buttons["save-review-correction"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        save.tap()

        XCTAssertTrue(stepper.waitForNonExistence(timeout: 5), "A successful durable correction dismisses its sheet.")
        for _ in 0..<10 where !total.isHittable { app.swipeDown() }
        let expected = "\(countBefore - 1) cigarettes today"
        expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: total)
        waitForExpectations(timeout: 5)
        app.terminate()
        app.launch()
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, expected)
    }

    @MainActor
    func testPhoneLoggingAndUndo() throws {
        let app = XCUIApplication()
        app.launch()
        let count = app.descendants(matching: .any)["today-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let initialLabel = count.label
        let initialCount = try XCTUnwrap(Int(initialLabel.split(separator: " ").first ?? ""))

        openManualLog(app)
        XCTAssertTrue(app.buttons["save-phone-log"].waitForExistence(timeout: 3))
        app.buttons["save-phone-log"].tap()
        let undo = app.buttons["undo-phone-log"]
        for _ in 0..<8 where !undo.isHittable { app.swipeDown() }
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
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
        openManualLog(app)
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
        openSettings(app)
        XCTAssertTrue(app.staticTexts["A little fine-tuning."].waitForExistence(timeout: 3))
        capture(app, name: "Settings")
    }

    @MainActor
    func testLargeTextCanReachPhoneLogging() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let log = app.buttons["phone-log-button"]
        let pane = app.scrollViews["compact-pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5))
        scrollTo(log, in: pane)
        XCTAssertTrue(log.isHittable)
        XCTAssertTrue(pane.frame.insetBy(dx: 0, dy: 12).contains(log.frame))
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
        openSettings(app)
        let appearance = app.segmentedControls["appearance-picker"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.buttons["Cream"].tap()
        XCTAssertTrue(appearance.buttons["Cream"].isSelected)
        capture(app, name: "Cream settings")

        appearance.buttons["Dark"].tap()
        XCTAssertTrue(appearance.buttons["Dark"].isSelected)
        closeSettings(app)
        capture(app, name: "Dark Today")
        app.terminate()
        app.launch()
        openSettings(app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        XCTAssertTrue(appearance.buttons["Dark"].isSelected)

        appearance.buttons["Follow System"].tap()
        app.terminate()
        app.launch()
        openSettings(app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        XCTAssertTrue(appearance.buttons["Follow System"].isSelected)
        appearance.buttons["Cream"].tap()
        closeSettings(app)
        capture(app, name: "Cream Today")
    }

    @MainActor
    func testProfileIsTheOnlySettingsEntryAndManualLogIsSecondary() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        XCTAssertTrue(app.buttons["phone-profile-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Log a cigarette"].exists)
        openSettings(app)
        XCTAssertTrue(app.staticTexts["A little fine-tuning."].waitForExistence(timeout: 3))
        closeSettings(app)
        openManualLog(app)
        XCTAssertTrue(app.buttons["save-phone-log"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testTodayAndLogDeepLinksReturnFromProfile() throws {
        let app = XCUIApplication()
        app.launch()
        openSettings(app)
        app.open(try XCTUnwrap(URL(string: "ciggy://today")))
        XCTAssertTrue(app.buttons["phone-profile-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Settings"].exists)
        openSettings(app)
        app.open(try XCTUnwrap(URL(string: "ciggy://log")))
        XCTAssertTrue(app.buttons["save-phone-log"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["phone-profile-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Settings"].exists)
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        app.tabBars.buttons["Today"].tap()
        let profile = app.buttons["phone-profile-button"]
        for _ in 0..<8 where !profile.isHittable { app.swipeDown() }
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
    }

    @MainActor
    private func closeSettings(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
    }

    @MainActor
    private func scrollTo(_ target: XCUIElement, in pane: XCUIElement) {
        // Short bidirectional drags cannot skip a control and keep moving away.
        for _ in 0..<40 {
            let targetFrame = target.frame
            let viewport = pane.frame.insetBy(dx: 0, dy: 12)
            if viewport.contains(targetFrame), target.isHittable { return }
            let start = pane.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            let end = pane.coordinate(withNormalizedOffset: CGVector(
                dx: 0.85, dy: targetFrame.midY < viewport.minY ? 0.7 : 0.3
            ))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    @MainActor
    private func openManualLog(_ app: XCUIApplication) {
        let log = app.buttons["phone-log-button"]
        for _ in 0..<10 where !log.isHittable { app.swipeUp() }
        XCTAssertTrue(log.isHittable)
        log.tap()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLiveActivityStartsSurvivesRelaunchAndStops() throws {
        let app = XCUIApplication()
        app.launch()
        let button = app.buttons["live-activity-button"]
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        if button.label == "Stop Live Activity" { button.tap() }
        XCTAssertTrue(app.buttons["Start Live Activity"].waitForExistence(timeout: 5))
        button.tap()
        let stop = app.buttons["Stop Live Activity"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        for _ in 0..<8 where !stop.isHittable { app.swipeUp() }
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        capture(app, name: "Live Activity controls")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.icons["ciggy"].waitForExistence(timeout: 5))
        let island = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        island.name = "Dynamic Island"
        island.lifetime = .keepAlways
        add(island)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let resumedButton = app.buttons.matching(identifier: "live-activity-button").firstMatch
        let ready = NSPredicate(format: "isHittable == true AND isEnabled == true")
        expectation(for: ready, evaluatedWith: resumedButton)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(resumedButton.label, "Stop Live Activity")
        resumedButton.tap()
        XCTAssertTrue(app.buttons["Start Live Activity"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
