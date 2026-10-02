//
//  ciggy_Watch_AppUITests.swift
//  ciggy Watch AppUITests
//
//  Created by Ali Khairreddin on 2026-07-14.
//

import XCTest

final class ciggy_Watch_AppUITests: XCTestCase {

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
    func testWatchAppearancePersists() throws {
        let app = XCUIApplication()
        app.launch()
        let settings = app.buttons["watch-settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let picker = app.descendants(matching: .any)["appearance-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let dark = app.buttons["Dark"].firstMatch
        XCTAssertTrue(dark.waitForExistence(timeout: 3))
        dark.tap()
        if !picker.exists { app.navigationBars.buttons.firstMatch.tap() }
        let darkShot = XCTAttachment(screenshot: app.screenshot())
        darkShot.name = "Dark Watch settings"
        darkShot.lifetime = .keepAlways
        add(darkShot)

        app.terminate()
        app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Dark") || (picker.value as? String)?.contains("Dark") == true || app.staticTexts["Dark"].exists)
        picker.tap()
        let cream = app.buttons["Cream"].firstMatch
        XCTAssertTrue(cream.waitForExistence(timeout: 3))
        cream.tap()
        if !picker.exists { app.navigationBars.buttons.firstMatch.tap() }
        let creamShot = XCTAttachment(screenshot: app.screenshot())
        creamShot.name = "Cream Watch settings"
        creamShot.lifetime = .keepAlways
        add(creamShot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
