import Foundation

/// Original motion evidence only; a count correction never invents timestamps.
public struct DetectionMoment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date?
    public let countedAt: Date?

    public func summary(calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) -> String {
        guard let countedAt else { return "Timing unavailable for this estimate" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.timeStyle = .short
        guard let startedAt else { return "Counted at \(formatter.string(from: countedAt)) · start unavailable" }
        if !calendar.isDate(startedAt, inSameDayAs: countedAt) { formatter.dateStyle = .medium }
        return "\(formatter.string(from: startedAt)) – \(formatter.string(from: countedAt))"
    }
}

public extension DetectionReview {
    var detectionMoments: [DetectionMoment] {
        let snapshots = Dictionary(eventSnapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return eventIDs.map { id in
            let event = snapshots[id]
            let end = event?.timestamp
            let validEnd = end.flatMap { MotionHistoryProcessor.isSupportedDate($0) ? $0 : nil }
            let start = event?.motionSessionStartedAt.flatMap { date in
                validEnd.map { date <= $0 && MotionHistoryProcessor.isSupportedDate(date) } == true ? date : nil
            }
            return DetectionMoment(id: id, startedAt: start, countedAt: validEnd)
        }.sorted {
            if $0.countedAt != $1.countedAt { return ($0.countedAt ?? .distantFuture) < ($1.countedAt ?? .distantFuture) }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func reviewPeriodSummary(calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let start = formatter.string(from: windowStart)
        if calendar.isDate(windowStart, inSameDayAs: windowEnd) { formatter.dateStyle = .none }
        return "Review period: \(start) – \(formatter.string(from: windowEnd))"
    }

    /// The dashboard receives only review scope, never credentials or HealthKit data.
    func motionDashboardURL(participantID: UUID? = nil) -> URL {
        var url = URLComponents(string: "https://ciggy.thatcanadian.dev/")!
        let formatter = ISO8601DateFormatter()
        let start = min(windowStart, detectionMoments.compactMap(\.startedAt).min() ?? windowStart)
        let end = max(windowEnd, start.addingTimeInterval(60))
        url.queryItems = [
            .init(name: "from", value: formatter.string(from: start)),
            .init(name: "to", value: formatter.string(from: end)),
            .init(name: "review", value: id.uuidString.lowercased())
        ]
        if let participantID { url.queryItems?.append(.init(name: "participant", value: participantID.uuidString.lowercased())) }
        return url.url!
    }
}
