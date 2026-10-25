import Foundation

public enum LeagueSeason: String, CaseIterable, Codable, Hashable, Sendable {
    case current, previous
}

public struct LeagueMember: Codable, Equatable, Sendable {
    public let id: String
    public let alias: String
    public let joinedAt: String
}

public struct LeagueEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let alias: String
    public let score: Int
    public let rank: Int?
    public let updatedAt: String?
}

public struct LeagueBoard: Codable, Equatable, Sendable {
    public let seasonStart: String
    public let seasonEnd: String
    public let serverNow: String
    public let generatedAt: String
    public let entries: [LeagueEntry]
    public let totalParticipants: Int
    public let me: LeagueEntry?
    public let member: LeagueMember?
    public let myRevision: Int?

    public static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    /// Reject incomplete/malformed snapshots rather than replacing a usable board.
    public var isValid: Bool {
        guard let start = Self.date(seasonStart), let end = Self.date(seasonEnd),
              let serverDate = Self.date(serverNow), let generated = Self.date(generatedAt),
              abs(generated.timeIntervalSince(serverDate)) < 60,
              [LeagueWeek(containing: serverDate).start, LeagueWeek(containing: serverDate, previous: true).start].contains(start),
              end.timeIntervalSince(start) == 7 * 86400,
              totalParticipants >= 0, entries.count == min(totalParticipants, 50),
              myRevision.map({ $0 >= 1 }) ?? true,
              Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ Self.valid($0) && $0.score > 0 && $0.rank != nil }),
              zip(entries, entries.dropFirst()).allSatisfy({ $0.score >= $1.score }),
              me.map(Self.valid) ?? true else { return false }
        for (index, entry) in entries.enumerated() {
            let expectedRank = entries.firstIndex(where: { $0.score == entry.score })! + 1
            guard entry.rank == expectedRank, entry.rank! <= totalParticipants else { return false }
            if index > 0 && entries[index - 1].score < entry.score { return false }
        }
        if let me {
            if let listed = entries.first(where: { $0.id == me.id }), listed != me { return false }
            if me.score > 0 {
                guard let rank = me.rank, rank <= totalParticipants else { return false }
                if entries.count < 50 && !entries.contains(where: { $0.id == me.id }) { return false }
            }
        }
        if let member {
            guard UUID(uuidString: member.id) != nil, !member.alias.isEmpty,
                  Self.date(member.joinedAt) != nil, me?.id == member.id, me?.alias == member.alias else { return false }
        } else if me != nil { return false }
        return true
    }

    private static func valid(_ entry: LeagueEntry) -> Bool {
        UUID(uuidString: entry.id) != nil && !entry.alias.isEmpty && entry.alias.count <= 100 &&
        (0...100000).contains(entry.score) &&
        (entry.updatedAt.map { date($0) != nil } ?? (entry.score == 0)) && (entry.score == 0 ? entry.rank == nil : (entry.rank ?? 0) > 0)
    }
}

/// UTC boundaries match the server, regardless of device calendar or travel.
public struct LeagueWeek: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public var key: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }
    public init(containing date: Date, previous: Bool = false) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        start = monday.addingTimeInterval(previous ? -7 * 86400 : 0)
        end = start.addingTimeInterval(7 * 86400)
    }
    public func count(events: [SmokingEvent], through now: Date) -> Int {
        Set(events.filter { $0.timestamp >= start && $0.timestamp < end && $0.timestamp <= now }.map(\.id)).count
    }
}
