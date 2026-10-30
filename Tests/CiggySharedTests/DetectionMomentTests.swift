import XCTest
@testable import CiggyShared

final class DetectionMomentTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_760_000_000)
    private func review(_ events: [SmokingEvent], ids: [UUID]? = nil) -> DetectionReview {
        DetectionReview(eventIDs: ids ?? events.map(\.id), origin: .watchHistory,
                        windowStart: base.addingTimeInterval(-3600), windowEnd: base.addingTimeInterval(3600), eventSnapshots: events)
    }
    func testEveryOriginalHasItsOwnSortedEvidenceWindow() {
        let first = SmokingEvent(timestamp: base, source: .automatic, motionSessionStartedAt: base.addingTimeInterval(-300))
        let second = SmokingEvent(timestamp: base.addingTimeInterval(600), source: .automatic, motionSessionStartedAt: base.addingTimeInterval(300))
        let result = review([second, first]).detectionMoments
        XCTAssertEqual(result.map(\.id), [first.id, second.id])
        XCTAssertEqual(result[0].startedAt, base.addingTimeInterval(-300))
        XCTAssertEqual(result[1].countedAt, base.addingTimeInterval(600))
    }
    func testMissingSnapshotsAndLegacyStartsNeverInventWindows() {
        let event = SmokingEvent(timestamp: base, source: .automatic)
        let missing = UUID()
        let moments = review([event], ids: [event.id, missing]).detectionMoments
        XCTAssertEqual(moments.count, 2)
        XCTAssertNil(moments[0].startedAt)
        XCTAssertTrue(moments[0].summary().contains("start unavailable"))
        XCTAssertNil(moments[1].countedAt)
        XCTAssertTrue(moments[1].summary().contains("unavailable"))
    }
    func testCorrectionKeepsOriginalEvidenceWithoutInventingAddedTimes() {
        let event = SmokingEvent(timestamp: base, source: .automatic, motionSessionStartedAt: base.addingTimeInterval(-300))
        var value = review([event]); value.decision = .adjusted; value.correctedCount = 3
        XCTAssertEqual(value.detectionMoments.count, 1)
        XCTAssertEqual(value.detectionMoments[0].countedAt, base)
        value.correctedCount = 0
        XCTAssertEqual(value.detectionMoments.count, 1)
    }
    func testInvalidStartDoesNotBecomeANegativeInterval() {
        let event = SmokingEvent(timestamp: base, source: .automatic, motionSessionStartedAt: base.addingTimeInterval(60))
        XCTAssertNil(review([event]).detectionMoments[0].startedAt)
    }
    func testCrossMidnightFormattingAndTimezone() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: base)
        let event = SmokingEvent(timestamp: midnight.addingTimeInterval(120), source: .automatic, motionSessionStartedAt: midnight.addingTimeInterval(-180))
        let summary = review([event]).detectionMoments[0].summary(calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(summary.contains("11:57")); XCTAssertTrue(summary.contains("12:02")); XCTAssertTrue(summary.contains("2025"))
    }
    func testReviewLinkUsesBroadPeriodAndOnlyNonsecretContext() throws {
        let event = SmokingEvent(timestamp: base, source: .automatic, heartRate: 90, notes: "Private note", motionSessionStartedAt: base.addingTimeInterval(-7200))
        let value = review([event]), participant = UUID()
        let url = value.motionDashboardURL(participantID: participant)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        XCTAssertEqual(Set(query.keys), ["from", "to", "participant", "review"])
        XCTAssertEqual(ISO8601DateFormatter().date(from: query["from"]!), event.motionSessionStartedAt)
        XCTAssertEqual(query["participant"], participant.uuidString.lowercased())
        XCTAssertFalse(url.absoluteString.contains("Private"))
    }
    func testEvidenceSurvivesCodableTransport() throws {
        let event = SmokingEvent(timestamp: base.addingTimeInterval(0.123), source: .automatic, motionSessionStartedAt: base.addingTimeInterval(-300.456))
        let value = review([event])
        let restored = try JSONDecoder().decode(DetectionReview.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored.detectionMoments, value.detectionMoments)
    }
}
