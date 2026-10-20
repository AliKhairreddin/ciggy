import XCTest

final class CiggyAdaptiveUITests: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	override func tearDown() async throws {
		await MainActor.run { XCUIDevice.shared.orientation = .portrait }
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
		let controls = app.scrollViews["controls-pane"]
		scrollTo(log, in: controls)
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
		for _ in 0..<8 where !undo.isHittable { pane.swipeDown() }
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
		XCTAssertFalse(app.buttons["save-phone-log"].exists)
		capture(app, "Tabletop preview")
		let log = app.buttons["phone-log-button"]
		scrollTo(log, in: controls)
		XCTAssertTrue(log.isHittable)
		log.tap()
		let field = app.textFields["phone-log-note"].exists
			? app.textFields["phone-log-note"] : app.textViews["phone-log-note"]
		field.tap()
		field.typeText("A small pause")
		if app.buttons["Done"].isHittable { app.buttons["Done"].tap() }
		XCUIDevice.shared.orientation = .landscapeLeft
		XCTAssertEqual(field.value as? String, "A small pause")
		let save = app.buttons["save-phone-log"]
		for _ in 0..<6 where !save.isHittable { app.swipeUp() }
		XCTAssertTrue(save.isHittable)
		save.tap()
		XCTAssertTrue(controls.waitForExistence(timeout: 5))
		XCTAssertLessThan(overview.frame.maxX, controls.frame.minX)
		let undo = app.buttons["undo-phone-log"]
		scrollTo(undo, in: controls)
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
		for _ in 0..<6 where !change.isHittable { controls.swipeUp(velocity: .slow) }
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
		XCTAssertFalse(app.buttons["save-phone-log"].exists)
		let log = app.buttons["phone-log-button"]
		for _ in 0..<16 where !log.isHittable { controls.swipeUp(velocity: .slow) }
		XCTAssertTrue(log.isHittable)
		capture(app, "Tabletop with large text")
		log.tap()
		let save = app.buttons["save-phone-log"]
		for _ in 0..<10 where !save.isHittable { app.swipeUp() }
		XCTAssertTrue(save.isHittable)
	}

	@MainActor
	private func scrollTo(_ target: XCUIElement, in pane: XCUIElement) {
		// A full fling can skip a small secondary action in a short pane.
		// Drag in small steps and recover if the action has passed above us.
		for _ in 0..<30 {
			let targetFrame = target.frame
			let viewport = pane.frame.insetBy(dx: 0, dy: 12)
			// XCTest can throw when asking hittability for a fully clipped item.
			if viewport.contains(targetFrame), target.isHittable { return }
			let start = pane.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
			let end = pane.coordinate(withNormalizedOffset: CGVector(
				dx: 0.85, dy: targetFrame.midY < viewport.minY ? 0.7 : 0.3
			))
			start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
		}
	}

	@MainActor
	private func capture(_ app: XCUIApplication, _ name: String) {
		let attachment = XCTAttachment(screenshot: app.screenshot())
		attachment.name = name
		attachment.lifetime = .keepAlways
		add(attachment)
	}
}
