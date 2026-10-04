import XCTest

final class CiggyAdaptiveUITests: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	@MainActor
	func testRotationKeepsPhoneLoggingAndUndo() throws {
		XCUIDevice.shared.orientation = .portrait
		let app = XCUIApplication()
		app.launch()
		let count = app.descendants(matching: .any)["today-count"].firstMatch
		XCTAssertTrue(count.waitForExistence(timeout: 5))
		let original = count.label
		XCUIDevice.shared.orientation = .landscapeLeft
		let overview = app.scrollViews["overview-pane"]
		XCTAssertTrue(overview.waitForExistence(timeout: 5))
		let log = app.buttons["phone-log-button"]
		for _ in 0..<6 where !log.isHittable { overview.swipeUp() }
		XCTAssertTrue(log.isHittable)
		capture(app, "Open landscape")
		log.tap()
		let save = app.buttons["save-phone-log"]
		for _ in 0..<4 where !save.isHittable { app.swipeUp() }
		XCTAssertTrue(save.isHittable)
		save.tap()
		XCUIDevice.shared.orientation = .portrait
		let undo = app.buttons["undo-phone-log"]
		let pane = app.scrollViews.firstMatch
		for _ in 0..<6 where !undo.isHittable { pane.swipeUp() }
		XCTAssertTrue(undo.isHittable)
		undo.tap()
		XCTAssertEqual(count.label, original)
		capture(app, "Open portrait")
	}

	@MainActor
	func testFoldedDraftLoggingAndUndoAcrossRotation() throws {
		XCUIDevice.shared.orientation = .portrait
		let app = XCUIApplication()
		app.launchArguments = ["--ciggy-preview-fold"]
		app.launch()
		let overview = app.scrollViews["overview-pane"]
		let controls = app.scrollViews["controls-pane"]
		XCTAssertTrue(controls.waitForExistence(timeout: 5))
		XCTAssertLessThan(overview.frame.maxY, controls.frame.minY)
		let count = app.descendants(matching: .any)["today-count"].firstMatch
		let original = count.label
		capture(app, "Tabletop preview")
		let field = app.textFields["phone-log-note"].exists
			? app.textFields["phone-log-note"] : app.textViews["phone-log-note"]
		field.tap()
		field.typeText("A small pause")
		if app.buttons["Done"].isHittable { app.buttons["Done"].tap() }
		XCUIDevice.shared.orientation = .landscapeLeft
		XCTAssertTrue(controls.waitForExistence(timeout: 5))
		XCTAssertLessThan(overview.frame.maxX, controls.frame.minX)
		XCTAssertEqual(field.value as? String, "A small pause")
		let save = app.buttons["save-phone-log"]
		for _ in 0..<6 where !save.isHittable { controls.swipeUp() }
		XCTAssertTrue(save.isHittable)
		save.tap()
		let undo = app.buttons["undo-phone-log"]
		for _ in 0..<6 where !undo.isHittable { controls.swipeUp() }
		XCTAssertTrue(undo.isHittable)
		capture(app, "Book preview with saved check-in")
		undo.tap()
		XCTAssertEqual(count.label, original)
		XCUIDevice.shared.orientation = .portrait
	}

	@MainActor
	func testFoldedGoalDraftAndReportRangeSurviveRotation() throws {
		XCUIDevice.shared.orientation = .portrait
		let app = XCUIApplication()
		app.launchArguments = ["--ciggy-preview-fold"]
		app.launch()
		app.buttons["Goals"].tap()
		let value = app.staticTexts["daily-limit-value"]
		XCTAssertTrue(value.waitForExistence(timeout: 5))
		let original = try XCTUnwrap(Int(value.label))
		let increasing = original < 100
		let change = app.buttons[increasing ? "Increase daily limit" : "Decrease daily limit"]
		let controls = app.scrollViews["controls-pane"]
		for _ in 0..<6 where !change.isHittable { controls.swipeUp() }
		change.tap()
		XCUIDevice.shared.orientation = .landscapeLeft
		XCTAssertEqual(value.label, "\(original + (increasing ? 1 : -1))")
		capture(app, "Book goals draft")
		app.buttons["Reports"].tap()
		let picker = app.segmentedControls["report-range-picker"]
		XCTAssertTrue(picker.waitForExistence(timeout: 5))
		picker.buttons["30 days"].tap()
		XCUIDevice.shared.orientation = .portrait
		XCTAssertTrue(picker.buttons["30 days"].isSelected)
		capture(app, "Tabletop reports")
	}

	@MainActor
	func testFoldedLargeTextKeepsControlsReachable() {
		XCUIDevice.shared.orientation = .portrait
		let app = XCUIApplication()
		app.launchArguments = ["--ciggy-preview-fold", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
		app.launch()
		let controls = app.scrollViews["controls-pane"]
		XCTAssertTrue(controls.waitForExistence(timeout: 5))
		let save = app.buttons["save-phone-log"]
		for _ in 0..<10 where !save.isHittable { controls.swipeUp() }
		XCTAssertTrue(save.isHittable)
		capture(app, "Tabletop with large text")
	}

	@MainActor
	private func capture(_ app: XCUIApplication, _ name: String) {
		let attachment = XCTAttachment(screenshot: app.screenshot())
		attachment.name = name
		attachment.lifetime = .keepAlways
		add(attachment)
	}
}
