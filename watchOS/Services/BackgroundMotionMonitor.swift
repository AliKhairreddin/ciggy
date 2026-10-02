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
}

private struct MotionHistoryCheckpoint: Codable {
	let processedThrough: Date
	let analyzer: RecordedMotionAnalyzer
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
	private let checkpointKey = "BackgroundMotionMonitor.checkpoint.v2"
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
		if processedThrough == nil { userDefaults.set(now, forKey: cursorKey) }
		recorder.recordAccelerometer(forDuration: captureDuration)
		userDefaults.set(now.addingTimeInterval(captureDuration), forKey: armedUntilKey)
		// The first call can still be awaiting the system permission prompt.
		isCaptureArmed = CMSensorRecorder.authorizationStatus() == .authorized
		lastError = nil
		scheduleRenewal(after: renewalInterval)
	}

	/// Reads samples old enough to be available from Core Motion and returns all probable
	/// sessions. The caller persists the candidates before committing `processedThrough`.
	func processAvailableHistory(sensitivity: Double) async -> HistoricalMotionBatch? {
		refreshStatus()
		guard isCaptureAvailable, isProcessingHistory == false else { return nil }
		guard CMSensorRecorder.authorizationStatus() == .authorized else { return nil }
		guard let storedCursor = processedThrough else { return nil }

		let end = Date().addingTimeInterval(-availabilityDelay)
		let start = max(storedCursor, end.addingTimeInterval(-retentionDuration))
		guard start < end else { return nil }

		isProcessingHistory = true
		defer { isProcessingHistory = false }
		let queryChunkDuration = self.queryChunkDuration
		var analyzer = checkpoint?.analyzer ?? RecordedMotionAnalyzer(sensitivity: sensitivity)
		analyzer.updateSensitivity(sensitivity)
		let initialAnalyzer = analyzer
		let result = await Task.detached(priority: .utility) {
			HistoricalMotionProcessor.process(
				from: start,
				to: end,
				analyzer: initialAnalyzer,
				queryChunkDuration: queryChunkDuration
			)
		}.value
		return HistoricalMotionBatch(
			candidates: result.candidates,
			processedFrom: start,
			processedThrough: end,
			analyzer: result.analyzer
		)
	}

	func commit(_ batch: HistoricalMotionBatch) {
		guard processedThrough.map({ batch.processedThrough >= $0 }) ?? true else { return }
		let checkpoint = MotionHistoryCheckpoint(processedThrough: batch.processedThrough, analyzer: batch.analyzer)
		// Cursor and classifier state are one value: a relaunch must not lose a
		// partial smoking session or the cooldown established in the previous batch.
		guard let data = try? JSONEncoder().encode(checkpoint) else { return }
		userDefaults.set(data, forKey: checkpointKey)
	}

	private var processedThrough: Date? {
		checkpoint?.processedThrough ?? userDefaults.object(forKey: cursorKey) as? Date
	}

	private var checkpoint: MotionHistoryCheckpoint? {
		guard let data = userDefaults.data(forKey: checkpointKey) else { return nil }
		return try? JSONDecoder().decode(MotionHistoryCheckpoint.self, from: data)
	}

	private func refreshStatus() {
		isCaptureAvailable = CMSensorRecorder.isAccelerometerRecordingAvailable()
		let armedUntil = userDefaults.object(forKey: armedUntilKey) as? Date
		let authorization = CMSensorRecorder.authorizationStatus()
		let hasPermission = authorization == .authorized
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
	struct Result: Sendable {
		let candidates: [DetectionCandidate]
		let analyzer: RecordedMotionAnalyzer
	}
	nonisolated static func process(
		from start: Date,
		to end: Date,
		analyzer initialAnalyzer: RecordedMotionAnalyzer,
		queryChunkDuration: TimeInterval
	) -> Result {
		let recorder = CMSensorRecorder()
		var analyzer = initialAnalyzer
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

		return Result(candidates: candidates, analyzer: analyzer)
	}
}
#endif
