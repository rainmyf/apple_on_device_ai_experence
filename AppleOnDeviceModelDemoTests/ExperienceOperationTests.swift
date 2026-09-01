import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

@MainActor
struct ExperienceOperationTests {
    @Test(arguments: TerminalState.allCases)
    func operationTransitionsFromIdleToExpectedTerminalState(_ state: TerminalState) async {
        var times = [10.0, 10.5].makeIterator()
        let operation = ExperienceOperation<String>(clock: { times.next()! })

        #expect(operation.output == nil)
        #expect(operation.latency == nil)
        #expect(operation.errorMessage == nil)
        #expect(!operation.isRunning)

        switch state {
        case .success:
            await operation.run { "done" }
            #expect(operation.output == "done")
            #expect(operation.errorMessage == nil)
        case .failure:
            await operation.run { throw TestOperationError.failed }
            #expect(operation.output == nil)
            #expect(operation.errorMessage == TestOperationError.failed.localizedDescription)
        case .cancellation:
            await operation.run { throw CancellationError() }
            #expect(operation.output == nil)
            #expect(operation.errorMessage == nil)
        }

        #expect(operation.latency == 0.5)
        #expect(!operation.isRunning)
    }

    @Test func loadingStateRemainsUntilWorkCompletes() async {
        var release: (() -> Void)?
        let operation = ExperienceOperation<String>(clock: { 10 })
        let task = Task {
            await operation.run {
                return await withCheckedContinuation { continuation in
                    release = { continuation.resume(returning: "done") }
                }
            }
        }

        while release == nil {
            await Task.yield()
        }

        #expect(operation.isRunning)
        #expect(operation.output == nil)
        #expect(operation.latency == nil)
        #expect(operation.errorMessage == nil)

        release?()
        await task.value
        #expect(!operation.isRunning)
        #expect(operation.output == "done")
    }

    @Test func startingAnotherAttemptClearsStaleStateWhileLoading() async {
        var times = [10.0, 10.2, 20.0, 20.4].makeIterator()
        let operation = ExperienceOperation<String>(clock: { times.next()! })
        await operation.run { "old result" }

        var release: (() -> Void)?
        let task = Task {
            await operation.run {
                return await withCheckedContinuation { continuation in
                    release = { continuation.resume(returning: "new result") }
                }
            }
        }
        while release == nil {
            await Task.yield()
        }

        #expect(operation.isRunning)
        #expect(operation.output == nil)
        #expect(operation.latency == nil)
        #expect(operation.errorMessage == nil)

        release?()
        await task.value
        #expect(operation.output == "new result")
    }

    @Test func duplicateRunsAreSuppressedWithoutClearingLoadingState() async {
        var release: (() -> Void)?
        var workCalls = 0
        var clockCalls = 0
        let operation = ExperienceOperation<String>(clock: {
            clockCalls += 1
            return clockCalls == 1 ? 10 : 10.5
        })
        let firstTask = Task {
            await operation.run {
                workCalls += 1
                return await withCheckedContinuation { continuation in
                    release = { continuation.resume(returning: "first") }
                }
            }
        }

        while release == nil {
            await Task.yield()
        }
        await operation.run {
            workCalls += 1
            return "duplicate"
        }

        #expect(operation.isRunning)
        #expect(workCalls == 1)
        #expect(clockCalls == 1)
        #expect(operation.output == nil)

        release?()
        await firstTask.value
        #expect(operation.output == "first")
        #expect(clockCalls == 2)
    }

    @Test func operationPublishesResultAndLatency() async {
        var times = [10.0, 10.8].makeIterator()
        let operation = ExperienceOperation<String>(clock: { times.next()! })

        await operation.run { "local result" }

        #expect(operation.output == "local result")
        #expect(abs((operation.latency ?? .nan) - 0.8) < 0.000_001)
        #expect(!operation.isRunning)
        #expect(operation.errorMessage == nil)
    }

    @Test func idleStateStartsEmpty() {
        let operation = ExperienceOperation<String>(clock: { 10 })

        #expect(operation.output == nil)
        #expect(operation.latency == nil)
        #expect(operation.errorMessage == nil)
        #expect(!operation.isRunning)
    }

    @Test func aNewAttemptClearsStaleResultAndError() async {
        var times = [10.0, 10.4, 20.0, 20.6].makeIterator()
        let operation = ExperienceOperation<String>(clock: { times.next()! })

        await operation.run { "old result" }
        await operation.run { throw TestOperationError.failed }

        #expect(operation.output == nil)
        #expect(abs((operation.latency ?? .nan) - 0.6) < 0.000_001)
        #expect(operation.errorMessage == TestOperationError.failed.localizedDescription)
        #expect(!operation.isRunning)
    }

    @Test func secondAttemptClearsPreviousErrorBeforeLoadingCompletes() async {
        let operation = ExperienceOperation<String>(clock: { 10 })
        await operation.run { throw TestOperationError.failed }
        #expect(operation.errorMessage == TestOperationError.failed.localizedDescription)

        var release: (() -> Void)?
        let task = Task {
            await operation.run {
                await withCheckedContinuation { continuation in
                    release = { continuation.resume(returning: "recovered") }
                }
            }
        }
        while release == nil {
            await Task.yield()
        }

        #expect(operation.isRunning)
        #expect(operation.errorMessage == nil)
        release?()
        await task.value
        #expect(operation.output == "recovered")
    }

    @Test func cancellationIsNotPublishedAsFailure() async {
        var times = [10.0, 10.5].makeIterator()
        let operation = ExperienceOperation<String>(clock: { times.next()! })

        let task = Task {
            await operation.run {
                try Task.checkCancellation()
                return "unreachable"
            }
        }
        task.cancel()
        await task.value

        #expect(operation.output == nil)
        #expect(operation.errorMessage == nil)
        #expect(operation.latency == 0.5)
        #expect(!operation.isRunning)
    }
}

private enum TestOperationError: LocalizedError {
    case failed

    var errorDescription: String? { "operation failed" }
}

enum TerminalState: CaseIterable {
    case success
    case failure
    case cancellation
}
