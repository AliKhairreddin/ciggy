import Foundation
import Combine
import Security

/// League credentials never travel to Watch, widgets, calibration, or UserDefaults.
struct LeagueCredential: Codable {
    var memberID: String
    var token: String
    var member: LeagueMember?
    var pendingDeletion = false
    var installationID: String?
    var revision: Int = 0
    var pendingScores: [LeagueScoreSubmission] = []
    var acknowledged: [String: Int] = [:]
}

struct LeagueScoreSubmission: Codable {
    let seasonStart: String
    let count: Int
    let revision: Int
}

enum LeagueKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "dev.thatcanadian.ciggy.league",
         kSecAttrAccount as String: "membership"]
    }

    static func load() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw LeagueFailure.secureStorage }
        return data
    }

    static func save(_ data: Data?) throws {
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw LeagueFailure.secureStorage }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw LeagueFailure.secureStorage
            }
        } else if status != errSecSuccess { throw LeagueFailure.secureStorage }
    }
}

private enum LeagueFailure: LocalizedError {
    case secureStorage, invalidResponse, message(String)
    var errorDescription: String? {
        switch self {
        case .secureStorage: return "Ciggy couldn't access your secure league membership. Unlock your device and try again."
        case .invalidResponse: return "The league returned an incomplete response. Your last saved standings are still here."
        case .message(let message): return message
        }
    }
}

/// Fetch on opening the league, reuse saved standings for one minute, and keep
/// failures visibly separate from an empty season. Only weekly aggregates leave the device.
@MainActor
public final class LeaderboardStore: ObservableObject {
    @Published public private(set) var board: LeagueBoard?
    @Published public private(set) var member: LeagueMember?
    @Published public var season: LeagueSeason = .current {
        didSet { if season != oldValue { board = savedBoard(for: season); updateLocalCount() } }
    }
    @Published public private(set) var isLoading = false
    @Published public private(set) var isWorking = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var pendingDeletion = false
    public var isMember: Bool { member != nil }
    @Published public private(set) var localWeeklyCount: Int?
    @Published public private(set) var scoreSyncMessage: String?
    public var canSync: Bool { isMember && !pendingDeletion && !isWorking && !isLoading && !storageFailed }
    private weak var repository: EventRepository?
    private var subscriptions = Set<AnyCancellable>()
    private var autoSyncTask: Task<Void, Never>?
    private var lastSyncAttempt: Date?
    private var needsSync = false
    private var latestServerTime: Date?
    private var serverTimeReceivedAt: Date?
    private var effectiveNow: Date {
        guard let latestServerTime, let serverTimeReceivedAt else { return now() }
        return latestServerTime.addingTimeInterval(max(0, now().timeIntervalSince(serverTimeReceivedAt)))
    }

    public func bind(repository: EventRepository) {
        guard self.repository !== repository else { return }
        self.repository = repository
        updateLocalCount()
        repository.$events.combineLatest(repository.$lastPersistenceError)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateLocalCount()
                self?.scheduleSync()
            }.store(in: &subscriptions)
    }

    private func updateLocalCount() {
        guard let repository, repository.lastPersistenceError == nil else {
            localWeeklyCount = nil
            scoreSyncMessage = "Your local count is unavailable. Your published count is unchanged."
            return
        }
        localWeeklyCount = LeagueWeek(containing: effectiveNow, previous: season == .previous)
            .count(events: repository.events, through: effectiveNow)
    }

    private func scheduleSync() {
        guard isMember, !pendingDeletion else { return }
        if isWorking || isLoading { needsSync = true; return }
        guard autoSyncTask == nil else { return }
        let delay = max(0, 60 - now().timeIntervalSince(lastSyncAttempt ?? .distantPast))
        autoSyncTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, let self else { return }
            self.autoSyncTask = nil
            await self.synchronize()
        }
    }

    private func savedBoard(for season: LeagueSeason) -> LeagueBoard? {
        guard let saved = cache[season.rawValue]?.board,
              LeagueBoard.date(saved.seasonStart) == LeagueWeek(containing: effectiveNow, previous: season == .previous).start else { return nil }
        return saved
    }

    private struct SavedBoard: Codable { let board: LeagueBoard; let receivedAt: Date }
    private var cache: [String: SavedBoard] = [:]
    private var credential: LeagueCredential?
    private var storageFailed = false
    private var retryAt: Date?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let readCredential: () throws -> Data?
    private let writeCredential: (Data?) throws -> Void
    private let transport: (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let endpoint: URL
    private let cacheKey = "Ciggy.league.standings.v1"
    private let retryKey = "Ciggy.league.retryAt.v1"
    private let installationKey = "Ciggy.league.installation.v1"

    public convenience init() {
        self.init(defaults: .standard, now: Date.init, readCredential: LeagueKeychain.load,
                  writeCredential: LeagueKeychain.save, transport: { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw LeagueFailure.invalidResponse }
            return (data, response)
        })
    }

    init(defaults: UserDefaults, now: @escaping () -> Date,
         readCredential: @escaping () throws -> Data?, writeCredential: @escaping (Data?) throws -> Void,
         transport: @escaping (URLRequest) async throws -> (Data, HTTPURLResponse),
         endpoint: URL = URL(string: "https://ciggy.thatcanadian.dev/api/league")!) {
        self.defaults = defaults; self.now = now
        self.readCredential = readCredential; self.writeCredential = writeCredential
        self.transport = transport; self.endpoint = endpoint
        if let data = defaults.data(forKey: cacheKey),
           let saved = try? JSONDecoder().decode([String: SavedBoard].self, from: data) {
            cache = saved.filter { $0.value.board.isValid && now().timeIntervalSince($0.value.receivedAt) < 14 * 86400 }
        }
        retryAt = defaults.object(forKey: retryKey) as? Date
        recoverCredential()
        // Never show another/revoked membership's cached personal row.
        cache = cache.filter { $0.value.board.member?.id == member?.id }
        board = savedBoard(for: season)
    }

    public func load() async {
        guard !isWorking else { return }
        if storageFailed { recoverCredential(); if storageFailed { return } }
        if pendingDeletion { await leave(); return }
        await fetchBoard()
        if isMember { await synchronize() }
    }

    public func join() async {
        guard !isWorking, !isLoading, !pendingDeletion else { return }
        if storageFailed { recoverCredential(); if storageFailed { return } }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            try checkBackoff()
            if credential == nil {
                var bytes = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LeagueFailure.secureStorage }
                let token = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                let installationID = UUID().uuidString
                defaults.set(installationID, forKey: installationKey)
                try persist(LeagueCredential(memberID: UUID().uuidString.lowercased(), token: token, installationID: installationID))
            }
            guard var next = credential else { throw LeagueFailure.secureStorage }
            let data = try await request(path: "join", method: "POST", body: ["memberID": next.memberID])
            let joined = try JSONDecoder().decode(LeagueMember.self, from: data)
            guard joined.id == next.memberID, !joined.alias.isEmpty, LeagueBoard.date(joined.joinedAt) != nil else { throw LeagueFailure.invalidResponse }
            next.member = joined
            try persist(next)
            member = joined
            clearCache()
            await fetchBoard(force: true)
            isWorking = false
            await synchronize()
        } catch { report(error) }
    }

    public func synchronize() async {
        guard canSync, var next = credential else { return }
        guard let repository, repository.lastPersistenceError == nil else {
            updateLocalCount(); return
        }
        guard let installationID = next.installationID, defaults.string(forKey: installationKey) == installationID else {
            scoreSyncMessage = "This membership is from an earlier installation. Leave and rejoin to use this iPhone’s history."
            return
        }
        // Repeated taps/reloads cannot turn into a stream of source writes.
        if let lastSyncAttempt, now().timeIntervalSince(lastSyncAttempt) < 60 {
            let changed = [LeagueWeek(containing: effectiveNow), LeagueWeek(containing: effectiveNow, previous: true)]
                .contains { next.acknowledged[$0.key] != $0.count(events: repository.events, through: effectiveNow) }
            if changed || !next.pendingScores.isEmpty {
                scoreSyncMessage = "Your latest count is waiting to sync."
                scheduleSync()
            } else { scoreSyncMessage = nil }
            return
        }
        isWorking = true; errorMessage = nil
        defer {
            isWorking = false
            if needsSync { needsSync = false; scheduleSync() }
        }
        do {
            try checkBackoff()
            // Get server time before deciding week boundaries; device clocks are not authority.
            if latestServerTime == nil || now().timeIntervalSince(serverTimeReceivedAt ?? .distantPast) >= 60 {
                await fetchBoard(force: true)
                guard errorMessage == nil, latestServerTime != nil else { return }
            }
            guard repository.lastPersistenceError == nil else { updateLocalCount(); return }
            next = credential ?? next
            let instant = effectiveNow
            let weeks = [LeagueWeek(containing: instant), LeagueWeek(containing: instant, previous: true)]
            let keys = Set(weeks.map(\.key))
            next.pendingScores.removeAll { !keys.contains($0.seasonStart) }
            next.acknowledged = next.acknowledged.filter { keys.contains($0.key) }
            // A correction replaces a pending older aggregate using a higher revision.
            // Persist exact payloads before sending so lost responses can be retried safely.
            for week in weeks {
                let count = week.count(events: repository.events, through: instant)
                guard count <= 100000 else { throw LeagueFailure.message("This count is too large to publish. Your league total is unchanged.") }
                if let pending = next.pendingScores.first(where: { $0.seasonStart == week.key }), pending.count == count { continue }
                if next.acknowledged[week.key] == count && !next.pendingScores.contains(where: { $0.seasonStart == week.key }) { continue }
                next.revision += 1
                next.pendingScores.removeAll { $0.seasonStart == week.key }
                next.pendingScores.append(LeagueScoreSubmission(seasonStart: week.key, count: count, revision: next.revision))
            }
            try persist(next)
            guard !next.pendingScores.isEmpty else {
                scoreSyncMessage = nil; updateLocalCount(); return
            }
            lastSyncAttempt = now()
            for submission in next.pendingScores {
                let data = try await request(path: "score", method: "PUT", encodedBody: JSONEncoder().encode(submission))
                struct Receipt: Decodable { let accepted: Bool; let seasonStart: String; let count: Int; let revision: Int }
                let receipt = try JSONDecoder().decode(Receipt.self, from: data)
                guard receipt.accepted, receipt.seasonStart == submission.seasonStart,
                      receipt.count == submission.count, receipt.revision == submission.revision else { throw LeagueFailure.invalidResponse }
                guard var latest = credential else { throw LeagueFailure.secureStorage }
                latest.pendingScores.removeAll { $0.seasonStart == submission.seasonStart && $0.revision == submission.revision }
                latest.acknowledged[submission.seasonStart] = submission.count
                try persist(latest)
            }
            scoreSyncMessage = nil
            invalidateCache()
            await fetchBoard(force: true)
            updateLocalCount()
        } catch {
            report(error)
            scoreSyncMessage = "Your latest count is waiting to sync."
        }
    }

    public func leave() async {
        guard !isWorking, !isLoading, var next = credential else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            // Persist before networking. Failed deletion keeps its credential and
            // retries on next opening; it never reports a local-only opt-out.
            next.pendingDeletion = true; next.pendingScores = []; autoSyncTask?.cancel(); autoSyncTask = nil; needsSync = false
            try persist(next)
            pendingDeletion = true
            let data = try await request(path: "membership", method: "DELETE")
            struct Receipt: Decodable { let deleted: Bool }
            guard try JSONDecoder().decode(Receipt.self, from: data).deleted else { throw LeagueFailure.invalidResponse }
            try writeCredential(nil)
            credential = nil; member = nil; pendingDeletion = false; scoreSyncMessage = nil
            clearCache()
            await fetchBoard(force: true)
        } catch {
            report(error)
            if pendingDeletion { errorMessage = "Leaving is pending. Your public entry may remain until the server confirms deletion. " + (errorMessage ?? "Try again.") }
        }
    }

    private func fetchBoard(force: Bool = false) async {
        guard !isLoading else { return }
        let requestedSeason = season
        if savedBoard(for: requestedSeason) == nil { cache.removeValue(forKey: requestedSeason.rawValue); board = nil }
        if !force, let saved = cache[requestedSeason.rawValue],
           now().timeIntervalSince(saved.receivedAt) >= 0,
           now().timeIntervalSince(saved.receivedAt) < 60 {
            board = saved.board; errorMessage = nil
            latestServerTime = LeagueBoard.date(saved.board.serverNow); serverTimeReceivedAt = saved.receivedAt
            updateLocalCount(); return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await request(query: requestedSeason.rawValue)
            let value = try JSONDecoder().decode(LeagueBoard.self, from: data)
            guard value.isValid, value.member?.id == credential?.memberID,
                  let serverDate = LeagueBoard.date(value.serverNow),
                  LeagueBoard.date(value.seasonStart) == LeagueWeek(containing: serverDate, previous: requestedSeason == .previous).start else { throw LeagueFailure.invalidResponse }
            latestServerTime = LeagueBoard.date(value.serverNow); serverTimeReceivedAt = now()
            updateLocalCount()
            cache[requestedSeason.rawValue] = SavedBoard(board: value, receivedAt: now())
            if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: cacheKey) }
            if var next = credential, let membership = value.member {
                next.member = membership
                if let revision = value.myRevision, revision > next.revision {
                    next.revision = revision
                    let key = LeagueWeek(containing: serverDate, previous: requestedSeason == .previous).key
                    next.pendingScores.removeAll { $0.seasonStart == key && $0.revision <= revision }
                    next.acknowledged.removeValue(forKey: key)
                }
                try persist(next)
                member = membership
            }
            if season == requestedSeason { board = value; errorMessage = nil }
        } catch { if season == requestedSeason { report(error) } }
        // A picker can change during a fetch; don't leave that new scope empty.
        if season != requestedSeason {
            isLoading = false
            await fetchBoard()
        }
    }

    private func request(path: String? = nil, method: String = "GET", body: [String: String]? = nil,
                         query: String? = nil, encodedBody: Data? = nil) async throws -> Data {
        try checkBackoff()
        var components = URLComponents(url: path.map { endpoint.appendingPathComponent($0) } ?? endpoint, resolvingAgainstBaseURL: false)!
        if let query { components.queryItems = [URLQueryItem(name: "season", value: query)] }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let credential { request.setValue("Bearer " + credential.token, forHTTPHeaderField: "Authorization") }
        if body != nil || encodedBody != nil {
            request.httpBody = try encodedBody ?? body.map { try JSONEncoder().encode($0) }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport(request)
        guard data.count < 128 * 1024 else { throw LeagueFailure.invalidResponse }
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            retryAt = Double(header).map { now().addingTimeInterval(max(1, $0)) } ?? formatter.date(from: header)
            defaults.set(retryAt, forKey: retryKey)
        }
        guard (200..<300).contains(response.statusCode) else {
            if path == "score", response.statusCode == 409, var next = credential {
                // Server kept a newer revision or the week rolled over. Reconcile
                // the current local aggregate on the next deliberate attempt.
                next.pendingScores = []; next.acknowledged = [:]
                next.revision += 1
                try persist(next)
                invalidateCache()
            }
            if response.statusCode == 429 { throw LeagueFailure.message("The league is taking a breather. Try again after \((retryAt ?? now().addingTimeInterval(60)).formatted(date: .omitted, time: .shortened)).") }
            if response.statusCode == 401 || response.statusCode == 410 {
                throw LeagueFailure.message("This league membership is no longer active. Leave the league to clear it, then join again.")
            }
            if response.statusCode == 409 { throw LeagueFailure.message("The standings changed while syncing. Try syncing your count again in a minute.") }
            throw LeagueFailure.message("The league couldn't complete that request. Your saved standings are unchanged. Try again shortly.")
        }
        return data
    }

    private func recoverCredential() {
        do {
            credential = try readCredential().map { try JSONDecoder().decode(LeagueCredential.self, from: $0) }
            member = credential?.member; pendingDeletion = credential?.pendingDeletion ?? false
            storageFailed = false; errorMessage = nil
        } catch { storageFailed = true; report(LeagueFailure.secureStorage) }
    }

    private func persist(_ value: LeagueCredential) throws {
        try writeCredential(JSONEncoder().encode(value))
        credential = value
    }

    private func checkBackoff() throws {
        if let retryAt, retryAt > now() {
            throw LeagueFailure.message("The league is taking a breather. Try again after \(retryAt.formatted(date: .omitted, time: .shortened)).")
        }
    }

    private func report(_ error: Error) {
        if error is LeagueFailure { errorMessage = error.localizedDescription }
        else { errorMessage = "Couldn't reach the league. Your last saved standings are still here; connect and try again." }
    }

    private func clearCache() { cache = [:]; board = nil; defaults.removeObject(forKey: cacheKey) }
    private func invalidateCache() {
        cache = cache.mapValues { SavedBoard(board: $0.board, receivedAt: .distantPast) }
        defaults.removeObject(forKey: cacheKey)
    }
}
