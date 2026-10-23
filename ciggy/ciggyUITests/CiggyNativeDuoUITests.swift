import XCTest

/// Use Device Hub to set the actual hinge and rotate its display surfaces before
/// each run. XCUIDevice.orientation does not rotate Duo on this runtime.
final class CiggyNativeDuoUITests: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
		try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4",
			"Native hinge validation requires the iPhone Duo simulator.")
	}

	@MainActor
	func testNativeCurrentPoseUsesRealHinge() throws {
		let app = XCUIApplication()
		app.launch()
		let posture = app.descendants(matching: .any).matching(NSPredicate(format:
			"identifier IN %@", ["duo-posture", "duo-lounge-scene"])).firstMatch
		XCTAssertTrue(posture.waitForExistence(timeout: 10), "Require the real hinge API")
		let desk = posture.label.contains("Desk mode")
		let overview = app.descendants(matching: .any)[desk ? "immersive-overview-pane" : "overview-pane"].firstMatch
		let controls = app.descendants(matching: .any)[desk ? "immersive-controls-pane" : "controls-pane"].firstMatch
		if posture.label.contains("Cover display") {
			XCTAssertTrue(app.scrollViews["compact-pane"].exists || overview.exists)
		} else {
			XCTAssertTrue(overview.exists)
			XCTAssertTrue(controls.exists)
			XCTAssertFalse(overview.frame.intersects(controls.frame))
			if desk {
				XCTAssertLessThan(overview.frame.maxY, controls.frame.minY)
				XCTAssertTrue(app.buttons["duo-music-play"].isHittable)
				let window = app.windows.firstMatch.frame
				XCTAssertEqual(overview.frame.minY, window.minY, accuracy: 2)
				XCTAssertEqual(overview.frame.width, window.width, accuracy: 2)
				XCTAssertEqual(controls.frame.maxY, window.maxY, accuracy: 2)
				XCTAssertEqual(controls.frame.width, window.width, accuracy: 2)
				XCTAssertFalse(app.buttons["phone-profile-button"].exists)
				XCTAssertFalse(app.buttons["phone-log-button"].exists)
				XCTAssertFalse(app.buttons["Reports"].exists)
				XCTAssertFalse(app.buttons["Goals"].exists)
			} else if posture.label.contains("Book mode") {
				XCTAssertLessThan(overview.frame.maxX, controls.frame.minX)
				XCTAssertTrue(app.descendants(matching: .any)["book-summary"].firstMatch.exists)
				XCTAssertTrue(app.buttons["phone-log-button"].isHittable)
			} else {
				XCTAssertTrue(posture.label.contains("Fully open"))
			}
		}
		if !desk {
			XCTAssertFalse(app.buttons["duo-lounge-scene"].exists)
			XCTAssertFalse(app.buttons["duo-music-play"].exists)
		}
		let attachment = XCTAttachment(screenshot: app.screenshot())
		attachment.name = "Native Duo \(posture.label) \(posture.value ?? "")"
		attachment.lifetime = .keepAlways
		add(attachment)
	}

	@MainActor
	func testNativeLoungePlaysChangesTrackAndPausesInBackground() throws {
		let app = XCUIApplication()
		app.launch()
		let play = app.buttons["duo-music-play"]
		try XCTSkipUnless(play.waitForExistence(timeout: 5), "Set Duo to the native laptop pose in Device Hub")
		XCTAssertEqual(play.label, "Play ambient music")
		play.tap()
		let playing = NSPredicate(format: "label == %@", "Pause ambient music")
		expectation(for: playing, evaluatedWith: play)
		waitForExpectations(timeout: 15)
		let progress = app.progressIndicators["duo-music-progress"]
		XCTAssertTrue(progress.waitForExistence(timeout: 5))
		expectation(for: NSPredicate(format: "value MATCHES %@", "[1-9][0-9]* of 24 seconds"), evaluatedWith: progress)
		waitForExpectations(timeout: 15)
		app.buttons["Next ambient track"].tap()
		XCTAssertEqual(app.staticTexts["duo-music-track"].label, "Slow Sunday")
		expectation(for: playing, evaluatedWith: play)
		waitForExpectations(timeout: 15)
		play.tap()
		XCTAssertEqual(play.label, "Play ambient music")
		play.tap()
		expectation(for: playing, evaluatedWith: play)
		waitForExpectations(timeout: 5)
		XCUIApplication(bundleIdentifier: "com.apple.Preferences").activate()
		XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
		app.activate()
		XCTAssertTrue(play.waitForExistence(timeout: 5))
		XCTAssertEqual(play.label, "Play ambient music")
	}
}
