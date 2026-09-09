import Foundation
import FoundationModels
import CoreSpotlight
import Vision

enum OnDeviceModelProfile: String, CaseIterable, Identifiable, Sendable {
    case text
    case image
    case localSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text conversation"
        case .image: "Image understanding"
        case .localSearch: "Local search"
        }
    }

    var summary: String {
        switch self {
        case .text: "A continuous on-device conversation."
        case .image: "Understand an attached image with native vision tools."
        case .localSearch: "Answer using the device's indexed content."
        }
    }

    var requiredToolNames: [String] {
        switch self {
        case .text: []
        case .image: ["OCRTool", "BarcodeReaderTool"]
        case .localSearch: ["SpotlightSearchTool"]
        }
    }

    var requiredCapabilities: [OnDeviceModelCapability] {
        switch self {
        case .text: []
        case .image: [.vision, .toolCalling]
        case .localSearch: [.toolCalling]
        }
    }

    fileprivate var instructions: String {
        switch self {
        case .text:
            "You are a concise assistant. Stay on device and use the prior conversation context."
        case .image:
            "Describe only what can be supported by the attached image. Use OCRTool or BarcodeReaderTool when useful."
        case .localSearch:
            "Answer from local indexed content when possible. Use SpotlightSearchTool for device search."
        }
    }
}

enum OnDeviceModelCapability: String, CaseIterable, Sendable {
    case vision
    case guidedGeneration
    case reasoning
    case toolCalling
}

struct OnDeviceModelLabCapabilities: Equatable, Sendable {
    let availability: FoundationModelStatus
    let variant: String
    let capabilityNames: [String]
    let contextSize: Int

    static func snapshot(
        availability: FoundationModelStatus,
        variant: String,
        capabilities: [OnDeviceModelCapability],
        contextSize: Int
    ) -> Self {
        Self(
            availability: availability,
            variant: variant,
            capabilityNames: capabilities.map(\.rawValue),
            contextSize: contextSize
        )
    }

    @available(iOS 27.0, *)
    static func snapshot(for model: SystemLanguageModel = .default) -> Self {
        let capabilityPairs: [(OnDeviceModelCapability, LanguageModelCapabilities.Capability)] = [
            (.vision, .vision),
            (.guidedGeneration, .guidedGeneration),
            (.reasoning, .reasoning),
            (.toolCalling, .toolCalling),
        ]
        return snapshot(
            availability: FoundationModelService.status(for: model.availability),
            variant: model.variant.displayName,
            capabilities: capabilityPairs.compactMap { model.capabilities.contains($0.1) ? $0.0 : nil },
            contextSize: model.contextSize
        )
    }

    func supports(_ capability: OnDeviceModelCapability) -> Bool {
        capabilityNames.contains(capability.rawValue)
    }
}

enum OnDeviceModelLabError: LocalizedError, Equatable {
    case emptyInput
    case attachmentRequired
    case unavailable(FoundationModelStatus)
    case unsupportedCapability(OnDeviceModelCapability)

    var errorDescription: String? {
        switch self {
        case .emptyInput: "Enter text before sending."
        case .attachmentRequired: "Attach an image for the image profile."
        case .unavailable(let status): "On-device model unavailable: " + status.rawValue + "."
        case .unsupportedCapability(let capability): "This profile requires the " + capability.rawValue + " capability."
        }
    }
}

struct OnDeviceModelLabRequest: Equatable, Sendable {
    let text: String
    let profile: OnDeviceModelProfile
    let imageURL: URL?

    static func make(
        text: String,
        profile: OnDeviceModelProfile,
        imageURL: URL? = nil
    ) throws -> Self {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OnDeviceModelLabError.emptyInput }
        if profile == .image, imageURL == nil {
            throw OnDeviceModelLabError.attachmentRequired
        }
        return Self(text: trimmed, profile: profile, imageURL: imageURL)
    }
}

struct OnDeviceModelLabResponse: Equatable, Sendable {
    let text: String
    let toolNames: [String]
}

struct OnDeviceModelLabTurn: Identifiable, Equatable, Sendable {
    let id: UUID
    let request: OnDeviceModelLabRequest
    let response: String
    let toolNames: [String]
    let latency: TimeInterval

    init(
        id: UUID = UUID(),
        request: OnDeviceModelLabRequest,
        response: String,
        toolNames: [String],
        latency: TimeInterval
    ) {
        self.id = id
        self.request = request
        self.response = response
        self.toolNames = toolNames
        self.latency = latency
    }
}

protocol OnDeviceModelLabSessionServing: AnyObject, Sendable {
    func respond(to input: OnDeviceModelLabRequest) async throws -> OnDeviceModelLabResponse
}

typealias OnDeviceModelLabSessionFactory = @MainActor @Sendable (
    SystemLanguageModel,
    OnDeviceModelProfile,
    [OnDeviceModelLabTurn]
) -> any OnDeviceModelLabSessionServing

final class OnDeviceModelLabToolCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var names = [String]()

    func reset() {
        lock.lock()
        names.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func record(_ name: String) {
        lock.lock()
        names.append(name)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return names
    }
}

@available(iOS 27.0, *)
struct OnDeviceModelLabDynamicProfile: LanguageModelSession.DynamicProfile {
    let selection: OnDeviceModelProfile
    private let recorder: OnDeviceModelLabToolCallRecorder

    init(selection: OnDeviceModelProfile, recorder: OnDeviceModelLabToolCallRecorder) {
        self.selection = selection
        self.recorder = recorder
    }

    var toolNames: [String] {
        selection.requiredToolNames
    }

    var hasToolCallHandler: Bool {
        !toolNames.isEmpty
    }

    @LanguageModelSession.DynamicProfileBuilder
    var body: some LanguageModelSession.DynamicProfile {
        switch selection {
        case .text:
            LanguageModelSession.Profile {
                Instructions(selection.instructions)
            }
        case .image:
            LanguageModelSession.Profile {
                Instructions(selection.instructions)
                [OCRTool(), BarcodeReaderTool()]
            }
            .onToolCall { [recorder] call in
                recorder.record(call.toolName)
            }
        case .localSearch:
            LanguageModelSession.Profile {
                Instructions(selection.instructions)
                [SpotlightSearchTool()]
            }
            .onToolCall { [recorder] call in
                recorder.record(call.toolName)
            }
        }
    }
}

private final class OnDeviceModelLabSessionAdapter: OnDeviceModelLabSessionServing, @unchecked Sendable {
    private let session: LanguageModelSession
    private let toolCallRecorder: OnDeviceModelLabToolCallRecorder

    @available(iOS 27.0, *)
    init(model: SystemLanguageModel, profile: OnDeviceModelProfile, history: [OnDeviceModelLabTurn]) {
        let recorder = OnDeviceModelLabToolCallRecorder()
        toolCallRecorder = recorder
        let dynamicProfile = OnDeviceModelLabDynamicProfile(selection: profile, recorder: recorder)
        session = LanguageModelSession(profile: dynamicProfile, history: Self.transcriptEntries(from: history))
    }

    @DynamicInstructionsBuilder
    @available(iOS 27.0, *)
    private static func dynamicInstructions(
        for profile: OnDeviceModelProfile,
        tools: [any Tool]
    ) -> some DynamicInstructions {
        Instructions(profile.instructions)
        tools
    }

    private static func transcriptEntries(from _: [OnDeviceModelLabTurn]) -> [Transcript.Entry] {
        // The native session owns the authoritative transcript. This is intentionally
        // empty for the first implementation; history is retained by that session.
        []
    }

    func respond(to input: OnDeviceModelLabRequest) async throws -> OnDeviceModelLabResponse {
        toolCallRecorder.reset()
        let response: LanguageModelSession.Response<String>
        if let imageURL = input.imageURL {
            let attachment = Attachment<ImageAttachmentContent>(imageURL: imageURL)
            response = try await session.respond(to: Prompt {
                input.text
                attachment
            })
        } else {
            response = try await session.respond(to: input.text)
        }
        return OnDeviceModelLabResponse(text: response.content, toolNames: toolCallRecorder.snapshot())
    }
}

@MainActor
final class OnDeviceModelLab: ObservableObject {
    @Published var text = ""
    @Published var selectedProfile: OnDeviceModelProfile {
        didSet {
            if oldValue != selectedProfile {
                session = nil
                turns = []
                errorMessage = nil
                if selectedProfile != .image {
                    imageURL = nil
                }
            }
        }
    }
    @Published var imageURL: URL?
    @Published private(set) var turns = [OnDeviceModelLabTurn]()
    @Published private(set) var isRunning = false
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var wasCancelled = false

    let capabilities: OnDeviceModelLabCapabilities
    private let model: SystemLanguageModel
    private let availability: FoundationModelStatus
    private let sessionFactory: OnDeviceModelLabSessionFactory
    private let currentTime: () -> TimeInterval
    private var session: (any OnDeviceModelLabSessionServing)?
    private var operationTask: Task<Void, Never>?
    private var activeRequestToken: UUID?
    private var startedAt: TimeInterval?

    init(
        model: SystemLanguageModel = .default,
        availability: FoundationModelStatus? = nil,
        capabilitiesOverride: OnDeviceModelLabCapabilities? = nil,
        sessionFactory: @escaping OnDeviceModelLabSessionFactory = { model, profile, history in
            OnDeviceModelLabSessionAdapter(model: model, profile: profile, history: history)
        },
        clock: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    ) {
        self.model = model
        self.availability = availability ?? FoundationModelService.status(for: model.availability)
        self.capabilities = capabilitiesOverride ?? OnDeviceModelLabCapabilities.snapshot(for: model)
        self.selectedProfile = .text
        self.imageURL = nil
        self.sessionFactory = sessionFactory
        self.currentTime = clock
    }

    var availabilityStatus: FoundationModelStatus { availability }
    var contextTurnCount: Int { turns.count }
    var canSend: Bool {
        !isRunning &&
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            availabilityStatus == .available &&
            (selectedProfile != .image || imageURL != nil)
    }

    func send() async {
        guard !isRunning else { return }
        do {
            let request = try OnDeviceModelLabRequest.make(text: text, profile: selectedProfile, imageURL: imageURL)
            guard availabilityStatus == .available else {
                throw OnDeviceModelLabError.unavailable(availabilityStatus)
            }
            for required in selectedProfile.requiredCapabilities where !capabilities.supports(required) {
                throw OnDeviceModelLabError.unsupportedCapability(required)
            }

            begin()
            let token = activeRequestToken!
            let started = startedAt!
            let operation: Task<Void, Never> = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    if self.session == nil {
                        self.session = self.sessionFactory(self.model, request.profile, self.turns)
                    }
                    guard let session = self.session else { return }
                    let response = try await session.respond(to: request)
                    guard !Task.isCancelled else { return }
                    self.finish(response, request: request, token: token, startedAt: started)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        cancel(token: activeRequestToken)
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    private func begin() {
        isRunning = true
        wasCancelled = false
        errorMessage = nil
        latency = nil
        activeRequestToken = UUID()
        startedAt = currentTime()
    }

    private func cancel(token: UUID?) {
        guard let token, token == activeRequestToken, isRunning else { return }
        operationTask?.cancel()
        operationTask = nil
        activeRequestToken = nil
        isRunning = false
        wasCancelled = true
        if let startedAt { latency = currentTime() - startedAt }
    }

    private func finish(
        _ response: OnDeviceModelLabResponse,
        request: OnDeviceModelLabRequest,
        token: UUID,
        startedAt: TimeInterval
    ) {
        guard token == activeRequestToken, !Task.isCancelled else { return }
        let elapsed = currentTime() - startedAt
        turns.append(OnDeviceModelLabTurn(
            request: request,
            response: response.text,
            toolNames: response.toolNames,
            latency: elapsed
        ))
        finishActive(token: token, startedAt: startedAt)
    }

    private func finish(error: Error, token: UUID, startedAt: TimeInterval) {
        guard token == activeRequestToken, !Task.isCancelled else { return }
        errorMessage = error.localizedDescription
        finishActive(token: token, startedAt: startedAt)
    }

    private func finishCancellation(token: UUID, startedAt: TimeInterval) {
        guard token == activeRequestToken else { return }
        wasCancelled = true
        finishActive(token: token, startedAt: startedAt)
    }

    private func finishActive(token: UUID, startedAt: TimeInterval) {
        guard token == activeRequestToken else { return }
        latency = currentTime() - startedAt
        activeRequestToken = nil
        operationTask = nil
        isRunning = false
    }
}
