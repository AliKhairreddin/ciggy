import Foundation

/// Coalesces refresh callers while keeping native history processors serialized.
/// Operations must cooperate with cancellation so a retired scan can finish promptly.
@MainActor
public final class TrackingRefreshRunner {
    public enum Context: Sendable { case foreground, background }

    private struct Flight {
        let id: UUID
        let context: Context
        let task: Task<Void, Never>
        var leases: [UUID: Context]
    }
    private var flight: Flight?
    // Internal diagnostics let concurrency tests synchronize on actual registration.
    var activeLeaseCount: Int { flight?.leases.count ?? 0 }
    var activeContext: Context? { flight?.context }

    public init() {}

    public func run(context: Context, operation: @escaping @MainActor () async -> Void) async {
        let leaseID = UUID()
        await withTaskCancellationHandler {
            guard Task.isCancelled == false else { return }
            let task = register(leaseID, context: context, operation: operation)
            await task.value
            removeLease(leaseID)
        } onCancel: {
            Task { @MainActor [weak self] in self?.removeLease(leaseID) }
        }
    }

    /// Screen sleep retires foreground work, but cannot revoke a background grant.
    public func cancelForeground() {
        guard var current = flight else { return }
        current.leases = current.leases.filter { $0.value != .foreground }
        flight = current
        if current.leases.isEmpty { current.task.cancel() }
    }

    private func register(_ leaseID: UUID, context: Context,
                          operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        if var current = flight, current.task.isCancelled == false,
           !(context == .background && current.context == .foreground) {
            current.leases[leaseID] = context
            flight = current
            return current.task
        }

        // A background grant needs its own bounded operation, never a foreground
        // scan's longer budget. Cancel old work but await its retirement first.
        let predecessor = flight?.task
        predecessor?.cancel()
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.finished(id) }
            if let predecessor { await predecessor.value }
            guard Task.isCancelled == false else { return }
            await operation()
        }
        flight = Flight(id: id, context: context, task: task, leases: [leaseID: context])
        return task
    }

    private func removeLease(_ leaseID: UUID) {
        guard var current = flight, current.leases.removeValue(forKey: leaseID) != nil else { return }
        flight = current
        if current.leases.isEmpty { current.task.cancel() }
    }

    private func finished(_ id: UUID) {
        // A retiring predecessor must not clear the replacement waiting for it.
        if flight?.id == id { flight = nil }
    }
}
