import Foundation
import XCTest
@testable import CiggyShared

final class LiveCalibrationBufferTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000.125)

    func testLiveBufferExcludesEarlierMotionDownsamplesAndFlushesWithoutWaitingForHistory() throws {
        var buffer = LiveCalibrationBuffer(enabledAt: start)
        XCTAssertNil(buffer.append(sample(at: -1)))
        for index in 0..<1_800 { XCTAssertNil(buffer.append(sample(at: Double(index) / 30))) }
        let recording = try XCTUnwrap(buffer.flush())
        XCTAssertEqual(recording.startedAt, start)
        XCTAssertEqual(recording.samples.count, 600)
        XCTAssertEqual(recording.samples.first?.timestamp, start)
        XCTAssertEqual(recording.endedAt, recording.samples.last?.timestamp)
        XCTAssertTrue(recording.samples.allSatisfy { $0.timestamp >= start && $0.rotationRate != nil })
        XCTAssertNil(buffer.flush())
    }

    func testLiveBufferPreservesGapsAndSplitsBeforeExceedingFiveMinutes() throws {
        var buffer = LiveCalibrationBuffer(enabledAt: start)
        _ = buffer.append(sample(at: 0))
        _ = buffer.append(sample(at: 100))
        let first = try XCTUnwrap(buffer.append(sample(at: 301)))
        XCTAssertEqual(first.samples.count, 2)
        XCTAssertEqual(first.endedAt, start.addingTimeInterval(100))
        let second = try XCTUnwrap(buffer.flush())
        XCTAssertEqual(second.startedAt, start.addingTimeInterval(301))
        XCTAssertNotEqual(first.id, second.id)
    }

    private func sample(at seconds: Double) -> MotionSample {
        .init(timestamp: start.addingTimeInterval(seconds), gravity: .init(x: 0, y: 0, z: -1),
              userAcceleration: .init(x: 0.1, y: 0, z: 0), rotationRate: .init(x: 0, y: 0.4, z: 0))
    }
}
