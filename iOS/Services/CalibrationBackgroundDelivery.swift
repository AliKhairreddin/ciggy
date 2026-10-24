#if os(iOS)
import BackgroundTasks
import Foundation

/// Recovery for local files not yet handed to background URLSession. This is a
/// system-managed opportunity, not an exact hourly timer or a tracking wake.
@MainActor
final class CalibrationBackgroundDelivery {
    static let shared = CalibrationBackgroundDelivery()
    static let identifier = "dev.thatcanadian.ciggy.calibration.recovery"
    private var submitted = false
    private var generation = UUID()

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            Task { @MainActor in
                self.submitted = false
                let work = Task { @MainActor in
                    IOSAppRuntime.shared.start()
                    let success = await CalibrationUploadManager.shared.recoverInBackground()
                    task.setTaskCompleted(success: success)
                }
                task.expirationHandler = { work.cancel() }
            }
        }
    }

    func schedule() {
        guard !submitted else { return }
        submitted = true
        let token = generation
        BGTaskScheduler.shared.getPendingTaskRequests { [weak self] requests in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                // Replacing a persisted request on each background relaunch
                // would continually move its earliest date into the future.
                guard !requests.contains(where: { $0.identifier == Self.identifier }) else { return }
                let request = BGProcessingTaskRequest(identifier: Self.identifier)
                request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
                request.requiresNetworkConnectivity = true
                request.requiresExternalPower = false
                do { try BGTaskScheduler.shared.submit(request) }
                catch { self.submitted = false } // URLSession remains independent.
            }
        }
    }

    func cancel() {
        generation = UUID()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        submitted = false
    }
}
#endif
