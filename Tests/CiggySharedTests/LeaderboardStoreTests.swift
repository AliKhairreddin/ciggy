import XCTest
@testable import CiggyShared

@MainActor
final class LeaderboardStoreTests: XCTestCase {
    func testAnonymousBrowsingNeverPublishesHistoryUntilExplicitJoin() async throws {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.repository(count: 2)
        let store = fixture.store()
        store.bind(repository: repository)
        await store.load()
        await store.synchronize()
        XCTAssertNil(fixture.credentialData)
        XCTAssertTrue(fixture.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertEqual(store.localWeeklyCount, 2)

        await store.join()
        XCTAssertTrue(store.isMember)
        let submitted = try fixture.submissions()
        XCTAssertEqual(submitted.first(where: { $0.seasonStart == fixture.currentKey })?.count, 2)
        XCTAssertEqual(submitted.first(where: { $0.seasonStart == fixture.previousKey })?.count, 0)
        for request in fixture.scoreRequests {
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(Set(payload.keys), ["seasonStart", "count", "revision"])
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testCorrectionReplacesPublishedTotalUsingHigherRevision() async throws {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.repository(count: 3)
        let store = fixture.store()
        store.bind(repository: repository)
        await store.join()
        let first = try XCTUnwrap(fixture.submissions().first { $0.seasonStart == fixture.currentKey })
        XCTAssertEqual(first.count, 3)

        XCTAssertTrue(repository.removeEvent(id: try XCTUnwrap(repository.events.first).id))
        fixture.instant = fixture.instant.addingTimeInterval(61)
        await store.synchronize()
        let corrected = try XCTUnwrap(fixture.submissions().last { $0.seasonStart == fixture.currentKey })
        XCTAssertEqual(corrected.count, 2)
        XCTAssertGreaterThan(corrected.revision, first.revision)
        XCTAssertEqual(store.board?.me?.score, 2)

        let requestCount = fixture.scoreRequests.count
        fixture.instant = fixture.instant.addingTimeInterval(61)
        await store.synchronize()
        XCTAssertEqual(fixture.scoreRequests.count, requestCount, "Unchanged aggregates should reuse the acknowledged total")
    }

    func testLostScoreResponseRetainsExactIntentAcrossRestart() async throws {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.repository(count: 4)
        let store = fixture.store()
        store.bind(repository: repository)
        fixture.loseNextScoreResponse = true
        await store.join()
        let sent = try XCTUnwrap(fixture.scoreRequests.first)
        let persisted = try JSONDecoder().decode(LeagueCredential.self, from: XCTUnwrap(fixture.credentialData))
        XCTAssertEqual(persisted.pendingScores.first?.count, 4)
        XCTAssertNotNil(store.errorMessage)

        let restarted = fixture.store()
        restarted.bind(repository: repository)
        await restarted.load()
        let repeated = try XCTUnwrap(fixture.scoreRequests.dropFirst().first)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(sent.httpBody)) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: XCTUnwrap(repeated.httpBody)) as? NSDictionary)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), repeated.value(forHTTPHeaderField: "Authorization"))
        let acknowledged = try JSONDecoder().decode(LeagueCredential.self, from: XCTUnwrap(fixture.credentialData))
        XCTAssertTrue(acknowledged.pendingScores.isEmpty)
        XCTAssertEqual(acknowledged.acknowledged[fixture.currentKey], 4)
    }

    func testInvalidRefreshKeepsValidCachedBoardAcrossRestart() async throws {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        fixture.addPublicEntrant(score: 12)
        let store = fixture.store()
        await store.load()
        let initial = try XCTUnwrap(store.board)
        await store.load()
        XCTAssertEqual(fixture.requests.count, 1, "Ordinary reload should reuse the one-minute snapshot")

        fixture.instant = fixture.instant.addingTimeInterval(61)
        fixture.returnPartialBoard = true
        await store.load()
        XCTAssertEqual(store.board, initial)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(fixture.store().board, initial)
    }

    func testFailedLocalRepositoryNeverPublishesAMisleadingZero() async throws {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        fixture.seedMembership(score: 9)
        // A failing snapshot read leaves persistence in recovery rather than an empty valid history.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let badSnapshot = directory.appendingPathComponent("history.json")
        try Data("not JSON".utf8).write(to: badSnapshot)
        let repository = EventRepository(userDefaults: fixture.defaults, storageKey: "broken", snapshotURL: badSnapshot)
        XCTAssertNotNil(repository.lastPersistenceError)
        let store = fixture.store()
        store.bind(repository: repository)
        await store.load()
        await store.synchronize()
        XCTAssertNil(store.localWeeklyCount)
        XCTAssertTrue(fixture.scoreRequests.isEmpty)
        XCTAssertEqual(store.board?.me?.score, 9)
        XCTAssertNotNil(store.scoreSyncMessage)
    }

    func testMissingRepositoryCannotOverwritePublishedCount() async {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        fixture.seedMembership(score: 8)
        let store = fixture.store()
        await store.load()
        await store.synchronize()
        XCTAssertEqual(store.board?.me?.score, 8)
        XCTAssertNil(store.localWeeklyCount)
        XCTAssertTrue(fixture.scoreRequests.isEmpty)
    }

    func testKeychainSurvivingReinstallCannotPublishNewEmptyHistory() async {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        fixture.seedMembership(score: 8)
        fixture.defaults.removeObject(forKey: "Ciggy.league.installation.v1")
        let repository = fixture.repository(count: 0)
        let store = fixture.store()
        store.bind(repository: repository)
        await store.load()
        await store.synchronize()
        XCTAssertEqual(store.board?.me?.score, 8)
        XCTAssertTrue(fixture.scoreRequests.isEmpty)
        XCTAssertTrue(store.scoreSyncMessage?.contains("earlier installation") == true)
    }

    func testMondayRolloverDoesNotReuseLastWeeksFreshCache() async throws {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        fixture.instant = ISO8601DateFormatter().date(from: "2026-10-25T23:59:50Z")!
        let store = fixture.store()
        await store.load()
        let oldStart = try XCTUnwrap(store.board?.seasonStart)
        fixture.instant = fixture.instant.addingTimeInterval(20)
        await store.load()
        XCTAssertEqual(fixture.requests.count, 2, "Week boundaries invalidate even a recently fetched snapshot")
        XCTAssertNotEqual(store.board?.seasonStart, oldStart)
        XCTAssertEqual(LeagueBoard.date(try XCTUnwrap(store.board?.seasonStart)),
                       LeagueWeek(containing: fixture.instant).start)
    }

    func testPendingDeletionSurvivesRestartAndBlocksRejoining() async throws {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        fixture.seedMembership(score: 6)
        fixture.failDeletion = true
        let store = fixture.store()
        await store.leave()
        XCTAssertTrue(store.pendingDeletion)
        XCTAssertTrue(try JSONDecoder().decode(LeagueCredential.self, from: XCTUnwrap(fixture.credentialData)).pendingDeletion)

        let restarted = fixture.store()
        let beforeJoin = fixture.requests.count
        await restarted.join()
        XCTAssertEqual(fixture.requests.count, beforeJoin)
        XCTAssertTrue(restarted.pendingDeletion)
        XCTAssertFalse(restarted.canSync)
        await restarted.load()
        XCTAssertEqual(fixture.requests.last?.httpMethod, "DELETE")

        fixture.failDeletion = false
        await restarted.leave()
        XCTAssertFalse(restarted.pendingDeletion)
        XCTAssertFalse(restarted.isMember)
        XCTAssertNil(fixture.credentialData)
    }

    func testRetryAfterPersistsAndPreventsNetworkRequestsUntilAllowed() async {
        let fixture = LeagueFixture()
        defer { fixture.cleanUp() }
        fixture.limitNextRequest = true
        let store = fixture.store()
        await store.load()
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertNotNil(store.errorMessage)
        let restarted = fixture.store()
        fixture.instant = fixture.instant.addingTimeInterval(119)
        await restarted.load()
        XCTAssertEqual(fixture.requests.count, 1)
        fixture.instant = fixture.instant.addingTimeInterval(2)
        await restarted.load()
        XCTAssertEqual(fixture.requests.count, 2)
        XCTAssertNotNil(restarted.board)
        XCTAssertNil(restarted.errorMessage)
    }
}

/// A deterministic synthetic service. No account, real history, or network access.
@MainActor
private final class LeagueFixture {
    let suite = "LeaderboardStoreTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    var instant = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
    var credentialData: Data?
    var requests: [URLRequest] = []
    var loseNextScoreResponse = false
    var returnPartialBoard = false
    var failDeletion = false
    var limitNextRequest = false
    private var member: LeagueMember?
    private var scores: [String: (count: Int, revision: Int)] = [:]
    private var entrant: LeagueEntry?

    var currentKey: String { LeagueWeek(containing: instant).key }
    var previousKey: String { LeagueWeek(containing: instant, previous: true).key }
    var scoreRequests: [URLRequest] { requests.filter { $0.url?.lastPathComponent == "score" } }

    init() { defaults = UserDefaults(suiteName: suite)! }
    func cleanUp() { defaults.removePersistentDomain(forName: suite) }

    func store() -> LeaderboardStore {
        LeaderboardStore(defaults: defaults, now: { self.instant },
                         readCredential: { self.credentialData },
                         writeCredential: { self.credentialData = $0 },
                         transport: { try await self.respond($0) })
    }

    func repository(count: Int) -> EventRepository {
        let repository = EventRepository(userDefaults: defaults, storageKey: "history")
        for offset in 0..<count {
            XCTAssertTrue(repository.addEvent(.init(timestamp: instant.addingTimeInterval(-Double(offset + 1) * 600),
                                                     source: .manual, notes: "Synthetic private note")))
        }
        return repository
    }

    func seedMembership(score: Int) {
        let id = UUID().uuidString.lowercased()
        member = LeagueMember(id: id, alias: "Synthetic Ash Clerk", joinedAt: iso(instant.addingTimeInterval(-86400)))
        defaults.set("synthetic-installation", forKey: "Ciggy.league.installation.v1")
        credentialData = try! JSONEncoder().encode(LeagueCredential(memberID: id, token: String(repeating: "a", count: 43), member: member,
                                                                   installationID: "synthetic-installation"))
        scores[currentKey] = (score, 1)
    }

    func addPublicEntrant(score: Int) {
        entrant = LeagueEntry(id: UUID().uuidString.lowercased(), alias: "Synthetic Paper Captain",
                             score: score, rank: 1, updatedAt: iso(instant))
    }

    func submissions() throws -> [LeagueScoreSubmission] {
        try scoreRequests.map { try JSONDecoder().decode(LeagueScoreSubmission.self, from: XCTUnwrap($0.httpBody)) }
    }

    private func respond(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if limitNextRequest {
            limitNextRequest = false
            return response(request, data: Data("{}".utf8), status: 429, headers: ["Retry-After": "120"])
        }
        switch (request.httpMethod, request.url?.lastPathComponent) {
        case ("POST", "join"):
            let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
            member = LeagueMember(id: try XCTUnwrap(body["memberID"]), alias: "Synthetic Ash Clerk", joinedAt: iso(instant))
            return response(request, data: try JSONEncoder().encode(member), status: 201)
        case ("PUT", "score"):
            let submission = try JSONDecoder().decode(LeagueScoreSubmission.self, from: XCTUnwrap(request.httpBody))
            scores[submission.seasonStart] = (submission.count, submission.revision)
            if loseNextScoreResponse {
                loseNextScoreResponse = false
                throw URLError(.networkConnectionLost)
            }
            let body: [String: Any] = ["accepted": true, "seasonStart": submission.seasonStart,
                                       "count": submission.count, "revision": submission.revision]
            return response(request, data: try JSONSerialization.data(withJSONObject: body))
        case ("DELETE", "membership"):
            if failDeletion { throw URLError(.notConnectedToInternet) }
            member = nil; scores = [:]
            return response(request, data: Data("{\"deleted\":true}".utf8))
        default:
            let previous = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "season" })?.value == "previous"
            let week = LeagueWeek(containing: instant, previous: previous)
            let score = scores[week.key]?.count ?? 0
            let me = member.map { LeagueEntry(id: $0.id, alias: $0.alias, score: score,
                                              rank: score > 0 ? 1 : nil, updatedAt: score > 0 ? iso(instant) : nil) }
            let entries = [me?.score ?? 0 > 0 ? me : nil, entrant].compactMap { $0 }.sorted { $0.score > $1.score }
            let board = LeagueBoard(seasonStart: iso(week.start), seasonEnd: iso(week.end),
                                   serverNow: iso(instant), generatedAt: iso(instant), entries: entries,
                                   totalParticipants: entries.count + (returnPartialBoard ? 1 : 0), me: me, member: member,
                                   myRevision: scores[week.key]?.revision)
            return response(request, data: try JSONEncoder().encode(board))
        }
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func response(_ request: URLRequest, data: Data, status: Int = 200,
                          headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
    }
}
