#if os(iOS)
import CiggyShared
import Combine
import Foundation
import Security
import UIKit

/// Each tester enrolls explicitly. The upload credential stays in this iPhone's
/// Keychain; it never goes to the Watch, widgets, logs, or source control.
@MainActor
final class CalibrationUploadManager: NSObject, ObservableObject {
    static let shared = CalibrationUploadManager()
    static let origin = URL(string: "https://ciggy.thatcanadian.dev")!
    nonisolated static let statusTaskName = "delivery-status-v1:="
    nonisolated static func isDeliveryReport(_ name: String?) -> Bool { name?.hasPrefix(statusTaskName) == true }
    private var preparationLease: UIBackgroundTaskIdentifier = .invalid
    private let statusDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CiggyDeliveryStatus", isDirectory: true)
    static let sessionIdentifier = "dev.thatcanadian.ciggy.calibration.upload.v1"
    @Published private(set) var alias: String
    @Published private(set) var isEnrolled = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var scheduledCount = 0
    @Published private(set) var nextRetryAt: Date?
    @Published private(set) var lastUploadedAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var lastDeliveryError: String?
    @Published private(set) var isWorking = false
    @Published private(set) var requiresPairing = false
    var backgroundCompletion: (() -> Void)? {
        didSet { finishBackgroundEventsIfReady() }
    }
    private var backgroundEventsFinished = false
    private var isFlushing = false
    private var needsFlush = false
    private var isPruning = false
    private var lastPrunedAt: Date?

    private weak var settings: UserSettingsStore?
    private var subscriptions: Set<AnyCancellable> = []
    private var responses: [Int: Data] = [:]
    private var backoff = CalibrationUploadPolicy.Backoff()
    private var deliveryPolicy = CalibrationDeliveryPolicy()
    private let deliveryPolicyKey = "Ciggy.calibration.deliveryPolicy.v14"
    private var generation = UUID()
    private var preparation: Task<PreparedQueue, Never>?
    private var session: URLSession?
    private let keychainService = "dev.thatcanadian.ciggy.calibration"
    private let backoffKey = "Ciggy.calibration.uploadBackoff.v1"
    private let pairingRequiredKey = "Ciggy.calibration.pairingRequired.v1"
    private let queueDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CiggyCalibrationUploads", isDirectory: true)

    private override init() {
        alias = UserDefaults.standard.string(forKey: "Ciggy.calibration.alias") ?? ""
        lastUploadedAt = UserDefaults.standard.object(forKey: "Ciggy.calibration.lastUploadedAt") as? Date
        super.init()
        isEnrolled = credential() != nil
        requiresPairing = UserDefaults.standard.bool(forKey: pairingRequiredKey)
        if let data = UserDefaults.standard.data(forKey: backoffKey), data.count <= 1_024 * 1_024,
           let saved = try? JSONDecoder().decode(CalibrationUploadPolicy.Backoff.self, from: data) { backoff = saved }
        if let data = UserDefaults.standard.data(forKey: deliveryPolicyKey), data.count <= 4_096,
           let saved = try? JSONDecoder().decode(CalibrationDeliveryPolicy.self, from: data) { deliveryPolicy = saved }
        backoff.prune(keeping: Set(backoff.failures.keys), at: Date())
    }

    private func ensureSession() -> URLSession {
        if let session { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForResource = 24 * 3_600
        configuration.httpMaximumConnectionsPerHost = 2
        // Delegate callbacks run synchronously on main, preserving body → receipt
        // → background-completion ordering without unstructured task races.
        let created = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        session = created
        return created
    }

    func restoreBackgroundSession(completion: @escaping () -> Void) {
        backgroundCompletion = completion
        _ = ensureSession()
    }

    private func finishBackgroundEventsIfReady() {
        guard backgroundEventsFinished, isFlushing == false, let completion = backgroundCompletion else { return }
        backgroundEventsFinished = false
        backgroundCompletion = nil
        completion()
    }

    func bind(settings: UserSettingsStore) {
        guard self.settings == nil else { return }
        self.settings = settings
        beginPreparationLease()
        _ = ensureSession()
        settings.$settings.map(\.calibrationEnabledAt).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { @MainActor [weak self] enabledAt in
                guard let self, self.settings?.settings.calibrationEnabledAt == enabledAt else { return }
                if enabledAt == nil { self.cancelPendingUploads() }
                else { self.flush() }
            }.store(in: &subscriptions)
        MotionRecordingStore.shared.$latestRecordingURL
            .sink { @MainActor [weak self] _ in self?.flush() }
            .store(in: &subscriptions)
        TrackingStatusStore.shared.$status
            .dropFirst().debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { @MainActor [weak self] _ in self?.flush() }.store(in: &subscriptions)
        if requiresPairing { stopSharing(); endPreparationLease() } else { flush() }
    }

    func enroll(code: String, alias: String) async throws {
        guard isWorking == false else { throw CalibrationError.message("Another pairing action is still finishing.") }
        guard settings != nil, isEnrolled == false else {
            throw CalibrationError.message("Forget the previous pairing before connecting this iPhone again.")
        }
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(trimmedAlias.count), (6...128).contains(trimmedCode.count) else {
            throw CalibrationError.message("Enter your name and the pairing code from the private dashboard.")
        }
        isWorking = true
        defer { isWorking = false; flush() }
        var request = URLRequest(url: Self.origin.appendingPathComponent("api/enroll"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": trimmedCode, "alias": trimmedAlias])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 16_384 else {
            throw CalibrationError.message("Pairing failed. Get a new code from the dashboard and try again.")
        }
        struct Enrollment: Decodable { let participantID: String; let token: String }
        let enrollment = try JSONDecoder().decode(Enrollment.self, from: data)
        guard UUID(uuidString: enrollment.participantID) != nil,
              (32...512).contains(enrollment.token.utf8.count),
              enrollment.token.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) })
        else { throw CalibrationError.invalidResponse }
        try saveCredential(enrollment.token)
        self.alias = trimmedAlias
        UserDefaults.standard.set(trimmedAlias, forKey: "Ciggy.calibration.alias")
        isEnrolled = true
        requiresPairing = false
        UserDefaults.standard.removeObject(forKey: pairingRequiredKey)
        lastError = nil
        // Enrollment and the explicit opt-in action are one operation. No earlier
        // recordings are eligible, including old debug/calibration files.
        settings?.settings.calibrationEnabledAt = Date()
        ConnectivityManager.shared.send(settings: settings?.settings ?? UserSettings())
        ConnectivityManager.shared.requestHistoryRefresh()
        flush()
    }

    func pause() {
        guard isWorking == false else { return }
        stopSharing()
    }

    private func stopSharing() {
        settings?.settings.calibrationEnabledAt = nil
        if let settings { ConnectivityManager.shared.send(settings: settings.settings) }
        cancelPendingUploads()
    }

    func resume() {
        guard isWorking == false, isEnrolled, requiresPairing == false, credential() != nil else { return }
        settings?.settings.calibrationEnabledAt = Date()
        if let settings { ConnectivityManager.shared.send(settings: settings.settings) }
        ConnectivityManager.shared.requestHistoryRefresh()
        flush()
    }

    func deleteSharedData() async throws {
        guard isWorking == false else { throw CalibrationError.message("Another pairing action is still finishing.") }
        guard let token = credential() else { throw CalibrationError.message("This iPhone has no pairing credential. Delete its shared data from the private dashboard.") }
        isWorking = true
        defer { isWorking = false }
        stopSharing()
        var request = URLRequest(url: Self.origin.appendingPathComponent("api/participant"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CalibrationError.message("Sharing is paused. Deletion could not be confirmed; try again when online.")
        }
        stopSharing()
        try forgetLocalPairing()
        lastError = nil
    }

    func forgetPairing() throws {
        guard isWorking == false else { throw CalibrationError.message("Another pairing action is still finishing.") }
        isWorking = true
        defer { isWorking = false }
        stopSharing()
        try forgetLocalPairing()
        lastError = "Pairing forgotten. Previously shared data remains on the private dashboard until you delete it there or its 14-day retention expires."
    }

    private func forgetLocalPairing() throws {
        let status = SecItemDelete(keychainQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CalibrationError.message("Sharing is paused, but the local pairing could not be cleared. Try again.")
        }
        isEnrolled = false
        requiresPairing = false
        alias = ""
        UserDefaults.standard.removeObject(forKey: "Ciggy.calibration.alias")
        UserDefaults.standard.removeObject(forKey: pairingRequiredKey)
    }

    func flush() {
        pruneExpiredHistory()
        guard isWorking == false, requiresPairing == false,
              let enabledAt = settings?.settings.calibrationEnabledAt, let token = credential() else {
            if !isFlushing { endPreparationLease() }
            return
        }
        guard !isFlushing else { needsFlush = true; return }
        isFlushing = true
        beginPreparationLease()
        CalibrationBackgroundDelivery.shared.schedule()
        let currentGeneration = generation
        let uploadSession = ensureSession()
        uploadSession.getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    self.preparation = nil
                    self.isFlushing = false
                    if self.needsFlush { self.needsFlush = false; self.flush() }
                    else { self.endPreparationLease() }
                    self.finishBackgroundEventsIfReady()
                }
                guard self.generation == currentGeneration, self.isWorking == false,
                      self.settings?.settings.calibrationEnabledAt == enabledAt else { return }
                let urls = MotionRecordingStore.shared.savedRecordingURLs()
                let consentHeader = String(enabledAt.timeIntervalSince1970)
                for task in tasks where task.originalRequest?.value(forHTTPHeaderField: "X-Ciggy-Consent") != consentHeader ||
                    task.originalRequest?.value(forHTTPHeaderField: "Authorization") != "Bearer \(token)" { task.cancel() }
                let motionTasks = tasks.filter { !Self.isDeliveryReport($0.taskDescription) }
                let activeNames = Set(motionTasks.filter {
                    ($0.state == .running || $0.state == .suspended) &&
                    $0.originalRequest?.value(forHTTPHeaderField: "X-Ciggy-Consent") == consentHeader &&
                    $0.originalRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)"
                }.compactMap(\.taskDescription))
                // Diagnostics must not wait for every raw file to decode/stage.
                // These counts describe the saved inbox and system upload queue;
                // expired/pre-consent files are reconciled by preparation below.
                self.pendingCount = urls.count
                self.scheduledCount = activeNames.count
                self.scheduleDeliveryReport(tasks: tasks, consent: enabledAt, token: token)
                let now = Date()
                let delays = self.backoff
                let directory = self.queueDirectory
                // Parsing every sample and staging raw JSON can be substantial.
                // Keep it off main while this entire snapshot remains serialized.
                let preparation = Task.detached(priority: .utility) {
                    Self.prepareQueue(urls: urls, directory: directory, consent: enabledAt,
                                      now: now, activeNames: activeNames, backoff: delays)
                }
                self.preparation = preparation
                let prepared = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
                guard self.generation == currentGeneration, self.isWorking == false,
                      self.requiresPairing == false, self.settings?.settings.calibrationEnabledAt == enabledAt,
                      self.credential() == token, prepared.cancelled == false else {
                    Self.removeStaged(prepared.staged.map(\.body))
                    return
                }
                let valid = Set(prepared.eligible.map(\.name))
                var active = Set<String>()
                for task in motionTasks {
                    let name = task.taskDescription ?? ""
                    guard valid.contains(name), task.state != .canceling, task.state != .completed,
                          task.originalRequest?.value(forHTTPHeaderField: "X-Ciggy-Consent") == String(enabledAt.timeIntervalSince1970),
                          active.insert(name).inserted else { task.cancel(); continue }
                }
                for url in prepared.discarded { try? MotionRecordingStore.shared.removeRecording(at: url) }
                self.backoff.prune(keeping: valid, at: Date())
                self.saveBackoff()
                self.pendingCount = prepared.eligible.count
                var capacity = max(0, CalibrationUploadPolicy.maximumScheduledFiles - active.count)
                for item in prepared.staged {
                    guard capacity > 0, active.contains(item.name) == false,
                          item.expiresAt > Date() else {
                        Self.removeStaged([item.body])
                        continue
                    }
                    var request = URLRequest(url: Self.origin.appendingPathComponent("api/upload"))
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(String(enabledAt.timeIntervalSince1970), forHTTPHeaderField: "X-Ciggy-Consent")
                    let task = uploadSession.uploadTask(with: request, fromFile: item.body)
                    task.taskDescription = item.name
                    task.earliestBeginDate = self.backoff.nextAttempt(for: item.name, at: Date())
                    task.countOfBytesClientExpectsToSend = Int64((try? item.body.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    task.resume()
                    active.insert(item.name)
                    capacity -= 1
                }
                self.scheduledCount = active.count
                self.nextRetryAt = prepared.eligible.map { self.backoff.nextAttempt(for: $0.name, at: now) }.filter { $0 > now }.min()
                if prepared.failed { self.lastError = "Could not queue a motion recording. The original remains saved for retry." }
            }
        }
    }

    private func cancelPendingUploads() {
        generation = UUID()
        preparation?.cancel()
        needsFlush = false
        ensureSession().getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let currentConsent = self.settings?.settings.calibrationEnabledAt.map { String($0.timeIntervalSince1970) }
                for task in tasks where currentConsent == nil || task.originalRequest?.value(forHTTPHeaderField: "X-Ciggy-Consent") != currentConsent {
                    task.cancel()
                }
            }
        }
        try? FileManager.default.removeItem(at: queueDirectory)
        try? FileManager.default.removeItem(at: statusDirectory)
        UserDefaults.standard.removeObject(forKey: "Ciggy.calibration.statusQueuedAt")
        deliveryPolicy = CalibrationDeliveryPolicy()
        UserDefaults.standard.removeObject(forKey: deliveryPolicyKey)
        lastDeliveryError = nil
        pendingCount = 0
        scheduledCount = 0
        nextRetryAt = nil
        CalibrationBackgroundDelivery.shared.cancel()
    }

    private func beginPreparationLease() {
        guard preparationLease == .invalid else { return }
        preparationLease = UIApplication.shared.beginBackgroundTask(withName: "Prepare saved motion uploads") { [weak self] in
            Task { @MainActor [weak self] in
                self?.preparation?.cancel()
                self?.needsFlush = false
                self?.endPreparationLease()
            }
        }
    }

    private func endPreparationLease() {
        guard preparationLease != .invalid else { return }
        UIApplication.shared.endBackgroundTask(preparationLease)
        preparationLease = .invalid
    }

    /// A recovery wake only prepares optional calibration; no history/detection
    /// request or cigarette mutation is involved.
    func recoverInBackground() async -> Bool {
        MotionRecordingStore.shared.recoverIncomingRecordings()
        flush()
        let deadline = Date().addingTimeInterval(20)
        while isFlushing && Date() < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if Task.isCancelled { preparation?.cancel() }
        return !isFlushing && !Task.isCancelled
    }

    private func scheduleDeliveryReport(tasks: [URLSessionTask], consent: Date, token: String) {
        guard !tasks.contains(where: { Self.isDeliveryReport($0.taskDescription) &&
            ($0.state == .running || $0.state == .suspended) &&
            $0.originalRequest?.value(forHTTPHeaderField: "X-Ciggy-Consent") == String(consent.timeIntervalSince1970) &&
            $0.originalRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)" }) else { return }
        let now = Date()
        guard deliveryPolicy.shouldSchedule(at: now) else { return }
        let report = CalibrationDeliveryReport(observedAt: now, consentAt: consent,
            phoneBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            phoneLastReceivedAt: MotionRecordingStore.shared.lastReceivedAt, phoneLastUploadedAt: lastUploadedAt,
            phonePendingCount: pendingCount, phoneScheduledCount: scheduledCount, phoneRetryAt: nextRetryAt,
            watchStatus: TrackingStatusStore.shared.status?.calibration)
        do {
            try FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
            let reportID = UUID().uuidString
            let body = statusDirectory.appendingPathComponent(reportID + ".json")
            try report.encoded().write(to: body, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var request = URLRequest(url: Self.origin.appendingPathComponent("api/upload"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(String(consent.timeIntervalSince1970), forHTTPHeaderField: "X-Ciggy-Consent")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("delivery-status", forHTTPHeaderField: "X-Ciggy-Payload")
            let task = ensureSession().uploadTask(with: request, fromFile: body)
            task.taskDescription = Self.statusTaskName + reportID
            task.earliestBeginDate = deliveryPolicy.earliestBeginDate(at: now, providerRetryAt: backoff.providerRetryAt)
            task.resume()
        } catch { lastDeliveryError = "Delivery status could not be saved for upload. Motion recordings remain queued separately." }
    }

    private struct QueueEntry: Sendable {
        let name: String
        let url: URL
        let startedAt: Date
        let expiresAt: Date
    }

    private struct Staged: Sendable {
        let name: String
        let body: URL
        let expiresAt: Date
    }

    private struct PreparedQueue: Sendable {
        var eligible: [QueueEntry] = []
        var discarded: [URL] = []
        var staged: [Staged] = []
        var cancelled = false
        var failed = false
        nonisolated init() {}
    }

    /// Local retention also applies after sharing is paused, including late
    /// Watch deliveries. Keep intentional live recordings separate from the
    /// automatic historical queue.
    private func pruneExpiredHistory() {
        let now = Date()
        guard !isPruning, lastPrunedAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        isPruning = true
        lastPrunedAt = now
        let urls = MotionRecordingStore.shared.savedRecordingURLs()
        Task { @MainActor [weak self] in
            let expired = await Task.detached(priority: .utility) {
                urls.filter { url in
                    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                          size <= 10 * 1_024 * 1_024, let data = try? Data(contentsOf: url),
                          let recording = try? JSONDecoder().decode(MotionRecording.self, from: data),
                          recording.startedAt < now.addingTimeInterval(-CalibrationUploadPolicy.retention),
                          recording.samples.isEmpty == false else { return false }
                    return recording.samples.allSatisfy { $0.source == .recordedAccelerometer }
                }
            }.value
            guard let self else { return }
            for url in expired {
                try? MotionRecordingStore.shared.removeRecording(at: url)
                try? FileManager.default.removeItem(at: self.queueDirectory.appendingPathComponent(url.lastPathComponent))
            }
            self.isPruning = false
        }
    }

    private nonisolated static func prepareQueue(
        urls: [URL], directory: URL, consent: Date, now: Date,
        activeNames: Set<String>, backoff: CalibrationUploadPolicy.Backoff
    ) -> PreparedQueue {
        var result = PreparedQueue()
        for url in urls {
            guard Task.isCancelled == false else { result.cancelled = true; return result }
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= CalibrationUploadPolicy.maximumBytes,
                  let data = try? Data(contentsOf: url),
                  data.count <= CalibrationUploadPolicy.maximumBytes,
                  let recording = try? JSONDecoder().decode(MotionRecording.self, from: data) else { continue }
            switch CalibrationUploadPolicy.eligibility(recording, filename: url.lastPathComponent, consent: consent, now: now) {
            case .eligible(let expiresAt):
                result.eligible.append(.init(name: url.lastPathComponent, url: url, startedAt: recording.startedAt, expiresAt: expiresAt))
            case .beforeConsent, .expired: result.discarded.append(url)
            case .invalid: break
            }
        }
        let valid = Set(result.eligible.map(\.name))
        // Staged copies include files retained by an older app version. Never
        // retain an orphan, expired, or pre-consent upload body for later replay.
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.lastPathComponent
            if valid.contains(name) == false { try? FileManager.default.removeItem(at: url) }
        }
        let capacity = max(0, CalibrationUploadPolicy.maximumScheduledFiles - activeNames.intersection(valid).count)
        let choices = result.eligible.sorted { $0.startedAt > $1.startedAt }.filter {
            activeNames.contains($0.name) == false
        }.prefix(capacity)
        var scheduledBytes = activeNames.reduce(0) { total, name in
            total + ((try? directory.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        for item in choices {
            guard Task.isCancelled == false else {
                removeStaged(result.staged.map(\.body)); result.staged = []; result.cancelled = true; return result
            }
            do {
                let data = try Data(contentsOf: item.url)
                let recording = try JSONDecoder().decode(MotionRecording.self, from: data)
                guard data.count <= CalibrationUploadPolicy.maximumBytes,
                      case .eligible = CalibrationUploadPolicy.eligibility(recording, filename: item.name, consent: consent, now: Date())
                else { continue }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var folder = directory
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try folder.setResourceValues(values)
                let body = directory.appendingPathComponent(item.name)
                // Imports can contain unknown JSON keys. Only the declared motion
                // fields may leave this iPhone, never unrelated attached metadata.
                let payload = try JSONEncoder().encode(recording)
                guard scheduledBytes + payload.count <= CalibrationUploadPolicy.maximumScheduledBytes else { continue }
                scheduledBytes += payload.count
                try payload.write(to: body, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                result.staged.append(.init(name: item.name, body: body, expiresAt: item.expiresAt))
            } catch { result.failed = true }
        }
        if Task.isCancelled {
            removeStaged(result.staged.map(\.body)); result.staged = []; result.cancelled = true
        }
        return result
    }

    private nonisolated static func removeStaged(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    private func saveBackoff() {
        if let data = try? JSONEncoder().encode(backoff) { UserDefaults.standard.set(data, forKey: backoffKey) }
    }

    private func keychainQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "upload-token"]
    }

    private func credential() -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveCredential(_ token: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let query = keychainQuery()
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        var status = updated
        if updated == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw CalibrationError.message("Could not securely save the pairing. Please try again.")
        }
    }

    private func completed(taskID: Int, name: String?, response: HTTPURLResponse?, error: String?, errorCode: Int?,
                           authorization: String?, consent: String?) {
        let body = responses.removeValue(forKey: taskID) ?? Data()
        guard let name else { return }
        if Self.isDeliveryReport(name) {
            let id = String(name.dropFirst(Self.statusTaskName.count))
            if UUID(uuidString: id) != nil { try? FileManager.default.removeItem(at: statusDirectory.appendingPathComponent(id + ".json")) }
            // A cancelled/old-consent callback must not resurrect opted-out work.
            guard errorCode != NSURLErrorCancelled,
                  let enabledAt = settings?.settings.calibrationEnabledAt,
                  consent == String(enabledAt.timeIntervalSince1970),
                  let token = credential(), authorization == "Bearer \(token)" else { return }
            if error == nil, let response, (200..<300).contains(response.statusCode),
               CalibrationDeliveryPolicy.receiptMatches(body) {
                deliveryPolicy.succeeded(at: Date())
                lastDeliveryError = nil
            } else {
                deliveryPolicy.failed(at: Date(), retryAfter: response?.value(forHTTPHeaderField: "Retry-After"))
                lastDeliveryError = "Delivery status has not reached the dashboard. A background retry is queued over Wi-Fi."
            }
            if let saved = try? JSONEncoder().encode(deliveryPolicy) { UserDefaults.standard.set(saved, forKey: deliveryPolicyKey) }
            if response?.statusCode == 401 {
                requiresPairing = true
                UserDefaults.standard.set(true, forKey: pairingRequiredKey)
                stopSharing()
                lastError = "This pairing can no longer upload. Reconnect this iPhone using a new dashboard code."
            } else if deliveryPolicy.failures > 0 {
                // Recreate the small report with current metadata and give its
                // persisted retry deadline to the background session now.
                flush()
            }
            return
        }
        if errorCode == NSURLErrorCancelled { flush(); return }
        let original = MotionRecordingStore.shared.savedRecordingURLs().first { $0.lastPathComponent == name }
        if error == nil, let response, (200..<300).contains(response.statusCode),
           CalibrationUploadPolicy.receiptMatches(body, filename: name) {
            if let original { try? MotionRecordingStore.shared.removeRecording(at: original) }
            try? FileManager.default.removeItem(at: queueDirectory.appendingPathComponent(name))
            lastUploadedAt = Date()
            UserDefaults.standard.set(lastUploadedAt, forKey: "Ciggy.calibration.lastUploadedAt")
            backoff.succeeded(name)
            saveBackoff()
            pendingCount = max(0, pendingCount - 1)
            lastError = nil
            flush()
        } else if error == nil, response?.statusCode == 410 {
            // Native-upload expiry is terminal; developer imports have a separate
            // server route. A stale body must never retry indefinitely.
            if let original { try? MotionRecordingStore.shared.removeRecording(at: original) }
            Self.removeStaged([queueDirectory.appendingPathComponent(name)])
            backoff.succeeded(name)
            saveBackoff()
            pendingCount = max(0, pendingCount - 1)
            lastError = "An old calibration recording expired before it could upload. Recent recordings still sync."
            flush()
        } else if let enabledAt = settings?.settings.calibrationEnabledAt,
                  consent == String(enabledAt.timeIntervalSince1970),
                  let token = credential(), authorization == "Bearer \(token)" {
            backoff.failed(name, status: response?.statusCode,
                           retryAfter: response?.value(forHTTPHeaderField: "Retry-After"), at: Date())
            saveBackoff()
            if response?.statusCode == 401 {
                requiresPairing = true
                UserDefaults.standard.set(true, forKey: pairingRequiredKey)
                stopSharing()
                lastError = "This pairing can no longer upload. Forget this pairing and use a new dashboard code. Previously shared data remains until deleted or its retention expires."
            } else {
                lastError = "Upload pending. Ciggy retries eligible saved recordings over Wi-Fi when it can run."
                if response?.statusCode == 429 || response?.statusCode == 503 {
                    // Re-stage not-yet-finished tasks with the provider's shared
                    // deadline instead of letting queued files bypass Retry-After.
                    ensureSession().getAllTasks { [weak self] tasks in
                        for task in tasks where !Self.isDeliveryReport(task.taskDescription) { task.cancel() }
                        Task { @MainActor [weak self] in self?.flush() }
                    }
                } else { flush() }
            }
        }
    }

    enum CalibrationError: LocalizedError {
        case message(String), invalidResponse
        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            case .invalidResponse: return "The dashboard returned an invalid pairing response."
            }
        }
    }
}

extension CalibrationUploadManager: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                               completionHandler: @escaping (URLRequest?) -> Void) {
        // A login/configuration redirect is a failed upload, never permission to
        // forward the tester's bearer credential to another origin.
        completionHandler(nil)
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        MainActor.assumeIsolated {
            var collected = self.responses[id] ?? Data()
            guard collected.count + data.count <= 16_384 else { dataTask.cancel(); return }
            collected.append(data)
            self.responses[id] = collected
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        let name = task.taskDescription
        let response = task.response as? HTTPURLResponse
        let message = error?.localizedDescription
        let authorization = task.originalRequest?.value(forHTTPHeaderField: "Authorization")
        let consent = task.originalRequest?.value(forHTTPHeaderField: "X-Ciggy-Consent")
        MainActor.assumeIsolated {
            self.completed(taskID: id, name: name, response: response, error: message, errorCode: (error as NSError?)?.code,
                           authorization: authorization, consent: consent)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            self.backgroundEventsFinished = true
            self.finishBackgroundEventsIfReady()
        }
    }
}
#endif
