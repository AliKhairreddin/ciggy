import SwiftUI
import XCTest
@testable import CiggyShared

final class CiggyAppearanceTests: XCTestCase {
	func testDefaultIsCreamEvenWhenTheDeviceUsesDarkAppearance() {
		XCTAssertEqual(CiggyAppearance.defaultValue.resolvedColorScheme(systemScheme: .dark), .light)
	}

	func testExplicitDarkAppearanceOverridesALightDevice() {
		XCTAssertEqual(CiggyAppearance.dark.resolvedColorScheme(systemScheme: .light), .dark)
	}

	func testFollowSystemRespondsToBothDeviceAppearances() {
		XCTAssertNil(CiggyAppearance.system.preferredColorScheme)
		XCTAssertEqual(CiggyAppearance.system.resolvedColorScheme(systemScheme: .light), .light)
		XCTAssertEqual(CiggyAppearance.system.resolvedColorScheme(systemScheme: .dark), .dark)
	}
}
