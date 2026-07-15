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
}

/// Arms watchOS historical accelerometer capture and analyzes the recorded backlog when
/// Ciggy next becomes active. `CMSensorRecorder` continues collecting while the app is
/// suspended or terminated; analysis itself happens only when the app has runtime.
@MainActor
final class BackgroundMotionMonitor: ObservableObject {
	static let shared = BackgroundMotionMonitor()

	@Published private(set) var isCaptureAvailable = false
	@Published private(set) var isCaptureArmed = false
	@Published private(set) var isProcessingHistory = false
	@Published private(set) var lastError: String?

	private let recorder = CMSensorRecorder()
	private let userDefaults: UserDefaults
	private let cursorKey = "BackgroundMotionMonitor.processedThrough.v1"
	private let armedUntilKey = "BackgroundMotionMonitor.armedUntil.v1"
	private let captureDuration: TimeInterval = 12 * 60 * 60
	private let renewalInterval: TimeInterval = 10 * 60 * 60
	private let availabilityDelay: TimeInterval = 3 * 60
	private let retentionDuration: TimeInterval = 3 * 24 * 60 * 60
	private let queryChunkDuration: TimeInterval = (12 * 60 * 60) - 1

	private init(userDefaults: UserDefaults = .standard) {
		self.userDefaults = userDefaults
		refreshStatus()
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
		guard isCaptureAvailable else { return }

		let authorization = CMSensorRecorder.authorizationStatus()
		guard authorization != .denied, authorization != .restricted else {
			isCaptureArmed = false
			lastError = "Motion access is disabled in Settings."
			return
		}

		let now = Date()
		if processedThrough == nil {
			advanceCursor(to: now)
		}
		recorder.recordAccelerometer(forDuration: captureDuration)
		userDefaults.set(now.addingTimeInterval(captureDuration), forKey: armedUntilKey)
		isCaptureArmed = true
		lastError = nil
		scheduleRenewal(after: renewalInterval)
	}

	/// Advances the history cursor past time already handled by live foreground motion.
	func markForegroundProcessed(through date: Date = Date()) {
		advanceCursor(to: date)
	}

	/// Reads samples old enough to be available from Core Motion and returns all probable
	/// sessions. The caller persists the candidates before committing `processedThrough`.
	func processAvailableHistory(sensitivity: Double) async -> HistoricalMotionBatch? {
		guard isCaptureAvailable, isProcessingHistory == false else { return nil }
		guard CMSensorRecorder.authorizationStatus() == .authorized else { return nil }
		guard let storedCursor = processedThrough else { return nil }

		let end = Date().addingTimeInterval(-availabilityDelay)
		let start = max(storedCursor, end.addingTimeInterval(-retentionDuration))
		guard start < end else { return nil }

		isProcessingHistory = true
		defer { isProcessingHistory = false }
		let queryChunkDuration = self.queryChunkDuration
		let candidates = await Task.detached(priority: .utility) {
			HistoricalMotionProcessor.process(
				from: start,
				to: end,
				sensitivity: sensitivity,
				queryChunkDuration: queryChunkDuration
			)
		}.value
		return HistoricalMotionBatch(
			candidates: candidates,
			processedFrom: start,
			processedThrough: end
		)
	}

	func commit(_ batch: HistoricalMotionBatch) {
		advanceCursor(to: batch.processedThrough)
	}

	private var processedThrough: Date? {
		userDefaults.object(forKey: cursorKey) as? Date
	}

	private func advanceCursor(to date: Date) {
		guard processedThrough.map({ date > $0 }) ?? true else { return }
		userDefaults.set(date, forKey: cursorKey)
	}

	private func refreshStatus() {
		isCaptureAvailable = CMSensorRecorder.isAccelerometerRecordingAvailable()
		let armedUntil = userDefaults.object(forKey: armedUntilKey) as? Date
		let authorization = CMSensorRecorder.authorizationStatus()
		let hasPermission = authorization != .denied && authorization != .restricted
		isCaptureArmed = isCaptureAvailable && hasPermission && (armedUntil.map { $0 > Date() } ?? false)
	}

	private func scheduleRenewal(after interval: TimeInterval) {
		WKApplication.shared().scheduleBackgroundRefresh(
			withPreferredDate: Date().addingTimeInterval(interval),
			userInfo: nil
		) { [weak self] error in
			guard let error else { return }
			Task { @MainActor [weak self] in
				self?.lastError = error.localizedDescription
			}
		}
	}
}

private enum HistoricalMotionProcessor {
	nonisolated static func process(
		from start: Date,
		to end: Date,
		sensitivity: Double,
		queryChunkDuration: TimeInterval
	) -> [DetectionCandidate] {
		let recorder = CMSensorRecorder()
		var analyzer = RecordedMotionAnalyzer(sensitivity: sensitivity)
		var candidates: [DetectionCandidate] = []
		var queryStart = start

		while queryStart < end {
			let queryEnd = min(queryStart.addingTimeInterval(queryChunkDuration), end)
			if let samples = recorder.accelerometerData(from: queryStart, to: queryEnd) {
				var iterator = NSFastEnumerationIterator(samples)
				while let sample = iterator.next() as? CMRecordedAccelerometerData {
					let acceleration = sample.acceleration
					if let candidate = analyzer.record(
						.init(
							timestamp: sample.startDate,
							x: acceleration.x,
							y: acceleration.y,
							z: acceleration.z
						)
					) {
						candidates.append(candidate)
					}
				}
			}
			queryStart = queryEnd
		}

		return candidates
	}
}
#endif
