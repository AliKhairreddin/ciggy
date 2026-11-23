import Foundation
import XCTest
import CiggyShared

@MainActor
final class WatchRefreshScheduleModelTests: XCTestCase {
    private enum Step {
        case advance(TimeInterval)
        case wake(WatchRefreshSchedule.Wake)
    }

    func testSingleSystemSlotAcrossFourClockAndLifecycleSteps() throws {
        let suite = "WatchRefreshModel-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSinceReferenceDate: 100_000_000)

        func replay(_ steps: [Step]) throws {
            defaults.removePersistentDomain(forName: suite)
            let schedule = WatchRefreshSchedule(defaults: defaults)
            var now = start
            var foreground = false
            var slot = schedule.appointment(for: .check, at: start, canSchedule: true)
            guard slot == start.addingTimeInterval(900) else { throw Violation("Missing initial 15-minute request", []) }

            for (index, step) in steps.enumerated() {
                if case .advance(let seconds) = step {
                    let target = now.addingTimeInterval(seconds)
                    if foreground, let due = slot, now <= due, due <= target { slot = nil }
                    now = target
                    continue
                }
                guard case .wake(let wake) = step else { continue }
                switch wake {
                case .foregroundEntered:
                    foreground = true
                    if slot == now { slot = nil }
                case .foregroundEnded:
                    foreground = false
                case .check:
                    break
                case .backgroundGrant:
                    guard !foreground, let due = slot, due <= now else { return }
                    slot = nil
                }

                let requested = schedule.appointment(for: wake, at: now, canSchedule: true)
                let trace = Array(steps.prefix(index + 1))
                if let requested {
                    if let due = slot, now.timeIntervalSince(due) <= 7_200 {
                        throw Violation("Replaced a pending system appointment within its grace period", trace)
                    }
                    guard requested == now.addingTimeInterval(900) else { throw Violation("Wrong preferred date", trace) }
                    slot = requested
                } else if let due = slot {
                    guard now.timeIntervalSince(due) <= 7_200 else { throw Violation("Overdue appointment never retried", trace) }
                } else if !foreground {
                    throw Violation("No pending appointment after background entry or grant", trace)
                }
            }
        }

        func explore(_ prefix: [Step]) throws {
            if prefix.count == 4 { return try replay(prefix) }
            let steps: [Step] = [.wake(.foregroundEntered), .wake(.foregroundEnded), .wake(.check),
                                 .wake(.backgroundGrant), .advance(60), .advance(900), .advance(7_200), .advance(7_201)]
            for step in steps { try explore(prefix + [step]) }
        }
        try explore([])
    }

    func testLegacyAppointmentRestartAndDelayedRejection() throws {
        let suite = "WatchRefreshUpgrade-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSinceReferenceDate: 100_000_000)
        let legacy = start.addingTimeInterval(1_800)
        defaults.set(legacy, forKey: "BackgroundMotionMonitor.scheduledRefresh.v1")
        let schedule = WatchRefreshSchedule(defaults: defaults)
        let earlier = try XCTUnwrap(schedule.appointment(for: .check, at: start, canSchedule: true))
        XCTAssertEqual(earlier, start.addingTimeInterval(900))

        let restored = WatchRefreshSchedule(defaults: defaults)
        restored.rejected(legacy)
        XCTAssertNil(restored.appointment(for: .check, at: start, canSchedule: true))
        restored.rejected(earlier)
        XCTAssertNil(restored.appointment(for: .check, at: start, canSchedule: false))
        XCTAssertEqual(restored.appointment(for: .check, at: start, canSchedule: true), earlier)
    }

    func testInvalidOrReversedForegroundClockPreservesAppointment() throws {
        let suite = "WatchRefreshClock-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSinceReferenceDate: 100_000_000)
        for ended in [Date(timeIntervalSinceReferenceDate: .nan), date.addingTimeInterval(-60)] {
            let schedule = WatchRefreshSchedule(defaults: defaults)
            _ = schedule.appointment(for: .foregroundEntered, at: date, canSchedule: true)
            XCTAssertNil(schedule.appointment(for: .foregroundEnded, at: ended, canSchedule: false))
            XCTAssertNil(schedule.appointment(for: .check, at: date, canSchedule: true))
        }
    }

    private struct Violation: Error, CustomStringConvertible {
        let description: String
        init(_ reason: String, _ trace: [Step]) {
            description = reason + " after " + trace.map { String(describing: $0) }.joined(separator: " → ")
        }
    }
}
