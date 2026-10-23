#if os(watchOS)
import CiggyShared
import Combine
import Foundation

/// Captures already-running live sensors only after consent. The background
/// history collector remains responsible for periods without foreground sensors.
@MainActor
final class LiveCalibrationCollector {
    static let shared = LiveCalibrationCollector()
    private var buffer: LiveCalibrationBuffer?
    private var subscription: AnyCancellable?
    private var writer: Task<Void, Never>?

    private init() {
        subscription = MotionManager.shared.samplePublisher.sink { @MainActor [weak self] sample in
            guard let self, let consent = self.buffer?.enabledAt else { return }
            if let recording = self.buffer?.append(sample) { self.queue(recording, consent: consent) }
        }
    }

    func configure(consent: Date?) {
        guard let consent else { buffer = nil; writer?.cancel(); writer = nil; return }
        guard buffer?.enabledAt != consent else { return }
        buffer = LiveCalibrationBuffer(enabledAt: consent)
    }

    private func queue(_ recording: MotionRecording, consent: Date) {
        let previous = writer
        writer = Task { @MainActor in
            await previous?.value
            guard Task.isCancelled == false else { return }
            await BackgroundCalibrationCollector.shared.enqueueLive(recording, consent: consent)
        }
    }

    func flush() async {
        if let consent = buffer?.enabledAt, let recording = buffer?.flush() { queue(recording, consent: consent) }
        await writer?.value
    }
}
#endif
