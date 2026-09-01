import Combine
import Foundation
import FoundationModels
import SwiftUI

#if targetEnvironment(simulator)
// FoundationModels' external macro server is not available in the generic
// simulator toolchain. Keep the simulator's test representation honest and
// compile the public macro-backed schema for device builds below.
struct GuidedTextAnalysis: Equatable, Sendable, Generable {
    var intent: String
    var entities: [String]
    var summary: String

    init(intent: String, entities: [String], summary: String) {
        self.intent = intent; self.entities = entities; self.summary = summary
    }
    static var generationSchema: GenerationSchema { GeneratedContent.generationSchema }
    init(_ content: GeneratedContent) throws {
        intent = try content.value(forProperty: "intent")
        entities = try content.value(forProperty: "entities")
        summary = try content.value(forProperty: "summary")
    }
    var generatedContent: GeneratedContent {
        GeneratedContent(properties: ["intent": intent, "entities": entities, "summary": summary])
    }
}

struct ContentTags: Equatable, Sendable, Generable {
    var topics: [String]
    var entities: [String]
    var actions: [String]
    var emotions: [String]

    init(topics: [String], entities: [String], actions: [String], emotions: [String]) {
        self.topics = topics; self.entities = entities; self.actions = actions; self.emotions = emotions
    }
    static var generationSchema: GenerationSchema { GeneratedContent.generationSchema }
    init(_ content: GeneratedContent) throws {
        topics = try content.value(forProperty: "topics")
        entities = try content.value(forProperty: "entities")
        actions = try content.value(forProperty: "actions")
        emotions = try content.value(forProperty: "emotions")
    }
    var generatedContent: GeneratedContent {
        GeneratedContent(properties: ["topics": topics, "entities": entities, "actions": actions, "emotions": emotions])
    }
}
#else
@Generable
struct GuidedTextAnalysis: Equatable, Sendable {
    @Guide(description: "Primary intent") var intent: String
    @Guide(description: "Important entities", .maximumCount(5)) var entities: [String]
    @Guide(description: "Summary under 30 words") var summary: String
}

@Generable
struct ContentTags: Equatable, Sendable {
    @Guide(.maximumCount(5)) var topics: [String]
    @Guide(.maximumCount(5)) var entities: [String]
    @Guide(.maximumCount(3)) var actions: [String]
    @Guide(.maximumCount(3)) var emotions: [String]
}
#endif

enum FoundationModelPrompts {
    static func respond(to input: String) -> String {
        "Please respond clearly and concisely to the following request:\n\n\(input.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func analyze(to input: String) -> String {
        "Analyze the following text and return the primary intent, important entities, and a summary under 30 words:\n\n\(input.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func tag(to input: String) -> String {
        "Identify topics, entities, actions, and emotions in the following text:\n\n\(input.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func streaming(to input: String) -> String {
        "Respond incrementally and concisely to the following request:\n\n\(input.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func toolCalling(to input: String) -> String {
        "Answer using the local capability lookup tool when a bundled fact is needed. Never invent a fact:\n\n\(input.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

/// Stores only snapshots actually emitted by a model stream. A repeated
/// snapshot is ignored; no final response is inferred when a stream finishes.
struct FoundationStreamingAccumulator: Sendable {
    private(set) var latest = ""
    private var emitted = Set<String>()

    mutating func consume(_ partial: String) -> String? {
        guard !partial.isEmpty, !emitted.contains(partial) else { return nil }
        emitted.insert(partial)
        latest = partial
        return partial
    }
}

enum FoundationStreamingCollector {
    static func collect<S: AsyncSequence>(_ sequence: S) async throws -> [String]
    where S.Element == String {
        var accumulator = FoundationStreamingAccumulator()
        var snapshots = [String]()
        for try await partial in sequence {
            try Task.checkCancellation()
            if let snapshot = accumulator.consume(partial) {
                snapshots.append(snapshot)
            }
        }
        return snapshots
    }
}

@MainActor
protocol FoundationStreamingServing: AnyObject {
    var availabilityStatus: FoundationModelStatus { get }
    func streamRespond(to prompt: String) -> AsyncThrowingStream<String, Error>
}

private final class FoundationStreamingSessionAdapter: FoundationStreamingServing {
    private let model: SystemLanguageModel
    private let availabilityProvider: @Sendable (SystemLanguageModel) -> FoundationModelStatus

    init(
        model: SystemLanguageModel,
        availabilityProvider: @escaping @Sendable (SystemLanguageModel) -> FoundationModelStatus
    ) {
        self.model = model
        self.availabilityProvider = availabilityProvider
    }

    var availabilityStatus: FoundationModelStatus { availabilityProvider(model) }

    func streamRespond(to prompt: String) -> AsyncThrowingStream<String, Error> {
        let session = LanguageModelSession(model: model)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: prompt) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
final class FoundationStreamingViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var partialResponse = ""
    @Published private(set) var snapshots = [String]()
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var latency: TimeInterval?

    let service: any FoundationStreamingServing
    private let currentTime: () -> TimeInterval
    private var streamTask: Task<Void, Never>?

    init(
        service: any FoundationStreamingServing = FoundationStreamingSessionAdapter(
            model: .default,
            availabilityProvider: { FoundationModelService.status(for: $0.availability) }
        ),
        currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    ) {
        self.service = service
        self.currentTime = currentTime
    }

    var availabilityStatus: FoundationModelStatus { service.availabilityStatus }
    var canRun: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            availabilityStatus == .available && !isRunning
    }

    func run() async {
        guard !isRunning else { return }
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            errorMessage = FoundationModelServiceError.emptyInput.localizedDescription
            return
        }
        guard availabilityStatus == .available else {
            errorMessage = FoundationModelServiceError.unavailable(availabilityStatus).localizedDescription
            return
        }

        partialResponse = ""
        snapshots = []
        errorMessage = nil
        latency = nil
        isRunning = true
        let startedAt = currentTime()
        defer {
            streamTask = nil
            latency = currentTime() - startedAt
            isRunning = false
        }

        let stream = service.streamRespond(to: FoundationModelPrompts.streaming(to: request))
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.consume(stream)
        }
        streamTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() {
        streamTask?.cancel()
    }

    private func consume(_ stream: AsyncThrowingStream<String, Error>) async {
        do {
            var accumulator = FoundationStreamingAccumulator()
            for try await partial in stream {
                try Task.checkCancellation()
                if let snapshot = accumulator.consume(partial) {
                    snapshots.append(snapshot)
                    partialResponse = snapshot
                }
            }
        } catch is CancellationError {
            // Cancellation keeps the last real partial visible and is not an error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FoundationToolResponse: Equatable, Sendable {
    let response: String
    let toolWasCalled: Bool
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct LocalCapabilityTool: Tool {
    let name = "lookupCapability"
    let description = "Looks up a fixed fact bundled in this demo. It never uses a network."
    let values: [String: String]

#if targetEnvironment(simulator)
    struct Arguments: Equatable, Sendable, Generable {
        var keyword: String

        init(keyword: String) { self.keyword = keyword }
        static var generationSchema: GenerationSchema { GeneratedContent.generationSchema }
        init(_ content: GeneratedContent) throws { keyword = try content.value(forProperty: "keyword") }
        var generatedContent: GeneratedContent { GeneratedContent(properties: ["keyword": keyword]) }
    }
#else
    @Generable
    struct Arguments: Equatable, Sendable {
        var keyword: String
    }
#endif

    func call(arguments: Arguments) async throws -> String {
        let keyword = arguments.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return "Invalid capability keyword." }
        return values[keyword] ?? "No local fact found."
    }
}

protocol FoundationToolLanguageModelSessionServing: AnyObject {
    func respond(to prompt: String) async throws -> FoundationToolResponse
}

private final class FoundationToolLanguageModelSessionAdapter: FoundationToolLanguageModelSessionServing, Sendable {
    private let session: LanguageModelSession

    init(model: SystemLanguageModel, tools: [any Tool]) {
        session = LanguageModelSession(model: model, tools: tools)
    }

    func respond(to prompt: String) async throws -> FoundationToolResponse {
        let response = try await session.respond(to: prompt).content
        let toolWasCalled = session.transcript.contains { entry in
            if case .toolCalls = entry { return true }
            return false
        }
        return FoundationToolResponse(response: response, toolWasCalled: toolWasCalled)
    }
}

final class FoundationToolCallingService: Sendable {
    typealias SessionFactory = @Sendable (SystemLanguageModel, [any Tool]) -> any FoundationToolLanguageModelSessionServing

    private let model: SystemLanguageModel
    private let sessionFactory: SessionFactory
    private let availabilityProvider: @Sendable (SystemLanguageModel) -> FoundationModelStatus

    init(
        model: SystemLanguageModel = .default,
        availabilityProvider: @escaping @Sendable (SystemLanguageModel) -> FoundationModelStatus = { FoundationModelService.status(for: $0.availability) },
        sessionFactory: @escaping SessionFactory = { model, tools in
            FoundationToolLanguageModelSessionAdapter(model: model, tools: tools)
        }
    ) {
        self.model = model
        self.availabilityProvider = availabilityProvider
        self.sessionFactory = sessionFactory
    }

    var availabilityStatus: FoundationModelStatus { availabilityProvider(model) }

    func respond(to input: String) async throws -> FoundationToolResponse {
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { throw FoundationModelServiceError.emptyInput }
        let status = availabilityProvider(model)
        guard status == .available else { throw FoundationModelServiceError.unavailable(status) }

        let tool = LocalCapabilityTool(values: Self.defaultValues)
        let session = sessionFactory(model, [tool])
        return try await session.respond(to: FoundationModelPrompts.toolCalling(to: request))
    }

    static let defaultValues = [
        "speech": "SpeechAnalyzer is enabled",
        "streaming": "Foundation Model responses can be observed incrementally",
        "tools": "This page permits only the bundled lookupCapability tool",
    ]
}

@MainActor
final class FoundationToolCallingViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var result: FoundationToolResponse?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var inputSnapshot: String?

    let service: FoundationToolCallingService
    private let currentTime: () -> TimeInterval
    private var operationTask: Task<Void, Never>?
    private var activeRequestToken: UUID?
    private var startedAt: TimeInterval?

    init(
        service: FoundationToolCallingService = FoundationToolCallingService(),
        currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate },
        clock: (() -> TimeInterval)? = nil
    ) {
        self.service = service
        self.currentTime = clock ?? currentTime
    }

    var availabilityStatus: FoundationModelStatus { service.availabilityStatus }
    var canRun: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            availabilityStatus == .available && !isRunning
    }

    var isInputEditable: Bool { !isRunning }

    func run() async {
        guard !isRunning else { return }
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            errorMessage = FoundationModelServiceError.emptyInput.localizedDescription
            return
        }
        guard availabilityStatus == .available else {
            errorMessage = FoundationModelServiceError.unavailable(availabilityStatus).localizedDescription
            return
        }

        let token = UUID()
        let started = currentTime()
        activeRequestToken = token
        startedAt = started
        inputSnapshot = request
        result = nil
        errorMessage = nil
        latency = nil
        isRunning = true

        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await self.service.respond(to: request)
                guard !Task.isCancelled else { return }
                self.finish(response, token: token, startedAt: started)
            } catch is CancellationError {
                self.finishCancellation(token: token, startedAt: started)
            } catch {
                self.finish(error: error, token: token, startedAt: started)
            }
        }
        operationTask = operation

        await withTaskCancellationHandler(operation: {
            await operation.value
        }, onCancel: {
            operation.cancel()
            Task { @MainActor [weak self] in self?.cancel(token: token) }
        })
        if Task.isCancelled { cancel(token: token) }
    }

    func cancel() {
        cancel(token: activeRequestToken)
    }

    func onDisappear() {
        cancel()
    }

    private func cancel(token: UUID?) {
        guard let token, activeRequestToken == token, isRunning else { return }
        operationTask?.cancel()
        operationTask = nil
        activeRequestToken = nil
        isRunning = false
        if let startedAt { latency = currentTime() - startedAt }
    }

    private func finish(_ response: FoundationToolResponse, token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        result = response
        finishActive(token: token, startedAt: startedAt)
    }

    private func finish(error: Error, token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        errorMessage = error.localizedDescription
        finishActive(token: token, startedAt: startedAt)
    }

    private func finishCancellation(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        finishActive(token: token, startedAt: startedAt)
    }

    private func finishActive(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        latency = currentTime() - startedAt
        activeRequestToken = nil
        operationTask = nil
        isRunning = false
    }
}

@MainActor
final class FoundationModelViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var result: String?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var inputSnapshot: String?

    let service: any FoundationModelServing
    private let currentTime: () -> TimeInterval
    private var operationTask: Task<Void, Never>?
    private var activeRequestToken: UUID?
    private var startedAt: TimeInterval?

    init(service: any FoundationModelServing = FoundationModelService(), currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }, clock: (() -> TimeInterval)? = nil) {
        self.service = service
        self.currentTime = clock ?? currentTime
    }

    var availabilityStatus: FoundationModelStatus { service.availabilityStatus }
    var canRun: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && availabilityStatus == .available && !isRunning
    }

    var isInputEditable: Bool { !isRunning }

    func run() async {
        guard !isRunning else { return }
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { returnFailure(FoundationModelServiceError.emptyInput); return }
        guard availabilityStatus == .available else { returnFailure(.unavailable(availabilityStatus)); return }
        begin(request: request)
        let token = activeRequestToken!
        let startedAt = self.startedAt!
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let value = try await self.service.respond(to: request)
                guard !Task.isCancelled else { return }
                self.finish(value, token: token, startedAt: startedAt)
            } catch is CancellationError {
                self.finishCancellation(token: token, startedAt: startedAt)
            } catch {
                self.finish(error: error, token: token, startedAt: startedAt)
            }
        }
        operationTask = operation
        await withTaskCancellationHandler(operation: { await operation.value }, onCancel: {
            operation.cancel()
            Task { @MainActor [weak self] in self?.cancel(token: token) }
        })
        if Task.isCancelled { cancel(token: token) }
    }

    func cancel() { cancel(token: activeRequestToken) }
    func onDisappear() { cancel() }

    private func begin(request: String) {
        result = nil; errorMessage = nil; latency = nil; isRunning = true
        inputSnapshot = request
        startedAt = currentTime()
        activeRequestToken = UUID()
    }

    private func cancel(token: UUID?) {
        guard let token, activeRequestToken == token, isRunning else { return }
        operationTask?.cancel(); operationTask = nil
        activeRequestToken = nil; isRunning = false
        if let startedAt { latency = currentTime() - startedAt }
    }

    private func finish(_ value: String, token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        result = value; finishActive(token: token, startedAt: startedAt)
    }

    private func finish(error: Error, token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        errorMessage = error.localizedDescription; finishActive(token: token, startedAt: startedAt)
    }

    private func finishCancellation(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        finishActive(token: token, startedAt: startedAt)
    }

    private func finishActive(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        latency = currentTime() - startedAt
        activeRequestToken = nil; operationTask = nil; isRunning = false
    }

    private func returnFailure(_ error: FoundationModelServiceError) {
        result = nil; latency = nil; errorMessage = error.localizedDescription
    }
}

typealias FoundationPromptViewModel = FoundationModelViewModel
typealias FoundationModelPromptViewModel = FoundationModelViewModel

@MainActor
final class GuidedGenerationViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var result: GuidedTextAnalysis?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var inputSnapshot: String?

    let service: any FoundationModelServing
    private let currentTime: () -> TimeInterval
    private var operationTask: Task<Void, Never>?
    private var activeRequestToken: UUID?
    private var startedAt: TimeInterval?

    init(service: any FoundationModelServing = FoundationModelService(), currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }, clock: (() -> TimeInterval)? = nil) {
        self.service = service
        self.currentTime = clock ?? currentTime
    }

    var availabilityStatus: FoundationModelStatus { service.availabilityStatus }
    var canRun: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && availabilityStatus == .available && !isRunning
    }

    var isInputEditable: Bool { !isRunning }

    func run() async {
        guard !isRunning else { return }
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { returnFailure(FoundationModelServiceError.emptyInput); return }
        guard availabilityStatus == .available else { returnFailure(.unavailable(availabilityStatus)); return }
        begin(request: request)
        let token = activeRequestToken!
        let startedAt = self.startedAt!
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let value = try await self.service.analyze(request)
                guard !Task.isCancelled else { return }
                self.finish(value, token: token, startedAt: startedAt)
            } catch is CancellationError {
                self.finishCancellation(token: token, startedAt: startedAt)
            } catch {
                self.finish(error: error, token: token, startedAt: startedAt)
            }
        }
        operationTask = operation
        await withTaskCancellationHandler(operation: { await operation.value }, onCancel: {
            operation.cancel()
            Task { @MainActor [weak self] in self?.cancel(token: token) }
        })
        if Task.isCancelled { cancel(token: token) }
    }

    func cancel() { cancel(token: activeRequestToken) }
    func onDisappear() { cancel() }

    private func begin(request: String) {
        result = nil; errorMessage = nil; latency = nil; isRunning = true
        inputSnapshot = request; startedAt = currentTime(); activeRequestToken = UUID()
    }

    private func cancel(token: UUID?) {
        guard let token, activeRequestToken == token, isRunning else { return }
        operationTask?.cancel(); operationTask = nil; activeRequestToken = nil; isRunning = false
        if let startedAt { latency = currentTime() - startedAt }
    }

    private func finish(_ value: GuidedTextAnalysis, token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        result = value; finishActive(token: token, startedAt: startedAt)
    }

    private func finish(error: Error, token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        errorMessage = error.localizedDescription; finishActive(token: token, startedAt: startedAt)
    }

    private func finishCancellation(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        finishActive(token: token, startedAt: startedAt)
    }

    private func finishActive(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        latency = currentTime() - startedAt; activeRequestToken = nil; operationTask = nil; isRunning = false
    }

    private func returnFailure(_ error: FoundationModelServiceError) {
        result = nil; latency = nil; errorMessage = error.localizedDescription
    }
}

@MainActor
final class ContentTaggingViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var result: ContentTags?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var inputSnapshot: String?

    let service: any FoundationModelServing
    private let currentTime: () -> TimeInterval
    private var operationTask: Task<Void, Never>?
    private var activeRequestToken: UUID?
    private var startedAt: TimeInterval?

    init(service: any FoundationModelServing = FoundationModelService(), currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }, clock: (() -> TimeInterval)? = nil) {
        self.service = service
        self.currentTime = clock ?? currentTime
    }

    var availabilityStatus: FoundationModelStatus { service.contentTaggingAvailabilityStatus }
    var canRun: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && availabilityStatus == .available && !isRunning
    }

    var isInputEditable: Bool { !isRunning }

    func run() async {
        guard !isRunning else { return }
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { returnFailure(FoundationModelServiceError.emptyInput); return }
        guard availabilityStatus == .available else { returnFailure(.unavailable(availabilityStatus)); return }
        begin(request: request)
        let token = activeRequestToken!
        let startedAt = self.startedAt!
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let value = try await self.service.tag(request)
                guard !Task.isCancelled else { return }
                self.finish(value, token: token, startedAt: startedAt)
            } catch is CancellationError {
                self.finishCancellation(token: token, startedAt: startedAt)
            } catch {
                self.finish(error: error, token: token, startedAt: startedAt)
            }
        }
        operationTask = operation
        await withTaskCancellationHandler(operation: { await operation.value }, onCancel: {
            operation.cancel()
            Task { @MainActor [weak self] in self?.cancel(token: token) }
        })
        if Task.isCancelled { cancel(token: token) }
    }

    func cancel() { cancel(token: activeRequestToken) }
    func onDisappear() { cancel() }

    private func begin(request: String) {
        result = nil; errorMessage = nil; latency = nil; isRunning = true
        inputSnapshot = request; startedAt = currentTime(); activeRequestToken = UUID()
    }

    private func cancel(token: UUID?) {
        guard let token, activeRequestToken == token, isRunning else { return }
        operationTask?.cancel(); operationTask = nil; activeRequestToken = nil; isRunning = false
        if let startedAt { latency = currentTime() - startedAt }
    }

    private func finish(_ value: ContentTags, token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        result = value; finishActive(token: token, startedAt: startedAt)
    }

    private func finish(error: Error, token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        errorMessage = error.localizedDescription; finishActive(token: token, startedAt: startedAt)
    }

    private func finishCancellation(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        finishActive(token: token, startedAt: startedAt)
    }

    private func finishActive(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        latency = currentTime() - startedAt; activeRequestToken = nil; operationTask = nil; isRunning = false
    }

    private func returnFailure(_ error: FoundationModelServiceError) {
        result = nil; latency = nil; errorMessage = error.localizedDescription
    }
}

struct FoundationModelExperienceView: View {
    @StateObject private var model: FoundationModelViewModel
    init(service: any FoundationModelServing = FoundationModelService()) { _model = StateObject(wrappedValue: FoundationModelViewModel(service: service)) }
    var body: some View {
        FoundationExperienceForm(experience: ExperienceCatalog[.foundationModel], availabilityStatus: model.availabilityStatus, exampleInput: "Explain how on-device inference protects privacy.", prompt: "Ask for a concise answer from the on-device model.", inputLabel: "Prompt", inputPlaceholder: "Ask something…", input: $model.input, inputSnapshot: model.inputSnapshot, runLabel: "Respond", isRunning: model.isRunning, canRun: model.canRun, errorMessage: model.errorMessage, latency: model.latency, cancelAction: { model.cancel() }, action: { await model.run() }) {
            if let result = model.result { ResultSurface(title: "Response", text: result) }
        }
        .onDisappear { model.onDisappear() }
    }
}

struct GuidedGenerationExperienceView: View {
    @StateObject private var model: GuidedGenerationViewModel
    init(service: any FoundationModelServing = FoundationModelService()) { _model = StateObject(wrappedValue: GuidedGenerationViewModel(service: service)) }
    var body: some View {
        FoundationExperienceForm(experience: ExperienceCatalog[.guidedGeneration], availabilityStatus: model.availabilityStatus, exampleInput: "Book a trip to Tokyo next spring.", prompt: "Generate typed fields constrained by a FoundationModels schema.", inputLabel: "Text", inputPlaceholder: "Describe the text to analyze…", input: $model.input, inputSnapshot: model.inputSnapshot, runLabel: "Analyze", isRunning: model.isRunning, canRun: model.canRun, errorMessage: model.errorMessage, latency: model.latency, cancelAction: { model.cancel() }, action: { await model.run() }) {
            if let result = model.result {
                VStack(alignment: .leading, spacing: 8) {
                    ResultSurface(title: "Intent", text: result.intent)
                    ResultSurface(title: "Entities", text: result.entities.joined(separator: ", "))
                    ResultSurface(title: "Summary", text: result.summary)
                }
            }
        }
        .onDisappear { model.onDisappear() }
    }
}

struct ContentTaggingExperienceView: View {
    @StateObject private var model: ContentTaggingViewModel
    init(service: any FoundationModelServing = FoundationModelService()) { _model = StateObject(wrappedValue: ContentTaggingViewModel(service: service)) }
    var body: some View {
        FoundationExperienceForm(experience: ExperienceCatalog[.contentTagging], availabilityStatus: model.availabilityStatus, exampleInput: "I am excited to book Tokyo next week.", prompt: "Extract structured topics, entities, actions, and emotions.", inputLabel: "Text", inputPlaceholder: "Paste text to tag…", input: $model.input, inputSnapshot: model.inputSnapshot, runLabel: "Tag content", isRunning: model.isRunning, canRun: model.canRun, errorMessage: model.errorMessage, latency: model.latency, cancelAction: { model.cancel() }, action: { await model.run() }) {
            if let result = model.result {
                VStack(alignment: .leading, spacing: 8) {
                    ResultSurface(title: "Topics", text: result.topics.joined(separator: ", "))
                    ResultSurface(title: "Entities", text: result.entities.joined(separator: ", "))
                    ResultSurface(title: "Actions", text: result.actions.joined(separator: ", "))
                    ResultSurface(title: "Emotions", text: result.emotions.joined(separator: ", "))
                }
            }
        }
        .onDisappear { model.onDisappear() }
    }
}

struct FoundationStreamingExperienceView: View {
    @StateObject private var model: FoundationStreamingViewModel

    init(service: any FoundationStreamingServing = FoundationStreamingSessionAdapter(
        model: .default,
        availabilityProvider: { FoundationModelService.status(for: $0.availability) }
    )) {
        _model = StateObject(wrappedValue: FoundationStreamingViewModel(service: service))
    }

    var body: some View {
        FoundationExperienceForm(
            experience: ExperienceCatalog[.streaming],
            availabilityStatus: model.availabilityStatus,
            exampleInput: "Explain why on-device inference is private.",
            prompt: "Watch the latest partial response arrive. A final response is never invented by this page.",
            inputLabel: "Prompt",
            inputPlaceholder: "Ask for a streamed answer…",
            input: $model.input,
            inputSnapshot: nil,
            runLabel: "Stream response",
            isRunning: model.isRunning,
            canRun: model.canRun,
            errorMessage: model.errorMessage,
            latency: model.latency,
            cancelAction: { model.cancel() },
            action: { await model.run() }
        ) {
            if !model.partialResponse.isEmpty {
                ResultSurface(title: "Latest partial", text: model.partialResponse)
                Text("Received \(model.snapshots.count) unique partial snapshots.")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .onDisappear { model.cancel() }
    }
}

struct FoundationToolCallingExperienceView: View {
    @StateObject private var model: FoundationToolCallingViewModel

    init(service: FoundationToolCallingService = FoundationToolCallingService()) {
        _model = StateObject(wrappedValue: FoundationToolCallingViewModel(service: service))
    }

    var body: some View {
        FoundationExperienceForm(
            experience: ExperienceCatalog[.toolCalling],
            availabilityStatus: model.availabilityStatus,
            exampleInput: "What is the speech capability?",
            prompt: "This session receives only lookupCapability, backed by a fixed local dictionary. No network, database, or external service is used.",
            inputLabel: "Question",
            inputPlaceholder: "Ask about a bundled capability fact…",
            input: $model.input,
            inputSnapshot: model.inputSnapshot,
            runLabel: "Ask local tool",
            isRunning: model.isRunning,
            canRun: model.canRun,
            errorMessage: model.errorMessage,
            latency: model.latency,
            cancelAction: { model.cancel() },
            action: { await model.run() }
        ) {
            if let result = model.result {
                ResultSurface(title: "Response", text: result.response)
                ResultSurface(
                    title: "Tool invocation",
                    text: result.toolWasCalled ? "lookupCapability was called." : "No tool call was recorded."
                )
            }
        }
        .onDisappear { model.onDisappear() }
    }
}

private struct FoundationExperienceForm<ResultContent: View>: View {
    let experience: ExperienceDefinition
    let availabilityStatus: FoundationModelStatus
    let exampleInput: String
    let prompt: String
    let inputLabel: String
    let inputPlaceholder: String
    @Binding var input: String
    let inputSnapshot: String?
    let runLabel: String
    let isRunning: Bool
    let canRun: Bool
    let errorMessage: String?
    let latency: TimeInterval?
    var cancelAction: (() -> Void)? = nil
    let action: () async -> Void
    @ViewBuilder let resultContent: () -> ResultContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ExperienceIntro(experience: experience)
                FoundationAvailabilitySurface(status: availabilityStatus)
                Text(prompt).foregroundStyle(AppTheme.secondaryInk)
                Text(inputLabel).font(.headline).foregroundStyle(AppTheme.ink)
                TextField(inputPlaceholder, text: $input, axis: .vertical).lineLimit(4...8).padding(14)
                    .disabled(isRunning)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("Use example") { input = exampleInput }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)
                if let inputSnapshot {
                    Text("Request snapshot: \(inputSnapshot)")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                }
                Button { Task { await action() } } label: {
                    Label(isRunning ? "Running…" : runLabel, systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(!canRun)
                if isRunning, let cancelAction {
                    Button("Cancel", action: cancelAction)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if let latency { Text(String(format: "Latency %.3fs", latency)).font(.footnote).foregroundStyle(AppTheme.secondaryInk) }
                resultContent()
                UsageInstructions(experience: experience)
                Text("Uses FoundationModels on device. A simulator build does not prove model execution.").font(.footnote).foregroundStyle(AppTheme.secondaryInk)
            }.padding(20)
        }
        .scrollIndicators(.hidden).background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(experience.title).navigationBarTitleDisplayMode(.inline)
    }
}

private struct FoundationAvailabilitySurface: View {
    let status: FoundationModelStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CURRENT DEVICE STATUS").font(.caption.weight(.bold)).foregroundStyle(AppTheme.secondaryInk)
            Text(status.rawValue).font(.headline).foregroundStyle(status == .available ? AppTheme.ink : .orange)
            Text(detail).font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var detail: String {
        switch status {
        case .available: "This model route is available; execution still depends on supported hardware and system state."
        case .deviceNotEligible: "This device is not eligible for Foundation Models. The page remains readable, but running is disabled."
        case .modelNotReady: "Foundation Model assets are not ready. Finish system preparation before running."
        case .unavailable: "Apple Intelligence is unavailable for this model route. Running is disabled."
        }
    }
}
