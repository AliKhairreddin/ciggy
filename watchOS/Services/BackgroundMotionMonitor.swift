#if os(watchOS)
import CiggyShared
import Combine
import CoreMotion
import Foundation
import WatchKit

struct HistoricalMotionBatch: Sendable {
	let candidates: [DetectionCandidate]
	let processedFrom: Date
	let processedThrough: Date
	let analyzer: RecordedMotionAnalyzer
	let latestSampleAt: Date?
	let pendingRanges: [MotionHistoryRange]
	let replayCheckpoints: [MotionHistoryReplayCheckpoint]
	let didExpireHistory: Bool
	let recentPending: Bool
}

/// Arms watchOS historical accelerometer capture and analyzes the recorded backlog during
/// foreground use and scheduled background refresh. `CMSensorRecorder` keeps collecting while the app is
/// suspended or terminated; analysis itself happens only when the app has runtime.
@MainActor
final class BackgroundMotionMonitor: ObservableObject {
	static let shared = BackgroundMotionMonitor()

	@Published private(set) var isCaptureAvailable = false
	@Published private(set) var isCaptureArmed = false
	@Published private(set) var isProcessingHistory = false
	@Published private(set) var lastError: String?
	private var runtimePersistenceError: String?
	@Published private(set) var lastHistorySampleAt: Date?
	@Published private(set) var lastHistoryCheckedAt: Date?
	@Published private(set) var hasPendingHistory = false
	@Published private(set) var hasExpiredHistory = false

	private let recorder = CMSensorRecorder()
	private let userDefaults: UserDefaults
	private let checkpointStore: MotionHistoryCheckpointStore
	private let armedUntilKey = "BackgroundMotionMonitor.armedUntil.v1"
	private let scheduledRefreshKey = "BackgroundMotionMonitor.scheduledRefresh.v1"
	private let captureDuration: TimeInterval = 12 * 60 * 60
	// A refresh also analyzes the backlog. watchOS decides when it actually runs.
	private let renewalInterval = TrackingRefreshPolicy.preferredBackgroundInterval
	private let availabilityDelay: TimeInterval = 3 * 60
	private let retentionDuration: TimeInterval = 3 * 24 * 60 * 60
	private let queryChunkDuration: TimeInterval = 30 * 60

	private init(userDefaults: UserDefaults = .standard) {
		self.userDefaults = userDefaults
		checkpointStore = MotionHistoryCheckpointStore(userDefaults: userDefaults)
		lastHistorySampleAt = checkpoint?.latestSampleAt
		lastHistoryCheckedAt = checkpoint?.checkedAt
		hasPendingHistory = checkpoint?.pendingRanges?.isEmpty == false || checkpoint?.backlogPending == true
		hasExpiredHistory = checkpoint?.hasExpiredHistory ?? false
		lastError = checkpointStore.lastError
		refreshStatus()
	}

	var statusDetail: String {
		if let error = runtimePersistenceError ?? lastError { return error }
		if hasPendingHistory { return "Some motion history is unavailable. Ciggy retries it while watchOS retains the recording; recent available activity still updates." }
		if hasExpiredHistory { return "Some older motion history expired before it could be checked, so past totals may be incomplete. Recent available activity still updates." }
		if isCaptureAvailable == false { return "Automatic detection needs a physical Apple Watch with motion access." }
		if isCaptureArmed == false { return "Open Ciggy and allow Motion & Fitness access to start background capture." }
		return "Ciggy requests background checks about every 15 minutes. Keep a Ciggy complication on your active Watch face; watchOS controls when checks actually run and can delay them longer."
	}

	var statusText: String {
		#if targetEnvironment(simulator)
		return "Device only"
		#else
		if isCaptureAvailable == false { return "Unavailable" }
		switch CMSensorRecorder.authorizationStatus() {
		case .denied, .restricted:
			return "Permission needed"
		case .notDetermined:
			return "Awaiting permission"
		case .authorized:
			if isProcessingHistory { return "Checking history" }
			if hasPendingHistory { return "Retrying history" }
			return isCaptureArmed ? "Background armed" : "Open to re-arm"
		@unknown default:
			return isCaptureArmed ? "Background armed" : "Unavailable"
		}
		#endif
	}

	/// Starts or extends the system recording window and asks watchOS to wake Ciggy before
	/// the 12-hour maximum expires. Background refresh timing is best-effort, so every
	/// foreground launch also calls this method.
	func armRecording() {
		refreshStatus()
		guard isCaptureAvailable else {
			userDefaults.removeObject(forKey: armedUntilKey)
			publishStatus()
			return
		}

		let authorization = CMSensorRecorder.authorizationStatus()
		guard authorization != .denied, authorization != .restricted else {
			userDefaults.removeObject(forKey: armedUntilKey)
			isCaptureArmed = false
			lastError = "Motion access is disabled in Settings."
			publishStatus()
			return
		}

		let now = Date()
		guard checkpointStore.beginCapture(at: now) else {
			lastError = checkpointStore.lastError
			publishStatus()
			return
		}
		let armedUntil = userDefaults.object(forKey: armedUntilKey) as? Date
		if MotionCapturePolicy.shouldRenew(at: now, armedUntil: armedUntil) {
			recorder.recordAccelerometer(forDuration: captureDuration)
			if CMSensorRecorder.authorizationStatus() == .authorized {
				userDefaults.set(now.addingTimeInterval(captureDuration), forKey: armedUntilKey)
			}
		}
		refreshStatus()
		lastError = nil
		scheduleRenewal(after: renewalInterval)
		publishStatus()
	}

	func backgroundRefreshDidBegin() {
		userDefaults.removeObject(forKey: scheduledRefreshKey)
	}

	func foregroundDidEnd(startedAt: Date?, at endedAt: Date = Date()) {
		if MotionCapturePolicy.wasRefreshDueDuringForeground(
			scheduledAt: userDefaults.object(forKey: scheduledRefreshKey) as? Date,
			foregroundStartedAt: startedAt, endedAt: endedAt
		) {
			userDefaults.removeObject(forKey: scheduledRefreshKey)
		}
	}

	func reportPersistenceError(_ error: String?) {
		guard runtimePersistenceError != error else { return }
		runtimePersistenceError = error
		publishStatus()
	}

	func publishStatus() {
		let status = TrackingStatus(
			historyCheckedAt: lastHistoryCheckedAt,
			historySampleAt: lastHistorySampleAt,
			captureUntil: userDefaults.object(forKey: armedUntilKey) as? Date,
			pendingHistory: hasPendingHistory,
			expiredHistory: hasExpiredHistory,
			captureAvailable: isCaptureAvailable,
			permissionGranted: CMSensorRecorder.authorizationStatus() == .authorized,
			lastError: runtimePersistenceError ?? lastError,
			isProcessing: isProcessingHistory,
			calibration: BackgroundCalibrationCollector.shared.status
		)
		TrackingStatusStore.shared.receive(status)
		ConnectivityManager.shared.send(trackingStatus: status)
	}

	/// Reads samples old enough to be available from Core Motion and returns all probable
	/// sessions. The caller persists the candidates before committing `processedThrough`.
	func processAvailableHistory(sensitivity: Double, maximumProcessingTime: TimeInterval = 20) async -> HistoricalMotionBatch? {
		refreshStatus()
		guard isCaptureAvailable, isProcessingHistory == false else { return nil }
		guard checkpointStore.loadFailed == false else {
			lastError = checkpointStore.lastError
			return nil
		}
		guard CMSensorRecorder.authorizationStatus() == .authorized else { return nil }
		guard let storedCursor = processedThrough else { return nil }

		let end = Date().addingTimeInterval(-availabilityDelay)
		let start = max(storedCursor, end.addingTimeInterval(-retentionDuration))
		guard start < end else { return nil }

		isProcessingHistory = true
		defer { isProcessingHistory = false; publishStatus() }
		publishStatus()
		lastHistoryCheckedAt = Date()
		let queryChunkDuration = self.queryChunkDuration
		var analyzer = checkpoint?.analyzer ?? RecordedMotionAnalyzer(sensitivity: sensitivity)
		analyzer.updateSensitivity(sensitivity)
		let initialAnalyzer = analyzer
		let pendingRanges = checkpoint?.pendingRanges ?? []
		let replayCheckpoints = checkpoint?.replayCheckpoints ?? []
		let sourceStartedAt = checkpoint?.sourceStartedAt
		let processing = Task.detached(priority: .utility) {
			HistoricalMotionProcessor.process(
				from: start,
				to: end,
				analyzer: initialAnalyzer,
				pendingRanges: pendingRanges,
				replayCheckpoints: replayCheckpoints,
				sourceStartedAt: sourceStartedAt,
				sensitivity: sensitivity,
				queryChunkDuration: queryChunkDuration,
				maximumProcessingTime: maximumProcessingTime
			)
		}
		let result = await withTaskCancellationHandler {
			await processing.value
		} onCancel: {
			processing.cancel()
		}
		guard Task.isCancelled == false else { return nil }
		return HistoricalMotionBatch(
			candidates: result.recent.candidates + result.history.candidates,
			processedFrom: start,
			processedThrough: result.history.processedThrough,
			analyzer: result.history.analyzer,
			latestSampleAt: [result.recent.latestSampleAt, result.history.latestSampleAt].compactMap { $0 }.max(),
			pendingRanges: result.history.pendingRanges,
			replayCheckpoints: result.history.replayCheckpoints,
			didExpireHistory: result.history.expiredRangeCount > 0 || storedCursor < start,
			recentPending: result.recent.isComplete == false || result.history.processedThrough < end
		)
	}

	@discardableResult func commit(_ batch: HistoricalMotionBatch) -> Bool {
		guard processedThrough.map({ batch.processedThrough >= $0 }) ?? true else { return false }
		let latestSample = [lastHistorySampleAt, batch.latestSampleAt].compactMap { $0 }.max()
		let checkpoint = MotionHistoryCheckpoint(processedThrough: batch.processedThrough, analyzer: batch.analyzer,
		                                        latestSampleAt: latestSample,
		                                        pendingRanges: batch.pendingRanges,
		                                        hasExpiredHistory: hasExpiredHistory || batch.didExpireHistory,
		                                        checkedAt: lastHistoryCheckedAt, backlogPending: batch.recentPending,
		                                        replayCheckpoints: batch.replayCheckpoints,
		                                        sourceStartedAt: self.checkpoint?.sourceStartedAt)
		// Cursor and classifier state are one value: a relaunch must not lose a
		// partial or already counted smoking session from the previous batch.
		guard checkpointStore.save(checkpoint) else {
			lastError = checkpointStore.lastError
			publishStatus()
			return false
		}
		lastHistorySampleAt = checkpoint.latestSampleAt
		hasPendingHistory = batch.pendingRanges.isEmpty == false || batch.recentPending
		hasExpiredHistory = checkpoint.hasExpiredHistory ?? false
		lastError = nil
		publishStatus()
		return true
	}

	private var processedThrough: Date? {
		guard let cursor = checkpoint?.processedThrough,
		      MotionHistoryProcessor.isSupportedDate(cursor) else { return nil }
		return cursor
	}

	private var checkpoint: MotionHistoryCheckpoint? {
		checkpointStore.checkpoint
	}

	private func refreshStatus() {
		isCaptureAvailable = CMSensorRecorder.isAccelerometerRecordingAvailable()
		let armedUntil = userDefaults.object(forKey: armedUntilKey) as? Date
		let authorization = CMSensorRecorder.authorizationStatus()
		let hasPermission = authorization == .authorized
		isCaptureArmed = isCaptureAvailable && hasPermission && (armedUntil.map { $0 > Date() } ?? false)
	}

	private func scheduleRenewal(after interval: TimeInterval) {
		let now = Date()
		let preferred = now.addingTimeInterval(interval)
		let existing = userDefaults.object(forKey: scheduledRefreshKey) as? Date
		guard MotionCapturePolicy.shouldSchedule(at: now, existing: existing, preferred: preferred) else { return }
		userDefaults.set(preferred, forKey: scheduledRefreshKey)
		WKApplication.shared().scheduleBackgroundRefresh(
			withPreferredDate: preferred, userInfo: nil
		) { [weak self] error in
			guard let error else { return }
			Task { @MainActor [weak self] in
				guard let self else { return }
				if self.userDefaults.object(forKey: self.scheduledRefreshKey) as? Date == preferred {
					self.userDefaults.removeObject(forKey: self.scheduledRefreshKey)
				}
				self.lastError = error.localizedDescription
				self.publishStatus()
			}
		}
	}
}

private enum HistoricalMotionProcessor {
	nonisolated static func process(
		from start: Date,
		to end: Date,
		analyzer initialAnalyzer: RecordedMotionAnalyzer,
		pendingRanges: [MotionHistoryRange],
		replayCheckpoints: [MotionHistoryReplayCheckpoint],
		sourceStartedAt: Date?,
		sensitivity: Double,
		queryChunkDuration: TimeInterval,
		maximumProcessingTime: TimeInterval
	) -> (recent: MotionHistoryProcessor.RecentResult, history: MotionHistoryProcessor.Result) {
		let recorder = CMSensorRecorder()
		let started = ProcessInfo.processInfo.systemUptime
		let budget = max(0.5, maximumProcessingTime)
		let deadline = started + budget
		let recentDeadline = started + min(5, budget * 0.75)
		let query: (Date, Date) -> AnySequence<RecordedAccelerationSample>? = { queryStart, queryEnd in
			// A persisted repair may begin before the sensor's wall-clock cutoff.
			// Clip the native read only; the existing analyzer still sees missing
			// leading coverage and keeps its normal reconciliation/counting rules.
			guard let range = SensorHistoryQuery.range(from: queryStart, to: queryEnd),
			      let samples = recorder.accelerometerData(from: range.start, to: range.end) else { return nil }
			var iterator = NSFastEnumerationIterator(samples)
			return AnySequence { AnyIterator {
				guard let sample = iterator.next() as? CMRecordedAccelerometerData else { return nil }
				let acceleration = sample.acceleration
				return RecordedAccelerationSample(timestamp: sample.startDate, x: acceleration.x,
				                                  y: acceleration.y, z: acceleration.z)
			} }
		}
		let recent = MotionHistoryProcessor.processRecent(
			from: start, to: end, analyzer: initialAnalyzer, sourceStartedAt: sourceStartedAt, sensitivity: sensitivity, query: query,
			shouldContinue: { Task.isCancelled == false && ProcessInfo.processInfo.systemUptime < recentDeadline }
		)
		let history = MotionHistoryProcessor.process(
			from: start, to: end, analyzer: initialAnalyzer, pendingRanges: pendingRanges,
			replayCheckpoints: replayCheckpoints, sourceStartedAt: sourceStartedAt,
			sensitivity: sensitivity, queryChunkDuration: queryChunkDuration,
			query: query,
			shouldContinue: { Task.isCancelled == false && ProcessInfo.processInfo.systemUptime < deadline }
		)
		return (recent, history)
	}
}
#endif
