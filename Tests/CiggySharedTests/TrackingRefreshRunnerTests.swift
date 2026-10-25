import XCTest
@testable import CiggyShared

@MainActor
final class TrackingRefreshRunnerTests: XCTestCase {
    func testSameModeCallersShareOneOperation() async {
        let runner = TrackingRefreshRunner()
        let started = Gate(), finish = Gate()
        var operations = 0
        let first = Task { @MainActor in
            await runner.run(context: .foreground) {
                operations += 1
                started.open()
                await finish.wait()
            }
        }
        await started.wait()
        let second = Task { @MainActor in
            await runner.run(context: .foreground) { operations += 1 }
        }
        await expectLeaseCount(2, runner: runner)
        finish.open()
        await first.value
        await second.value
        XCTAssertEqual(operations, 1)
        XCTAssertEqual(runner.activeLeaseCount, 0)
    }

    func testBackgroundArrivalRetiresForegroundBeforeItsOwnBoundedOperation() async {
        let runner = TrackingRefreshRunner()
        let foregroundStarted = Gate(), retireForeground = Gate()
        let backgroundStarted = Gate(), finishBackground = Gate()
        var events: [String] = []
        var foregroundWasCancelled = false
        let foreground = Task { @MainActor in
            await runner.run(context: .foreground) {
                events.append("foreground started")
                foregroundStarted.open()
                await retireForeground.wait()
                foregroundWasCancelled = Task.isCancelled
                events.append("foreground retired")
            }
        }
        await foregroundStarted.wait()
        let background = Task { @MainActor in
            await runner.run(context: .background) {
                events.append("background started")
                backgroundStarted.open()
                await finishBackground.wait()
            }
        }
        await expectContext(.background, runner: runner)
        XCTAssertEqual(events, ["foreground started"], "Native processors must not overlap while cancellation retires")
        retireForeground.open()
        await backgroundStarted.wait()
        XCTAssertTrue(foregroundWasCancelled)
        XCTAssertEqual(events, ["foreground started", "foreground retired", "background started"])

        // Finishing the old generation must not discard this active flight.
        let joined = Task { @MainActor in
            await runner.run(context: .background) { events.append("unexpected second background operation") }
        }
        await expectLeaseCount(2, runner: runner)
        finishBackground.open()
        await foreground.value
        await background.value
        await joined.value
        XCTAssertEqual(events.count, 3)
    }

    func testCancelledForegroundCannotBeJoinedByNewBackgroundWake() async {
        let runner = TrackingRefreshRunner()
        let started = Gate(), retire = Gate()
        var backgroundRan = false
        let foreground = Task { @MainActor in
            await runner.run(context: .foreground) { started.open(); await retire.wait() }
        }
        await started.wait()
        runner.cancelForeground()
        let background = Task { @MainActor in
            await runner.run(context: .background) { backgroundRan = true }
        }
        await expectContext(.background, runner: runner)
        XCTAssertFalse(backgroundRan)
        retire.open()
        await foreground.value
        await background.value
        XCTAssertTrue(backgroundRan)
    }

    func testForegroundCancellationDoesNotCancelBackgroundGrant() async {
        let runner = TrackingRefreshRunner()
        let started = Gate(), finish = Gate()
        var backgroundWasCancelled = true
        var extraOperationRan = false
        let background = Task { @MainActor in
            await runner.run(context: .background) {
                started.open()
                await finish.wait()
                backgroundWasCancelled = Task.isCancelled
            }
        }
        await started.wait()
        let foreground = Task { @MainActor in
            await runner.run(context: .foreground) { extraOperationRan = true }
        }
        await expectLeaseCount(2, runner: runner)
        runner.cancelForeground()
        foreground.cancel()
        await expectLeaseCount(1, runner: runner)
        finish.open()
        await background.value
        await foreground.value
        XCTAssertFalse(backgroundWasCancelled)
        XCTAssertFalse(extraOperationRan)
    }

    func testOneCancelledAwaiterKeepsWorkerAliveUntilLastLeaseCancels() async {
        let runner = TrackingRefreshRunner()
        let started = Gate(), probe = Gate(), probed = Gate(), finish = Gate()
        var cancelledWithOneLease = true
        var cancelledWithNoLeases = false
        let first = Task { @MainActor in
            await runner.run(context: .background) {
                started.open()
                await probe.wait()
                cancelledWithOneLease = Task.isCancelled
                probed.open()
                await finish.wait()
                cancelledWithNoLeases = Task.isCancelled
            }
        }
        await started.wait()
        let second = Task { @MainActor in
            await runner.run(context: .background) { XCTFail("The operation should be shared") }
        }
        await expectLeaseCount(2, runner: runner)
        first.cancel()
        await expectLeaseCount(1, runner: runner)
        probe.open()
        await probed.wait()
        XCTAssertFalse(cancelledWithOneLease)
        second.cancel()
        await expectLeaseCount(0, runner: runner)
        finish.open()
        await first.value
        await second.value
        XCTAssertTrue(cancelledWithNoLeases)
    }

    func testCancelledCallerNeverStartsAnOperation() async {
        let runner = TrackingRefreshRunner()
        let enter = Gate()
        var ran = false
        let caller = Task { @MainActor in
            await enter.wait()
            await runner.run(context: .background) { ran = true }
        }
        caller.cancel()
        enter.open()
        await caller.value
        XCTAssertFalse(ran)
        XCTAssertEqual(runner.activeLeaseCount, 0)
    }

    private func expectLeaseCount(_ count: Int, runner: TrackingRefreshRunner,
                                  file: StaticString = #filePath, line: UInt = #line) async {
        // Registration/cancellation handlers are MainActor jobs with no I/O.
        // Bound scheduling turns so a regression fails instead of hanging a test.
        for _ in 0..<100 {
            if runner.activeLeaseCount == count { return }
            await Task.yield()
        }
        XCTAssertEqual(runner.activeLeaseCount, count, file: file, line: line)
    }

    private func expectContext(_ context: TrackingRefreshRunner.Context, runner: TrackingRefreshRunner,
                               file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 {
            if runner.activeContext == context { return }
            await Task.yield()
        }
        XCTAssertEqual(runner.activeContext, context, file: file, line: line)
    }

    private final class Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }
}
