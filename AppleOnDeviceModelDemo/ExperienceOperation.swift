import Foundation
import Combine

@MainActor
final class ExperienceOperation<Output>: ObservableObject {
    @Published private(set) var output: Output?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false

    private let clock: () -> TimeInterval

    init(clock: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }) {
        self.clock = clock
    }

    func run(_ work: () async throws -> Output) async {
        guard !isRunning else { return }

        output = nil
        errorMessage = nil
        latency = nil
        isRunning = true
        let start = clock()

        defer {
            latency = clock() - start
            isRunning = false
        }

        do {
            output = try await work()
        } catch is CancellationError {
            // Cancellation is an expected terminal state, not a failure.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
