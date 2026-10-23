#if os(watchOS)
import CiggyShared
import Combine
import CoreMotion
import Foundation

/// Explicit opt-in only. Pulls already-recorded physical Watch acceleration on
/// legitimate app wakes; this does not keep the Watch process alive all day.
@MainActor
final class BackgroundCalibrationCollector: ObservableObject {
    static let shared = BackgroundCalibrationCollector()
    private var ledger: HistoricalCalibrationSampler.Ledger?
    private var activeConsent: Date?
    private var generation = UUID()
    private var worker: Task<Extraction, Never>?
    @Published private(set) var lastError: String?
    @Published private(set) var isCollecting = false
    @Published private(set) var lastCompletedAt: Date?
    @Published private(set) var pendingChunkCount = 0
    @Published private(set) var retryingChunkCount = 0
    private let directory: URL
    private let maximumBytes = 80 * 1_024 * 1_024

    private enum Extraction: Sendable {
        case recording(Data)
        case missing
        case interrupted
        case failed(String)
    }

    private init() {
        directory = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                     ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("CiggyHistoricalCalibration", isDirectory: true)
        let url = directory.appendingPathComponent("ledger.json")
        if let data = try? Data(contentsOf: url), data.count <= 512 * 1_024,
           let saved = try? JSONDecoder().decode(HistoricalCalibrationSampler.Ledger.self, from: data) {
            ledger = saved
            activeConsent = saved.enabledAt
        }
    }

    /// Caller supplies at most six seconds in foreground and one second during
    /// background runtime. Cancelled/partially-read chunks never advance progress.
    func collect(enabledAt: Date?, maximumProcessingTime: Double = 6) async {
        guard let consent = enabledAt, consent.timeIntervalSince1970.isFinite,
              consent >= .distantPast, consent <= Date() else {
            purge()
            return
        }
        if activeConsent != consent {
            purge()
            activeConsent = consent
            ledger = .init(enabledAt: consent)
        }
        guard worker == nil, maximumProcessingTime.isFinite, maximumProcessingTime > 0 else { return }
        let now = Date()
        ledger?.reconcile(consent: consent, now: now)
        prune(at: now)
        saveLedger()
        updateStatus(at: now)
        #if targetEnvironment(simulator)
        return
        #else
        guard CMSensorRecorder.isAccelerometerRecordingAvailable(),
              CMSensorRecorder.authorizationStatus() == .authorized else { return }
        let token = generation
        let deadline = ProcessInfo.processInfo.systemUptime + min(6, maximumProcessingTime)
        // Time is the main bound; permit enough complete chunks to catch up
        // between system wakes instead of permanently growing a 30min backlog.
        let limit = maximumProcessingTime <= 1 ? 12 : 48
        isCollecting = true
        defer {
            if generation == token {
                worker = nil
                isCollecting = false
                updateStatus(at: Date())
            }
        }
        for _ in 0..<limit {
            guard generation == token, Task.isCancelled == false,
                  ProcessInfo.processInfo.systemUptime < deadline,
                  let window = ledger?.pending(now: now).first else { break }
            let url = fileURL(for: window)
            // Recover an interrupted file->queue->ledger transaction. The stable
            // recording ID makes an at-least-once retry harmless on the iPhone.
            if FileManager.default.fileExists(atPath: url.path) {
                ConnectivityManager.shared.sendMotionRecording(at: url)
                ledger?.didComplete(window)
                saveLedger()
                continue
            }
            let task = Task.detached(priority: .utility) {
                Self.extract(window: window, consent: consent, deadline: deadline)
            }
            worker = task
            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            guard generation == token, Task.isCancelled == false else { return }
            worker = nil
            switch result {
            case .recording(let data):
                guard ProcessInfo.processInfo.systemUptime < deadline else { return }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    var folder = directory
                    try folder.setResourceValues(values)
                    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    // Enqueue persists before committing the source cursor. A
                    // termination here can resend the same ID, never lose it.
                    ConnectivityManager.shared.sendMotionRecording(at: url)
                    ledger?.didComplete(window)
                    lastError = nil
                } catch {
                    lastError = "Could not save a calibration chunk: \(error.localizedDescription)"
                    return
                }
            case .missing:
                ledger?.retry(window, after: now)
            case .interrupted:
                return
            case .failed(let error):
                lastError = error
                return
            }
            saveLedger()
            prune(at: Date())
        }
        #endif
    }

    /// Cancels original-path and already-copied WC files before deleting the
    /// private queue, so opting out cannot flush stale raw recordings later.
    private func purge() {
        generation = UUID()
        worker?.cancel()
        worker = nil
        ConnectivityManager.shared.cancelMotionRecordingTransfers(in: directory)
        if FileManager.default.fileExists(atPath: directory.path) {
            do { try FileManager.default.removeItem(at: directory) }
            catch { lastError = "Could not delete the calibration queue: \(error.localizedDescription)" }
        }
        ledger = nil
        activeConsent = nil
        isCollecting = false
        lastCompletedAt = nil
        pendingChunkCount = 0
        retryingChunkCount = 0
    }

    private func updateStatus(at now: Date) {
        guard let ledger else { return }
        let eligible = HistoricalCalibrationSampler.windows(enabledAt: ledger.enabledAt, now: now)
        pendingChunkCount = eligible.filter { ledger.completed[$0.id] == nil }.count
        retryingChunkCount = ledger.retryAfter.count
        lastCompletedAt = ledger.completed.values.max()
    }

    private func fileURL(for window: HistoricalCalibrationSampler.Window) -> URL {
        let endMilliseconds = Int64(window.end.timeIntervalSince1970 * 1_000)
        return directory.appendingPathComponent("calibration_\(endMilliseconds)_\(window.id.uuidString).json")
    }

    private func saveLedger() {
        guard let ledger else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(ledger)
            try data.write(to: directory.appendingPathComponent("ledger.json"), options: .atomic)
        } catch { lastError = "Could not save calibration progress: \(error.localizedDescription)" }
    }

    private func prune(at now: Date) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                      includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        let oldest = now.addingTimeInterval(-HistoricalCalibrationSampler.retentionSeconds)
        var retained: [(url: URL, end: Date, bytes: Int)] = []
        for url in files where url.lastPathComponent.hasPrefix("calibration_") && url.pathExtension == "json" {
            let fields = url.deletingPathExtension().lastPathComponent.split(separator: "_")
            guard fields.count == 3, let milliseconds = Double(fields[1]), milliseconds.isFinite,
                  UUID(uuidString: String(fields[2])) != nil else {
                removeQueuedFile(url)
                continue
            }
            let end = Date(timeIntervalSince1970: milliseconds / 1_000)
            // Reject whole chunks that would retain even a leading sample older
            // than 48h, rather than retaining a 48h-old chunk for another 5min.
            guard end.addingTimeInterval(-HistoricalCalibrationSampler.chunkSeconds) >= oldest else {
                removeQueuedFile(url)
                continue
            }
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            retained.append((url, end, bytes))
        }
        var bytes = retained.reduce(0) { $0 + $1.bytes }
        for file in retained.sorted(by: { $0.end < $1.end }) where bytes > maximumBytes {
            removeQueuedFile(file.url)
            bytes -= file.bytes
        }
    }

    private func removeQueuedFile(_ url: URL) {
        ConnectivityManager.shared.cancelMotionRecordingTransfer(at: url)
        do { try FileManager.default.removeItem(at: url) }
        catch { lastError = "Could not remove an expired calibration chunk: \(error.localizedDescription)" }
    }

    private nonisolated static func extract(
        window: HistoricalCalibrationSampler.Window, consent: Date, deadline: TimeInterval
    ) -> Extraction {
        let shouldContinue = { Task.isCancelled == false && ProcessInfo.processInfo.systemUptime < deadline }
        guard shouldContinue() else { return .interrupted }
        let recorder = CMSensorRecorder()
        guard let source = recorder.accelerometerData(from: window.start, to: window.end) else { return .missing }
        var iterator = NSFastEnumerationIterator(source)
        let samples = AnySequence { AnyIterator<RecordedAccelerationSample> {
            guard let raw = iterator.next() as? CMRecordedAccelerometerData else { return nil }
            return .init(timestamp: raw.startDate, x: raw.acceleration.x, y: raw.acceleration.y, z: raw.acceleration.z)
        } }
        switch HistoricalCalibrationSampler.sample(samples, window: window, enabledAt: consent, shouldContinue: shouldContinue) {
        case .complete(let recording):
            do {
                let data = try JSONEncoder().encode(recording)
                guard shouldContinue() else { return .interrupted }
                return .recording(data)
            } catch { return .failed("Could not encode a calibration chunk: \(error.localizedDescription)") }
        case .missing: return .missing
        case .interrupted: return .interrupted
        }
    }
}
#endif
