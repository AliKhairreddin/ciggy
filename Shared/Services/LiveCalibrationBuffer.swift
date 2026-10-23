import Foundation

/// Opt-in live motion complements delayed accelerometer history. Preserve gaps;
/// never manufacture samples while the Watch app is suspended.
public struct LiveCalibrationBuffer: Sendable {
    public let enabledAt: Date
    private var recording: MotionRecording?
    private var lastAcceptedAt: Date?

    public init(enabledAt: Date) { self.enabledAt = enabledAt }

    public mutating func append(_ sample: MotionSample) -> MotionRecording? {
        guard sample.isValid, MotionHistoryProcessor.isSupportedDate(sample.timestamp),
              sample.source == .liveDeviceMotion, sample.timestamp >= enabledAt else { return nil }
        if let lastAcceptedAt, sample.timestamp.timeIntervalSince(lastAcceptedAt) < 0.1 - 0.000_001 { return nil }
        var completed: MotionRecording?
        if let current = recording,
           sample.timestamp.timeIntervalSince(current.startedAt) >= 300 || current.samples.count >= 3_000 {
            completed = flush()
        }
        if recording == nil { recording = MotionRecording(label: .unlabelled, startedAt: sample.timestamp) }
        recording?.samples.append(sample)
        lastAcceptedAt = sample.timestamp
        return completed
    }

    public mutating func flush() -> MotionRecording? {
        guard var current = recording, let last = current.samples.last else { return nil }
        current.endedAt = last.timestamp
        recording = nil
        return current
    }
}
