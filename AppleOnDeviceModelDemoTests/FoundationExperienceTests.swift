import Foundation
import FoundationModels
import Testing
@testable import AppleOnDeviceModelDemo

@MainActor
struct FoundationExperienceTests {
    @Test func contentTaggingViewModelUsesRouteSpecificAvailability() async {
        let service = FoundationServiceStub()
        service.availabilityStatus = .available
        service.contentTaggingAvailabilityStatus = .modelNotReady
        let model = ContentTaggingViewModel(service: service)
        model.input = "hello"

        await model.run()

        #expect(model.errorMessage == FoundationModelServiceError.unavailable(.modelNotReady).localizedDescription)
        #expect(service.tagCalls == 0)
    }

    @Test func emptyInputIsRejectedBeforeSessionFactory() async {
        let service = FoundationModelService(
            availabilityProvider: { _ in .available },
            sessionFactory: { _ in fatalError("session must not be constructed") }
        )

        await #expect(throws: FoundationModelServiceError.emptyInput) {
            try await service.respond(to: " \n\t ")
        }
    }

    @Test func unavailableModelIsRejectedBeforeSessionFactory() async {
        let service = FoundationModelService(
            availabilityProvider: { _ in .modelNotReady },
            sessionFactory: { _ in fatalError("session must not be constructed") }
        )

        await #expect(throws: FoundationModelServiceError.unavailable(.modelNotReady)) {
            try await service.respond(to: "hello")
        }
    }

    @Test func serviceRoutesExactPromptsAndStructuredResponses() async throws {
        let generalModel = SystemLanguageModel.default
        let taggingModel = SystemLanguageModel(useCase: .contentTagging)
        let session = FoundationSessionStub()
        session.response = "hello back"
        session.analysis = GuidedTextAnalysis(intent: "plan", entities: ["Tokyo"], summary: "Plan a trip.")
        session.tags = ContentTags(topics: ["travel"], entities: ["Tokyo"], actions: ["book"], emotions: ["excited"])
        let receivedModels = ModelCapture()
        let service = FoundationModelService(
            model: generalModel,
            contentTaggingModel: taggingModel,
            availabilityProvider: { _ in .available },
            sessionFactory: { model in
                receivedModels.models.append(model)
                return session
            }
        )

        let response = try await service.respond(to: "  hello  ")
        let analysis = try await service.analyze("东京旅行")
        let tags = try await service.tag("book Tokyo")

        #expect(response == "hello back")
        #expect(analysis.intent == "plan")
        #expect(tags.topics == ["travel"])
        #expect(session.prompts == [
            FoundationModelPrompts.respond(to: "hello"),
            FoundationModelPrompts.analyze(to: "东京旅行"),
            FoundationModelPrompts.tag(to: "book Tokyo"),
        ])
        #expect(receivedModels.models.count == 3)
        #expect(receivedModels.models[2] === taggingModel)
    }

    @Test func servicePropagatesSessionErrors() async {
        let session = FoundationSessionStub()
        session.error = TestFoundationError.failed
        let service = FoundationModelService(
            availabilityProvider: { _ in .available },
            sessionFactory: { _ in session }
        )

        await #expect(throws: TestFoundationError.failed) {
            try await service.respond(to: "hello")
        }
    }

    @Test func contentTaggingRendersStructuredFields() async {
        let service = FoundationServiceStub()
        service.tags = ContentTags(
            topics: ["travel"],
            entities: ["Tokyo"],
            actions: ["book"],
            emotions: ["excited"]
        )
        let model = ContentTaggingViewModel(service: service)
        model.input = "I am excited to book Tokyo."

        await model.run()

        #expect(model.result?.topics == ["travel"])
        #expect(model.result?.entities == ["Tokyo"])
        #expect(model.result?.actions == ["book"])
        #expect(model.result?.emotions == ["excited"])
        #expect(service.tagCalls == 1)
    }

    @Test func emptyAndWhitespaceInputDoesNotCallService() async {
        let service = FoundationServiceStub()
        let model = ContentTaggingViewModel(service: service)
        model.input = " \n\t "

        await model.run()

        #expect(model.result == nil)
        #expect(service.tagCalls == 0)
        #expect(model.errorMessage == FoundationModelServiceError.emptyInput.localizedDescription)
    }

    @Test func unicodeInputIsTrimmedOnlyAtTheBoundaries() async {
        let service = FoundationServiceStub()
        service.tags = ContentTags(topics: ["旅行", "美食"], entities: ["東京", "京都"], actions: ["予約", "訪問"], emotions: [])
        let model = ContentTaggingViewModel(service: service)
        model.input = "  你好，東京。  "

        await model.run()

        #expect(service.lastTagInput == "你好，東京。")
        #expect(model.result?.topics == ["旅行", "美食"])
        #expect(model.result?.emotions.isEmpty == true)
    }

    @Test func unavailableStatusIsReportedWithoutCallingService() async {
        let service = FoundationServiceStub()
        service.availabilityStatus = .deviceNotEligible
        let model = GuidedGenerationViewModel(service: service)
        model.input = "Plan a trip."

        await model.run()

        #expect(model.result == nil)
        #expect(service.analyzeCalls == 0)
        #expect(model.errorMessage == FoundationModelServiceError.unavailable(.deviceNotEligible).localizedDescription)
    }

    @Test func guidedGenerationMapsAllStructuredFields() async {
        let service = FoundationServiceStub()
        service.analysis = GuidedTextAnalysis(
            intent: "plan",
            entities: ["Tokyo", "京都"],
            summary: "Plan a trip to Japan."
        )
        let model = GuidedGenerationViewModel(service: service)
        model.input = "  Plan a trip to Tokyo and 京都. "

        await model.run()

        #expect(model.result == service.analysis)
        #expect(service.lastAnalyzeInput == "Plan a trip to Tokyo and 京都.")
    }

    @Test func promptConstructionIsExactAndPreservesStructuredRequest() {
        #expect(
            FoundationModelPrompts.respond(to: "  hello  ")
                == "Please respond clearly and concisely to the following request:\n\nhello"
        )
        #expect(
            FoundationModelPrompts.analyze(to: "东京旅行")
                == "Analyze the following text and return the primary intent, important entities, and a summary under 30 words:\n\n东京旅行"
        )
        #expect(
            FoundationModelPrompts.tag(to: "I feel excited")
                == "Identify topics, entities, actions, and emotions in the following text:\n\nI feel excited"
        )
    }

    @Test func serviceErrorsArePublishedAndCancellationIsNotAnError() async {
        let service = FoundationServiceStub()
        service.error = TestFoundationError.failed
        let failedModel = ContentTaggingViewModel(service: service)
        failedModel.input = "hello"
        await failedModel.run()
        #expect(failedModel.errorMessage == TestFoundationError.failed.localizedDescription)
        #expect(failedModel.latency != nil)

        service.error = CancellationError()
        let cancelledModel = ContentTaggingViewModel(service: service)
        cancelledModel.input = "hello"
        await cancelledModel.run()
        #expect(cancelledModel.errorMessage == nil)
        #expect(cancelledModel.result == nil)
    }

    @Test func promptModelPublishesErrorAndCancellation() async {
        let service = FoundationServiceStub()
        service.error = TestFoundationError.failed
        let failedModel = FoundationModelViewModel(service: service, currentTime: { 10 })
        failedModel.input = "hello"
        await failedModel.run()
        #expect(failedModel.errorMessage == TestFoundationError.failed.localizedDescription)
        #expect(failedModel.latency == 0)

        service.error = CancellationError()
        let cancelledModel = FoundationModelViewModel(service: service)
        cancelledModel.input = "hello"
        await cancelledModel.run()
        #expect(cancelledModel.errorMessage == nil)
        #expect(cancelledModel.result == nil)
    }

    @Test func promptModelSuppressesDuplicatesAndUsesDeterministicLatency() async {
        let service = FoundationServiceStub()
        var times = [30.0, 30.75]
        let model = FoundationModelViewModel(service: service, currentTime: { times.removeFirst() })
        model.input = "hello"
        var release: (() -> Void)?
        service.responseWork = {
            await withCheckedContinuation { continuation in
                release = { continuation.resume(returning: "done") }
            }
        }
        let firstRun = Task { await model.run() }
        while release == nil { await Task.yield() }
        await model.run()
        #expect(service.responseCalls == 1)
        #expect(model.isRunning)
        release?()
        await firstRun.value
        #expect(model.result == "done")
        #expect(model.latency == 0.75)
    }

    @Test func guidedModelPublishesErrorAndCancellation() async {
        let service = FoundationServiceStub()
        service.error = TestFoundationError.failed
        let failedModel = GuidedGenerationViewModel(service: service)
        failedModel.input = "hello"
        await failedModel.run()
        #expect(failedModel.errorMessage == TestFoundationError.failed.localizedDescription)

        service.error = CancellationError()
        let cancelledModel = GuidedGenerationViewModel(service: service)
        cancelledModel.input = "hello"
        await cancelledModel.run()
        #expect(cancelledModel.errorMessage == nil)
        #expect(cancelledModel.result == nil)
    }

    @Test func guidedModelSuppressesDuplicatesAndUsesDeterministicLatency() async {
        let service = FoundationServiceStub()
        var times = [20.0, 20.5]
        let model = GuidedGenerationViewModel(service: service, currentTime: { times.removeFirst() })
        model.input = "hello"
        var release: (() -> Void)?
        service.analyzeWork = {
            await withCheckedContinuation { continuation in
                release = { continuation.resume(returning: GuidedTextAnalysis(intent: "answer", entities: [], summary: "done")) }
            }
        }
        let firstRun = Task { await model.run() }
        while release == nil { await Task.yield() }
        await model.run()
        #expect(service.analyzeCalls == 1)
        #expect(model.isRunning)
        release?()
        await firstRun.value
        #expect(model.result?.intent == "answer")
        #expect(model.latency == 0.5)
    }

    @Test func duplicateRunsAreSuppressedAndLatencyUsesInjectedClock() async {
        let service = FoundationServiceStub()
        var times = [10.0, 10.25]
        let model = ContentTaggingViewModel(service: service, currentTime: { times.removeFirst() })
        model.input = "hello"

        var release: (() -> Void)?
        service.tagWork = {
            await withCheckedContinuation { continuation in
                release = { continuation.resume(returning: ContentTags(topics: ["one"], entities: [], actions: [], emotions: [])) }
            }
        }
        let firstRun = Task { await model.run() }
        while release == nil {
            await Task.yield()
        }
        await model.run()
        #expect(service.tagCalls == 1)
        #expect(model.isRunning)
        release?()
        await firstRun.value

        #expect(model.result?.topics == ["one"])
        #expect(model.latency == 0.25)
        #expect(!model.isRunning)
    }

    @Test func emptyStructuredArraysRemainEmpty() async {
        let service = FoundationServiceStub()
        service.tags = ContentTags(topics: [], entities: [], actions: [], emotions: [])
        let model = ContentTaggingViewModel(service: service)
        model.input = "No tags"

        await model.run()

        #expect(model.result == ContentTags(topics: [], entities: [], actions: [], emotions: []))
    }

    @Test func cancelledPromptRunKeepsSnapshotAndCannotPublishStaleResult() async {
        let service = FoundationServiceStub()
        var release: (() -> Void)?
        service.responseWork = {
            await withCheckedContinuation { continuation in
                release = { continuation.resume(returning: "stale") }
            }
        }
        let model = FoundationModelViewModel(service: service)
        model.input = "first"
        let first = Task { @MainActor in await model.run() }
        while release == nil { await Task.yield() }
        model.cancel()
        model.input = "second"
        service.responseWork = { "fresh" }
        await model.run()
        release?()
        await first.value

        #expect(model.result == "fresh")
        #expect(model.inputSnapshot == "second")
        #expect(model.errorMessage == nil)
    }
}

@MainActor
private final class FoundationServiceStub: FoundationModelServing {
    var availabilityStatus: FoundationModelStatus = .available
    var contentTaggingAvailabilityStatus: FoundationModelStatus = .available
    var response = ""
    var analysis = GuidedTextAnalysis(intent: "", entities: [], summary: "")
    var tags = ContentTags(topics: [], entities: [], actions: [], emotions: [])
    var error: Error?
    var tagCalls = 0
    var analyzeCalls = 0
    var responseCalls = 0
    var analyzeWork: (() async throws -> GuidedTextAnalysis)?
    var responseWork: (() async throws -> String)?
    var lastTagInput: String?
    var lastAnalyzeInput: String?
    var tagWork: (() async throws -> ContentTags)?

    func respond(to prompt: String) async throws -> String {
        responseCalls += 1
        if let responseWork { return try await responseWork() }
        if let error { throw error }
        return response.isEmpty ? prompt : response
    }

    func analyze(_ prompt: String) async throws -> GuidedTextAnalysis {
        analyzeCalls += 1
        lastAnalyzeInput = prompt
        if let analyzeWork { return try await analyzeWork() }
        if let error { throw error }
        return analysis
    }

    func tag(_ text: String) async throws -> ContentTags {
        tagCalls += 1
        lastTagInput = text
        if let tagWork { return try await tagWork() }
        if let error { throw error }
        return tags
    }
}

private final class FoundationSessionStub: FoundationLanguageModelSessionServing, @unchecked Sendable {
    var response = ""
    var analysis = GuidedTextAnalysis(intent: "", entities: [], summary: "")
    var tags = ContentTags(topics: [], entities: [], actions: [], emotions: [])
    var error: Error?
    var prompts = [String]()

    func respond(to prompt: String) async throws -> String {
        prompts.append(prompt)
        if let error { throw error }
        return response
    }

    func analyze(to prompt: String) async throws -> GuidedTextAnalysis {
        prompts.append(prompt)
        if let error { throw error }
        return analysis
    }

    func tag(to prompt: String) async throws -> ContentTags {
        prompts.append(prompt)
        if let error { throw error }
        return tags
    }
}

private final class ModelCapture: @unchecked Sendable {
    var models = [SystemLanguageModel]()
}

private enum TestFoundationError: LocalizedError {
    case failed

    var errorDescription: String? { "foundation operation failed" }
}
