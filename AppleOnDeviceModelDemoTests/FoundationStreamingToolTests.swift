import Foundation
import FoundationModels
import Testing
@testable import AppleOnDeviceModelDemo

struct FoundationStreamingToolTests {
    @Test func streamingAccumulatesExactOrderedPartialsAndSuppressesDuplicates() async throws {
        let fixture = DeterministicPartialSequence(values: [
            .success("The"),
            .success("The on-device"),
            .success("The on-device model"),
            .success("The on-device model"),
            .success("The on-device model is private."),
        ])

        let snapshots = try await FoundationStreamingCollector.collect(fixture)

        #expect(snapshots == [
            "The",
            "The on-device",
            "The on-device model",
            "The on-device model is private.",
        ])
    }

    @Test func streamingPreservesFixtureErrorsWithoutFabricatingFinalText() async {
        let fixture = DeterministicPartialSequence(values: [
            .success("Partial"),
            .failure(StreamingFixtureError.failed),
        ])

        await #expect(throws: StreamingFixtureError.failed) {
            try await FoundationStreamingCollector.collect(fixture)
        }
    }

    @Test func streamingCancellationIsPropagated() async {
        let task = Task {
            try await FoundationStreamingCollector.collect(CancellationAwareSequence())
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test @MainActor func unavailableStreamingDoesNotConstructOrRunSession() async {
        let service = StreamingServiceStub()
        service.availabilityStatus = .modelNotReady
        let model = FoundationStreamingViewModel(service: service)
        model.input = "hello"

        await model.run()

        #expect(service.streamCalls == 0)
        #expect(model.partialResponse.isEmpty)
        #expect(model.errorMessage == FoundationModelServiceError.unavailable(.modelNotReady).localizedDescription)
    }

    @Test @MainActor func availableStreamingPublishesOnlyRealPartialSnapshots() async {
        let service = StreamingServiceStub()
        service.values = ["A", "An", "An answer", "An answer"]
        let model = FoundationStreamingViewModel(service: service)
        model.input = "hello"

        await model.run()

        #expect(model.snapshots == ["A", "An", "An answer"])
        #expect(model.partialResponse == "An answer")
        #expect(model.errorMessage == nil)
    }

    @Test @MainActor func cancellingRunningViewModelWakesBlockedStreamAndKeepsLastPartial() async {
        let service = BlockingStreamingService()
        let model = FoundationStreamingViewModel(service: service, currentTime: { 10 })
        model.input = "hello"

        let runTask = Task { @MainActor in await model.run() }
        while !service.started {
            await Task.yield()
        }
        while model.partialResponse != "First partial" {
            await Task.yield()
        }

        model.cancel()
        await runTask.value

        #expect(model.partialResponse == "First partial")
        #expect(model.snapshots == ["First partial"])
        #expect(!model.isRunning)
        #expect(model.errorMessage == nil)
        #expect(model.latency == 0)
        for _ in 0..<100 where service.terminationCount == 0 {
            await Task.yield()
        }
        #expect(service.terminationCount == 1)
    }

    @Test @MainActor func streamingViewModelPublishesProducerErrorAndLatency() async {
        let service = ErrorStreamingService()
        let model = FoundationStreamingViewModel(service: service, currentTime: { 20 })
        model.input = "hello"

        await model.run()

        #expect(model.partialResponse == "Partial before failure")
        #expect(model.errorMessage == StreamingFixtureError.failed.localizedDescription)
        #expect(!model.isRunning)
        #expect(model.latency == 0)
    }

    @Test func malformedGeneratedContentDoesNotBecomeToolArguments() throws {
        let missingKeyword = GeneratedContent(properties: [:])
        let wrongKeywordType = GeneratedContent(properties: ["keyword": 42])

        #expect(throws: Error.self) {
            try LocalCapabilityTool.Arguments(missingKeyword)
        }
        #expect(throws: Error.self) {
            try LocalCapabilityTool.Arguments(wrongKeywordType)
        }
    }

    @Test func localFactToolReturnsKnownLocalValue() async throws {
        let tool = LocalCapabilityTool(values: ["speech": "SpeechAnalyzer is enabled"])

        let output = try await tool.call(arguments: .init(keyword: "speech"))

        #expect(String(describing: output).contains("SpeechAnalyzer is enabled"))
    }

    @Test func localFactToolRejectsMalformedAndUnsupportedArguments() async throws {
        let tool = LocalCapabilityTool(values: ["speech": "SpeechAnalyzer is enabled"])

        let malformed = try await tool.call(arguments: .init(keyword: "  "))
        let unsupported = try await tool.call(arguments: .init(keyword: "weather"))

        #expect(String(describing: malformed) == "Invalid capability keyword.")
        #expect(String(describing: unsupported) == "No local fact found.")
    }

    @Test @MainActor func toolSessionReceivesOnlyApprovedLocalTool() async throws {
        let session = ToolSessionStub()
        let captured = ToolCapture()
        let service = FoundationToolCallingService(
            availabilityProvider: { _ in .available },
            sessionFactory: { model, tools in
                captured.names = tools.map(\.name)
                return session
            }
        )

        _ = try await service.respond(to: "What is speech?" )

        #expect(captured.names == ["lookupCapability"])
        #expect(session.prompts == [FoundationModelPrompts.toolCalling(to: "What is speech?")])
    }

    @Test @MainActor func unavailableToolSessionDoesNotConstructSession() async {
        let sessionConstructed = LockedFlag()
        let service = FoundationToolCallingService(
            availabilityProvider: { _ in .deviceNotEligible },
            sessionFactory: { _, _ in
                sessionConstructed.value = true
                return ToolSessionStub()
            }
        )

        await #expect(throws: FoundationModelServiceError.unavailable(.deviceNotEligible)) {
            try await service.respond(to: "speech")
        }

        #expect(!sessionConstructed.value)
    }

    @Test @MainActor func toolCallingPublishesSnapshotLatencyAndCancelsOwnedTask() async {
        let session = BlockingToolSession()
        let service = FoundationToolCallingService(
            availabilityProvider: { _ in .available },
            sessionFactory: { _, _ in session }
        )
        var now = 10.0
        let model = FoundationToolCallingViewModel(service: service, currentTime: { now })
        model.input = "  speech  "
        let run = Task { @MainActor in await model.run() }

        while !session.started { await Task.yield() }
        #expect(model.inputSnapshot == "speech")
        #expect(!model.isInputEditable)
        now = 10.75
        model.cancel()
        await run.value

        #expect(model.latency == 0.75)
        #expect(model.result == nil)
        #expect(model.errorMessage == nil)
        #expect(!model.isRunning)
    }

    @Test @MainActor func staleToolResultAfterCancellationCannotOverwriteNewRun() async {
        let session = SequencedToolSession()
        let service = FoundationToolCallingService(
            availabilityProvider: { _ in .available },
            sessionFactory: { _, _ in session }
        )
        let model = FoundationToolCallingViewModel(service: service)
        model.input = "first"
        let first = Task { @MainActor in await model.run() }
        while session.startedCount < 1 { await Task.yield() }
        model.cancel()
        model.input = "second"
        let second = Task { @MainActor in await model.run() }
        while session.startedCount < 2 { await Task.yield() }
        session.release(response: "second")
        await second.value
        session.release(response: "first")
        await first.value

        #expect(model.result?.response == "second")
        #expect(model.inputSnapshot == "second")
    }
}

private struct DeterministicPartialSequence: AsyncSequence, Sendable {
    typealias Element = String
    let values: [Result<String, Error>]

    struct AsyncIterator: AsyncIteratorProtocol {
        var values: [Result<String, Error>]
        var index = 0

        mutating func next() async throws -> String? {
            guard index < values.count else { return nil }
            defer { index += 1 }
            return try values[index].get()
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(values: values) }
}

private struct CancellationAwareSequence: AsyncSequence, Sendable {
    typealias Element = String

    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async throws -> String? {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return nil
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}

private enum StreamingFixtureError: Error, Equatable { case failed }

extension StreamingFixtureError: LocalizedError {
    var errorDescription: String? { "stream fixture failed" }
}

@MainActor
private final class StreamingServiceStub: FoundationStreamingServing {
    var availabilityStatus: FoundationModelStatus = .available
    var streamCalls = 0
    var values: [String] = []

    func streamRespond(to prompt: String) -> AsyncThrowingStream<String, Error> {
        streamCalls += 1
        return AsyncThrowingStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }
}

@MainActor
private final class BlockingStreamingService: FoundationStreamingServing {
    var availabilityStatus: FoundationModelStatus = .available
    var started = false
    var terminationCount = 0

    func streamRespond(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            started = true
            continuation.yield("First partial")
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.terminationCount += 1 }
            }
        }
    }
}

@MainActor
private final class ErrorStreamingService: FoundationStreamingServing {
    var availabilityStatus: FoundationModelStatus = .available

    func streamRespond(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Partial before failure")
            continuation.finish(throwing: StreamingFixtureError.failed)
        }
    }
}

private final class ToolSessionStub: FoundationToolLanguageModelSessionServing, @unchecked Sendable {
    var prompts = [String]()
    func respond(to prompt: String) async throws -> FoundationToolResponse {
        prompts.append(prompt)
        return FoundationToolResponse(response: "local", toolWasCalled: true)
    }
}

@MainActor
private final class BlockingToolSession: FoundationToolLanguageModelSessionServing {
    var started = false
    private var continuation: CheckedContinuation<FoundationToolResponse, Error>?

    func respond(to prompt: String) async throws -> FoundationToolResponse {
        started = true
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }, onCancel: {
            Task { @MainActor in
                self.continuation?.resume(throwing: CancellationError())
                self.continuation = nil
            }
        })
    }
}

@MainActor
private final class SequencedToolSession: FoundationToolLanguageModelSessionServing {
    var startedCount = 0
    private var continuations: [CheckedContinuation<FoundationToolResponse, Never>] = []

    func respond(to prompt: String) async throws -> FoundationToolResponse {
        startedCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func release(response: String) {
        guard !continuations.isEmpty else { return }
        let continuation = continuations.removeLast()
        continuation.resume(returning: FoundationToolResponse(response: response, toolWasCalled: true))
    }
}

private final class ToolCapture: @unchecked Sendable {
    var names = [String]()
}

private final class LockedFlag: @unchecked Sendable {
    var value = false
}
