import Foundation
import FoundationModels

protocol SMSClassificationSessionServing: Sendable {
    func classifyDomain(prompt: String) async throws -> String
    func extractEntities(prompt: String, domain: String) async throws -> [SMSGeneratedEntity]
}

@MainActor
protocol SMSClassificationServing: AnyObject {
    var availabilityStatus: FoundationModelStatus { get }
    func classify(_ sms: String) async throws -> SMSGeneratedResult
}

protocol SMSSampleStoreServing {
    func load() -> [SMSSample]
}

extension BundledSMSSampleStore: SMSSampleStoreServing {}

enum SMSClassificationServiceError: LocalizedError, Equatable {
    case emptyInput
    case inputTooLong
    case unavailable(FoundationModelStatus)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Enter an SMS before running classification."
        case .inputTooLong:
            "SMS is too long for this experience (maximum 1000 UTF-16 code units)."
        case .unavailable(let status):
            "On-device language model is unavailable: \(status.rawValue)."
        }
    }
}

#if targetEnvironment(simulator)
struct SMSGeneratedModelEntity: Equatable, Sendable, Generable {
    static let allowedLabels = SMSClassificationVocabulary.entityLabels.sorted()
    var text: String
    var label: String
    var occurrence: Int

    init(text: String, label: String, occurrence: Int) {
        self.text = text
        self.label = label
        self.occurrence = occurrence
    }

    static var generationSchema: GenerationSchema { GeneratedContent.generationSchema }

    init(_ content: GeneratedContent) throws {
        text = try content.value(forProperty: "text")
        label = try content.value(forProperty: "label")
        occurrence = try content.value(forProperty: "occurrence")
    }

    var generatedContent: GeneratedContent {
        GeneratedContent(properties: [
            "text": text,
            "label": label,
            "occurrence": occurrence,
        ])
    }
}

struct SMSGeneratedDomainResult: Equatable, Sendable, Generable {
    static let allowedDomains = SMSClassificationVocabulary.domains.sorted()
    var domain: String

    init(domain: String) { self.domain = domain }
    static var generationSchema: GenerationSchema { GeneratedContent.generationSchema }
    init(_ content: GeneratedContent) throws { domain = try content.value(forProperty: "domain") }
    var generatedContent: GeneratedContent { GeneratedContent(properties: ["domain": domain]) }
}

struct SMSGeneratedEntitiesResult: Equatable, Sendable, Generable {
    var entities: [SMSGeneratedModelEntity]

    init(entities: [SMSGeneratedModelEntity]) { self.entities = entities }

    static var generationSchema: GenerationSchema { GeneratedContent.generationSchema }

    init(_ content: GeneratedContent) throws {
        entities = try content.value(forProperty: "entities")
    }

    var generatedContent: GeneratedContent {
        GeneratedContent(properties: [
            "entities": GeneratedContent(elements: entities),
        ])
    }
}
#else
@Generable
struct SMSGeneratedModelEntity: Equatable, Sendable {
    static let allowedLabels = SMSClassificationVocabulary.entityLabels.sorted()
    @Guide(description: "Exact contiguous entity text copied from the SMS") var text: String
    @Guide(description: "One label from the v7.24 entity allowlist", .anyOf(SMSClassificationVocabulary.entityLabels.sorted())) var label: String
    @Guide(description: "Zero-based occurrence of this exact text") var occurrence: Int
}

@Generable
struct SMSGeneratedDomainResult: Equatable, Sendable {
    static let allowedDomains = SMSClassificationVocabulary.domains.sorted()
    @Guide(description: "Exactly one v7.24 domain", .anyOf(SMSClassificationVocabulary.domains.sorted())) var domain: String
}

@Generable
struct SMSGeneratedEntitiesResult: Equatable, Sendable {
    @Guide(description: "Extract every supported entity copied from the SMS, up to 64", .maximumCount(64)) var entities: [SMSGeneratedModelEntity]
}
#endif

private final class SMSClassificationLanguageModelSessionAdapter: SMSClassificationSessionServing {
    private let session: LanguageModelSession

    init(model: SystemLanguageModel = SystemLanguageModel.default) {
        session = LanguageModelSession(model: model)
    }

    func classifyDomain(prompt: String) async throws -> String {
        let response = try await session.respond(to: prompt, generating: SMSGeneratedDomainResult.self)
        return response.content.domain
    }

    func extractEntities(prompt: String, domain: String) async throws -> [SMSGeneratedEntity] {
        let response = try await session.respond(to: prompt, generating: SMSGeneratedEntitiesResult.self)
        return response.content.entities.map {
            SMSGeneratedEntity(text: $0.text, label: $0.label, occurrence: $0.occurrence)
        }
    }
}

typealias SMSClassificationSessionFactory = (SystemLanguageModel) -> any SMSClassificationSessionServing

@MainActor
final class SMSClassificationService: SMSClassificationServing {
    private let model: SystemLanguageModel
    private let availabilityProvider: (SystemLanguageModel) -> FoundationModelStatus
    private let sessionFactory: SMSClassificationSessionFactory
    private let availabilityStatusOverride: FoundationModelStatus?

    init(
        model: SystemLanguageModel = SystemLanguageModel.default,
        availabilityProvider: @escaping (SystemLanguageModel) -> FoundationModelStatus = {
            FoundationModelService.status(for: $0.availability)
        },
        sessionFactory: @escaping SMSClassificationSessionFactory = {
            SMSClassificationLanguageModelSessionAdapter(model: $0)
        }
    ) {
        self.model = model
        self.availabilityProvider = availabilityProvider
        self.sessionFactory = sessionFactory
        self.availabilityStatusOverride = nil
    }

    init(
        availabilityStatus: FoundationModelStatus,
        sessionFactory: @escaping SMSClassificationSessionFactory
    ) {
        self.model = SystemLanguageModel.default
        self.availabilityProvider = { _ in availabilityStatus }
        self.sessionFactory = sessionFactory
        self.availabilityStatusOverride = availabilityStatus
    }

    var availabilityStatus: FoundationModelStatus {
        availabilityStatusOverride ?? availabilityProvider(model)
    }

    func classify(_ sms: String) async throws -> SMSGeneratedResult {
        let input = sms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw SMSClassificationServiceError.emptyInput }
        guard input.utf16.count <= SMSClassifierPrompt.maxSMSUTF16Length else {
            throw SMSClassificationServiceError.inputTooLong
        }
        guard availabilityStatus == .available else {
            throw SMSClassificationServiceError.unavailable(availabilityStatus)
        }
        try Task.checkCancellation()
        let session = sessionFactory(model)
        let generatedDomain = try await session.classifyDomain(
            prompt: SMSClassifierPrompt.makeDomainPrompt(sms: input)
        )
        let domain = SMSClassificationVocabulary.domains.contains(generatedDomain)
            ? generatedDomain
            : "ignored"
        try Task.checkCancellation()
        let entities = try await session.extractEntities(
            prompt: SMSClassifierPrompt.makeEntityPrompt(sms: input, domain: domain),
            domain: domain
        )
        return SMSGeneratedResult(domain: domain, entities: entities)
    }
}

@MainActor
final class SMSClassificationViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var inputSnapshot: String?
    @Published private(set) var currentSample: SMSSample?
    @Published private(set) var result: SMSAnnotationResult?
    @Published private(set) var rawJSONOutput: String?
    @Published private(set) var jsonOutput: String?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false

    let service: any SMSClassificationServing
    let samples: [SMSSample]

    private let sampleStore: any SMSSampleStoreServing
    private let currentTime: () -> TimeInterval
    private var operationTask: Task<Void, Never>?
    private var activeRequestToken: UUID?
    private var startedAt: TimeInterval?

    init(
        service: any SMSClassificationServing = SMSClassificationService(),
        sampleStore: any SMSSampleStoreServing = BundledSMSSampleStore(),
        currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    ) {
        self.service = service
        self.sampleStore = sampleStore
        self.samples = sampleStore.load()
        self.currentTime = currentTime
    }

    var availabilityStatus: FoundationModelStatus { service.availabilityStatus }

    var canRun: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            input.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= SMSClassifierPrompt.maxSMSUTF16Length &&
            availabilityStatus == .available && !isRunning
    }

    var isInputEditable: Bool { !isRunning }

    func run() async {
        guard !isRunning else { return }
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { returnFailure(.emptyInput); return }
        guard request.utf16.count <= SMSClassifierPrompt.maxSMSUTF16Length else {
            returnFailure(.inputTooLong)
            return
        }
        guard availabilityStatus == .available else {
            returnFailure(.unavailable(availabilityStatus))
            return
        }

        begin(request: request)
        let token = activeRequestToken!
        let startedAt = self.startedAt!
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let generated = try await self.service.classify(request)
                guard !Task.isCancelled else { return }
                self.finish(generated, source: request, token: token, startedAt: startedAt)
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

    func selectRandomSample(randomIndex: Int? = nil) {
        cancel()
        guard let sample = SMSRandomSamplePicker.next(
            from: samples,
            excluding: currentSample,
            randomIndex: randomIndex
        ) else { return }

        currentSample = sample
        input = sample.text
        result = nil
        rawJSONOutput = nil
        jsonOutput = nil
        inputSnapshot = nil
        latency = nil
        errorMessage = nil
    }

    private func begin(request: String) {
        result = nil
        rawJSONOutput = nil
        jsonOutput = nil
        errorMessage = nil
        latency = nil
        inputSnapshot = request
        startedAt = currentTime()
        activeRequestToken = UUID()
        isRunning = true
    }

    private func cancel(token: UUID?) {
        guard let token, activeRequestToken == token, isRunning else { return }
        operationTask?.cancel()
        operationTask = nil
        activeRequestToken = nil
        isRunning = false
        if let startedAt { latency = currentTime() - startedAt }
    }

    private func finish(
        _ generated: SMSGeneratedResult,
        source: String,
        token: UUID,
        startedAt: TimeInterval
    ) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        let annotation = SMSAnnotationValidator.validate(generated, source: source)
        do {
            let rawData = try JSONEncoder.sorted.encode(generated)
            rawJSONOutput = String(decoding: rawData, as: UTF8.self)
            result = annotation
            jsonOutput = try annotation.jsonString()
            finishActive(token: token, startedAt: startedAt)
        } catch {
            finish(error: error, token: token, startedAt: startedAt)
        }
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

    private func returnFailure(_ error: SMSClassificationServiceError) {
        result = nil
        rawJSONOutput = nil
        jsonOutput = nil
        latency = nil
        errorMessage = error.localizedDescription
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
