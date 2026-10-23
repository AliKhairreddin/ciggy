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
	let didExpireHistory: Bool
	let recentPending: Bool
}

private struct MotionHistoryCheckpoint: Codable {
	let processedThrough: Date
	let analyzer: RecordedMotionAnalyzer
	// Optional fields preserve checkpoints written before reconciliation existed.
	let latestSampleAt: Date?
	let pendingRanges: [MotionHistoryRange]?
	let hasExpiredHistory: Bool?
	let checkedAt: Date?
	let backlogPending: Bool?
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
	@Published private(set) var lastHistorySampleAt: Date?
	@Published private(set) var lastHistoryCheckedAt: Date?
	@Published private(set) var hasPendingHistory = false
	@Published private(set) var hasExpiredHistory = false

	private let recorder = CMSensorRecorder()
	private let userDefaults: UserDefaults
	private let cursorKey = "BackgroundMotionMonitor.processedThrough.v1"
	private let checkpointKey = "BackgroundMotionMonitor.checkpoint.v2"
	private let armedUntilKey = "BackgroundMotionMonitor.armedUntil.v1"
	private let scheduledRefreshKey = "BackgroundMotionMonitor.scheduledRefresh.v1"
	private let captureDuration: TimeInterval = 12 * 60 * 60
	// A refresh also analyzes the backlog. watchOS decides when it actually runs.
	private let renewalInterval: TimeInterval = 30 * 60
	private let availabilityDelay: TimeInterval = 3 * 60
	private let retentionDuration: TimeInterval = 3 * 24 * 60 * 60
	private let queryChunkDuration: TimeInterval = 30 * 60

	private init(userDefaults: UserDefaults = .standard) {
		self.userDefaults = userDefaults
		lastHistorySampleAt = checkpoint?.latestSampleAt
		lastHistoryCheckedAt = checkpoint?.checkedAt
		hasPendingHistory = checkpoint?.pendingRanges?.isEmpty == false || checkpoint?.backlogPending == true
		hasExpiredHistory = checkpoint?.hasExpiredHistory ?? false
		refreshStatus()
	}

	var statusDetail: String {
		if let lastError { return lastError }
		if hasPendingHistory { return "Some motion history is unavailable. Ciggy retries it while watchOS retains the recording; recent available activity still updates." }
		if hasExpiredHistory { return "Some older motion history expired before it could be checked, so past totals may be incomplete. Recent available activity still updates." }
		if isCaptureAvailable == false { return "Automatic detection needs a physical Apple Watch with motion access." }
		if isCaptureArmed == false { return "Open Ciggy and allow Motion & Fitness access to start background capture." }
		return "Motion estimates can appear a few minutes later. Keep a Ciggy complication on your active Watch face to give background checks more opportunities; watchOS controls their timing."
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
		if processedThrough == nil { userDefaults.set(now, forKey: cursorKey) }
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

	func publishStatus() {
		let status = TrackingStatus(
			historyCheckedAt: lastHistoryCheckedAt,
			historySampleAt: lastHistorySampleAt,
			captureUntil: userDefaults.object(forKey: armedUntilKey) as? Date,
			pendingHistory: hasPendingHistory,
			expiredHistory: hasExpiredHistory,
			captureAvailable: isCaptureAvailable,
			permissionGranted: CMSensorRecorder.authorizationStatus() == .authorized,
			lastError: lastError,
			isProcessing: isProcessingHistory
		)
		TrackingStatusStore.shared.receive(status)
		ConnectivityManager.shared.send(trackingStatus: status)
	}

	/// Reads samples old enough to be available from Core Motion and returns all probable
	/// sessions. The caller persists the candidates before committing `processedThrough`.
	func processAvailableHistory(sensitivity: Double, maximumProcessingTime: TimeInterval = 20) async -> HistoricalMotionBatch? {
		refreshStatus()
		guard isCaptureAvailable, isProcessingHistory == false else { return nil }
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
		let processing = Task.detached(priority: .utility) {
			HistoricalMotionProcessor.process(
				from: start,
				to: end,
				analyzer: initialAnalyzer,
				pendingRanges: pendingRanges,
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
			didExpireHistory: result.history.expiredRangeCount > 0 || storedCursor < start,
			recentPending: result.recent.isComplete == false || result.history.processedThrough < end
		)
	}

	func commit(_ batch: HistoricalMotionBatch) {
		guard processedThrough.map({ batch.processedThrough >= $0 }) ?? true else { return }
		let latestSample = [lastHistorySampleAt, batch.latestSampleAt].compactMap { $0 }.max()
		let checkpoint = MotionHistoryCheckpoint(processedThrough: batch.processedThrough, analyzer: batch.analyzer,
		                                        latestSampleAt: latestSample,
		                                        pendingRanges: batch.pendingRanges,
		                                        hasExpiredHistory: hasExpiredHistory || batch.didExpireHistory,
		                                        checkedAt: lastHistoryCheckedAt, backlogPending: batch.recentPending)
		// Cursor and classifier state are one value: a relaunch must not lose a
		// partial smoking session or the cooldown established in the previous batch.
		guard let data = try? JSONEncoder().encode(checkpoint) else { return }
		userDefaults.set(data, forKey: checkpointKey)
		lastHistorySampleAt = checkpoint.latestSampleAt
		hasPendingHistory = batch.pendingRanges.isEmpty == false || batch.recentPending
		hasExpiredHistory = checkpoint.hasExpiredHistory ?? false
		publishStatus()
	}

	private var processedThrough: Date? {
		guard let cursor = checkpoint?.processedThrough ?? userDefaults.object(forKey: cursorKey) as? Date,
		      MotionHistoryProcessor.isSupportedDate(cursor) else { return nil }
		return cursor
	}

	private var checkpoint: MotionHistoryCheckpoint? {
		guard let data = userDefaults.data(forKey: checkpointKey) else { return nil }
		guard let checkpoint = try? JSONDecoder().decode(MotionHistoryCheckpoint.self, from: data),
		      MotionHistoryProcessor.isSupportedDate(checkpoint.processedThrough) else { return nil }
		return checkpoint
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
			guard let samples = recorder.accelerometerData(from: queryStart, to: queryEnd) else { return nil }
			var iterator = NSFastEnumerationIterator(samples)
			return AnySequence { AnyIterator {
				guard let sample = iterator.next() as? CMRecordedAccelerometerData else { return nil }
				let acceleration = sample.acceleration
				return RecordedAccelerationSample(timestamp: sample.startDate, x: acceleration.x,
				                                  y: acceleration.y, z: acceleration.z)
			} }
		}
		let recent = MotionHistoryProcessor.processRecent(
			from: start, to: end, sensitivity: sensitivity, query: query,
			shouldContinue: { Task.isCancelled == false && ProcessInfo.processInfo.systemUptime < recentDeadline }
		)
		let history = MotionHistoryProcessor.process(
			from: start, to: end, analyzer: initialAnalyzer, pendingRanges: pendingRanges,
			sensitivity: sensitivity, queryChunkDuration: queryChunkDuration,
			query: query,
			shouldContinue: { Task.isCancelled == false && ProcessInfo.processInfo.systemUptime < deadline }
		)
		return (recent, history)
	}
}
#endif
