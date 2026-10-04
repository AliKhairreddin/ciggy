import XCTest
@testable import CiggyShared

final class CiggyLayoutPlanTests: XCTestCase {
	func testCoverAndSplitViewStayCompact() {
		for size in [CGSize(width: 393, height: 852), CGSize(width: 430, height: 626)] {
			let plan = CiggyLayoutPlan(size: size, regularWidth: false)
			XCTAssertEqual(plan.mode, .single)
			XCTAssertEqual(plan.overview.size, size)
			XCTAssertNil(plan.controls)
		}
	}

	func testOpenPortraitAndLandscapeUseBothColumns() throws {
		for size in [CGSize(width: 626, height: 890), CGSize(width: 890, height: 626)] {
			let plan = CiggyLayoutPlan(size: size, regularWidth: true)
			XCTAssertEqual(plan.mode, .columns)
			let controls = try XCTUnwrap(plan.controls)
			XCTAssertEqual(plan.overview.width, controls.width)
			XCTAssertEqual(controls.minX - plan.overview.maxX, 18)
			XCTAssertEqual(controls.maxX, size.width)
		}
		XCTAssertEqual(CiggyLayoutPlan(size: CGSize(width: 852, height: 393), regularWidth: false).mode, .columns)
	}

	func testTabletopUsesActualOffCenterHingeAndMargins() throws {
		let fold = CGRect(x: 0, y: 370, width: 626, height: 32)
		let plan = CiggyLayoutPlan(size: CGSize(width: 626, height: 820), regularWidth: true, division: fold)
		XCTAssertEqual(plan.mode, .tabletop)
		let controls = try XCTUnwrap(plan.controls)
		XCTAssertEqual(plan.overview.maxY, fold.minY)
		XCTAssertEqual(controls.minY, fold.maxY)
		XCTAssertEqual(controls.maxY, 820)
		XCTAssertFalse(plan.overview.intersects(fold))
		XCTAssertFalse(controls.intersects(fold))
	}

	func testBookKeepsControlsOnTrailingSideAndMirrorsReadingOrder() throws {
		let size = CGSize(width: 890, height: 626)
		let fold = CGRect(x: 410, y: 0, width: 36, height: 626)
		let leftToRight = CiggyLayoutPlan(size: size, regularWidth: true, division: fold)
		let rightToLeft = CiggyLayoutPlan(size: size, regularWidth: true, division: fold, rightToLeft: true)
		XCTAssertEqual(leftToRight.mode, .book)
		XCTAssertEqual(leftToRight.overview.maxX, fold.minX)
		XCTAssertEqual(try XCTUnwrap(leftToRight.controls).minX, fold.maxX)
		XCTAssertEqual(rightToLeft.overview, leftToRight.controls)
		XCTAssertEqual(rightToLeft.controls, leftToRight.overview)
	}

	func testAccessibilityStacksOpenContentButStillRespectsPhysicalFold() {
		let size = CGSize(width: 626, height: 890)
		XCTAssertEqual(CiggyLayoutPlan(size: size, regularWidth: true, accessibilitySize: true).mode, .single)
		let plan = CiggyLayoutPlan(size: size, regularWidth: true, accessibilitySize: true,
			division: CGRect(x: 0, y: 420, width: 626, height: 30))
		XCTAssertEqual(plan.mode, .tabletop)
	}

	func testFlatAndOutsideDivisionsDoNotSplitContent() {
		let size = CGSize(width: 626, height: 890)
		for fold in [
			CGRect(x: 313, y: 0, width: 0, height: 890),
			CGRect(x: 0, y: 950, width: 626, height: 20)
		] {
			XCTAssertEqual(CiggyLayoutPlan(size: size, regularWidth: true, division: fold).mode, .columns)
		}
	}

	func testHingeAtWindowEdgeUsesRemainingSpace() {
		for fold in [
			CGRect(x: -5, y: 0, width: 25, height: 890),
			CGRect(x: 606, y: 0, width: 25, height: 890),
			CGRect(x: 0, y: -5, width: 626, height: 25),
			CGRect(x: 0, y: 870, width: 626, height: 25)
		] {
			let plan = CiggyLayoutPlan(size: CGSize(width: 626, height: 890), regularWidth: true, division: fold)
			XCTAssertEqual(plan.mode, .single)
			XCTAssertNil(plan.controls)
			XCTAssertGreaterThan(plan.overview.width, 0)
			XCTAssertGreaterThan(plan.overview.height, 0)
			XCTAssertFalse(plan.overview.intersects(fold))
		}
	}
}
