import Foundation
import FoundationModels

enum FoundationModelStatus: String, Equatable, Sendable {
    case available = "Available"
    case deviceNotEligible = "Device Not Eligible"
    case modelNotReady = "Model Not Ready"
    case unavailable = "Unavailable"
}

enum FoundationModelServiceError: LocalizedError, Equatable {
    case unavailable(FoundationModelStatus)
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .unavailable(let status):
            "Foundation Model is unavailable: \(status.rawValue)."
        case .emptyInput:
            "Enter text before running this model experience."
        }
    }
}

protocol FoundationLanguageModelSessionServing: Sendable {
    func respond(to prompt: String) async throws -> String
    func analyze(to prompt: String) async throws -> GuidedTextAnalysis
    func tag(to prompt: String) async throws -> ContentTags
}

private final class FoundationLanguageModelSessionAdapter: FoundationLanguageModelSessionServing {
    private let session: LanguageModelSession

    init(model: SystemLanguageModel) {
        session = LanguageModelSession(model: model)
    }

    func respond(to prompt: String) async throws -> String {
        try await session.respond(to: prompt).content
    }

    func analyze(to prompt: String) async throws -> GuidedTextAnalysis {
        try await session.respond(to: prompt, generating: GuidedTextAnalysis.self).content
    }

    func tag(to prompt: String) async throws -> ContentTags {
        try await session.respond(to: prompt, generating: ContentTags.self).content
    }
}

typealias FoundationLanguageModelSessionFactory = @Sendable (SystemLanguageModel) -> any FoundationLanguageModelSessionServing

final class FoundationModelService: Sendable {
    private let model: SystemLanguageModel
    private let contentTaggingModel: SystemLanguageModel
    private let sessionFactory: FoundationLanguageModelSessionFactory
    private let availabilityProvider: @Sendable (SystemLanguageModel) -> FoundationModelStatus

    init(
        model: SystemLanguageModel = .default,
        contentTaggingModel: SystemLanguageModel? = nil,
        availabilityProvider: @escaping @Sendable (SystemLanguageModel) -> FoundationModelStatus = { FoundationModelService.status(for: $0.availability) },
        sessionFactory: @escaping FoundationLanguageModelSessionFactory = { FoundationLanguageModelSessionAdapter(model: $0) }
    ) {
        self.model = model
        self.contentTaggingModel = contentTaggingModel ?? SystemLanguageModel(useCase: .contentTagging)
        self.sessionFactory = sessionFactory
        self.availabilityProvider = availabilityProvider
    }

    var availabilityStatus: FoundationModelStatus {
        availabilityProvider(model)
    }

    var contentTaggingAvailabilityStatus: FoundationModelStatus {
        availabilityProvider(contentTaggingModel)
    }

    static func status(
        for availability: SystemLanguageModel.Availability
    ) -> FoundationModelStatus {
        switch CapabilityStatus.foundation(availability) {
        case .ready:
            .available
        case .deviceNotEligible:
            .deviceNotEligible
        case .modelNotReady:
            .modelNotReady
        case .appleIntelligenceDisabled, .unsupported:
            .unavailable
        default:
            .unavailable
        }
    }

    func respond(to transcript: String) async throws -> String {
        let request = try validatedInput(transcript, model: model)

        let session = sessionFactory(model)
        return try await session.respond(to: FoundationModelPrompts.respond(to: request))
    }

    func analyze(_ transcript: String) async throws -> GuidedTextAnalysis {
        let request = try validatedInput(transcript, model: model)
        let session = sessionFactory(model)
        return try await session.analyze(to: FoundationModelPrompts.analyze(to: request))
    }

    func tag(_ transcript: String) async throws -> ContentTags {
        let request = try validatedInput(transcript, model: contentTaggingModel)
        let session = sessionFactory(contentTaggingModel)
        return try await session.tag(to: FoundationModelPrompts.tag(to: request))
    }

    private func validatedInput(
        _ input: String,
        model: SystemLanguageModel
    ) throws -> String {
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            throw FoundationModelServiceError.emptyInput
        }

        let status = availabilityProvider(model)
        guard status == .available else {
            throw FoundationModelServiceError.unavailable(status)
        }
        return request
    }
}

@MainActor
protocol FoundationModelServing: AnyObject {
    var availabilityStatus: FoundationModelStatus { get }
    var contentTaggingAvailabilityStatus: FoundationModelStatus { get }
    func respond(to transcript: String) async throws -> String
    func analyze(_ transcript: String) async throws -> GuidedTextAnalysis
    func tag(_ transcript: String) async throws -> ContentTags
}

extension FoundationModelService: FoundationModelServing {}

extension FoundationModelServing {
    var contentTaggingAvailabilityStatus: FoundationModelStatus { availabilityStatus }

    func analyze(_ transcript: String) async throws -> GuidedTextAnalysis {
        throw FoundationModelServiceError.unavailable(availabilityStatus)
    }

    func tag(_ transcript: String) async throws -> ContentTags {
        throw FoundationModelServiceError.unavailable(availabilityStatus)
    }
}
