import XCTest
@testable import CiggyShared

final class CiggyAmbientLoopTests: XCTestCase {
	func testEveryTrackProducesPlayableQuietPCMWithCleanLoopBoundaries() {
		for track in CiggyAmbientLoop.Track.allCases {
			let data = CiggyAmbientLoop.waveData(for: track)
			XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
			XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
			XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
			XCTAssertEqual(data.count, 44 + 22_050 * 24 * 2)
			var peak = 0
			for offset in stride(from: 44, to: data.count, by: 2) {
				let bits = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
				peak = max(peak, abs(Int(Int16(bitPattern: bits))))
			}
			XCTAssertGreaterThan(peak, 1_000, "The track must contain actual music")
			XCTAssertLessThan(peak, 16_000, "Keep the original loops quiet and unclipped")
			XCTAssertEqual(Array(data[44..<64]), Array(repeating: 0, count: 20))
			XCTAssertEqual(Array(data.suffix(20)), Array(repeating: 0, count: 20))
		}
	}

	func testTracksHaveDistinctAudio() {
		XCTAssertNotEqual(CiggyAmbientLoop.waveData(for: .blueHour), CiggyAmbientLoop.waveData(for: .slowSunday))
	}
}
