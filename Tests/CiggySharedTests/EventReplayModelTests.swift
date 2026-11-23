import Foundation
import XCTest
import CiggyShared

@MainActor
final class EventReplayModelTests: XCTestCase {
    private enum Estimate: String {
        case first, replay, next
    }

    private enum Delivery: Hashable, CustomStringConvertible {
        case estimate(Estimate), delete(Estimate), restart

        var description: String {
            switch self {
            case .estimate(let estimate): return estimate.rawValue
            case .delete(let estimate): return "delete " + estimate.rawValue
            case .restart: return "restart"
            }
        }
    }

    func testEveryDeliveryOrderPreservesDistinctEstimatesAndExplicitDeletion() throws {
        let start = Date(timeIntervalSinceReferenceDate: 100_000_000)
        func estimate(_ offset: TimeInterval) -> SmokingEvent {
            SmokingEvent(timestamp: start.addingTimeInterval(offset + 300), source: .automatic,
                         motionSessionStartedAt: start.addingTimeInterval(offset))
        }
        let first = estimate(0), replay = estimate(30), next = estimate(300)
        let estimates: [Estimate: SmokingEvent] = [.first: first, .replay: replay, .next: next]
        let firstIDs: Set<UUID> = [first.id, replay.id]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "EventReplayModel-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for deleted in [Estimate.replay, .first] {
            let deliveries: [Delivery] = [.estimate(.first), .estimate(.replay), .delete(deleted), .estimate(.next), .restart]
            for repeated in [Delivery.estimate(.replay), .delete(deleted)] {
                try permute(deliveries + [repeated]) { schedule in
                    let url = directory.appendingPathComponent("events.json")
                    let makeRepository = { EventRepository(userDefaults: defaults, snapshotURL: url) }
                    var repository = makeRepository()
                    var observed = Set<Estimate>()
                    var deletions = Set<Estimate>()
                    for (index, delivery) in schedule.enumerated() {
                        switch delivery {
                        case .estimate(let item):
                            let event = try XCTUnwrap(estimates[item])
                            guard repository.receiveEvent(event) else {
                                throw Violation("Event receipt failed", schedule, index)
                            }
                            observed.insert(item)
                        case .delete(let item):
                            let event = try XCTUnwrap(estimates[item])
                            guard repository.receiveDeletion(id: event.id) else {
                                throw Violation("Deletion receipt failed", schedule, index)
                            }
                            deletions.insert(item)
                        case .restart:
                            repository = makeRepository()
                        }
                        let firstSeen = observed.contains(.first) || observed.contains(.replay)
                        let expectedFirst = firstSeen && observed.isDisjoint(with: deletions) ? 1 : 0
                        let firstCount = repository.events.filter { firstIDs.contains($0.id) }.count
                        let expectedNext = observed.contains(.next) ? 1 : 0
                        let nextCount = repository.events.filter { $0.id == next.id }.count
                        guard firstCount == expectedFirst, nextCount == expectedNext,
                              repository.events.count == firstCount + nextCount else {
                            throw Violation("Expected first/next counts \(expectedFirst)/\(expectedNext), got \(firstCount)/\(nextCount)", schedule, index)
                        }
                    }
                    try FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private func permute(_ remaining: [Delivery], prefix: [Delivery] = [],
                         check: ([Delivery]) throws -> Void) rethrows {
        guard !remaining.isEmpty else { return try check(prefix) }
        var tried = Set<Delivery>()
        for (index, delivery) in remaining.enumerated() where tried.insert(delivery).inserted {
            var rest = remaining
            rest.remove(at: index)
            try permute(rest, prefix: prefix + [delivery], check: check)
        }
    }

    private struct Violation: Error, CustomStringConvertible {
        let description: String

        init(_ reason: String, _ schedule: [Delivery], _ index: Int) {
            description = reason + " after " + schedule.prefix(index + 1).map(\.description).joined(separator: " → ")
        }
    }
}
