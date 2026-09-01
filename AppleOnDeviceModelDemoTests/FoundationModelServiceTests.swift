import Foundation
import FoundationModels
import Testing
@testable import AppleOnDeviceModelDemo

struct FoundationModelServiceTests {
    @Test func mapsAvailableStatus() {
        #expect(FoundationModelService.status(for: .available) == .available)
    }

    @Test func mapsDeviceNotEligibleStatus() {
        #expect(
            FoundationModelService.status(for: .unavailable(.deviceNotEligible))
                == .deviceNotEligible
        )
    }

    @Test func mapsModelNotReadyStatus() {
        #expect(
            FoundationModelService.status(for: .unavailable(.modelNotReady))
                == .modelNotReady
        )
    }

    @Test func mapsDisabledAppleIntelligenceToUnavailable() {
        #expect(
            FoundationModelService.status(for: .unavailable(.appleIntelligenceNotEnabled))
                == .unavailable
        )
    }

    @Test func classifiesContentSafetyRefusalAsBlockedSystem() {
        let error = TestContentTaggingError(description: "May contain sensitive content")

        #expect(
            FoundationContentTaggingDiagnostic.classification(for: error)
                == .blockedSystem
        )
    }

    @Test func classifiesUnexpectedContentTaggingErrorAsFailApp() {
        let error = TestContentTaggingError(description: "The typed generation failed")

        #expect(
            FoundationContentTaggingDiagnostic.classification(for: error)
                == .failApp
        )
    }
}

private struct TestContentTaggingError: LocalizedError {
    let description: String

    var errorDescription: String? { description }
}

enum FoundationContentTaggingDiagnostic {
    enum Classification: Equatable {
        case blockedSystem
        case failApp
    }

    static func classification(for error: any Error) -> Classification {
        let rawError = "\(error)\n\(error.localizedDescription)"
        return rawError.localizedCaseInsensitiveContains("May contain sensitive content")
            ? .blockedSystem
            : .failApp
    }
}

#if !targetEnvironment(simulator)
struct PhysicalDeviceFoundationModelTests {
    @Test
    func reportsAndExercisesDefaultModelOnPhysicalDevice() async throws {
        let model = SystemLanguageModel.default
        print("DEVICE_RESULT|FM-AVAILABILITY|\(model.availability)")

        guard case .available = model.availability else {
            print("DEVICE_RESULT|FM-01|BLOCKED_SYSTEM|\(model.availability)")
            return
        }

        let session = LanguageModelSession(model: model)
        let response = try await session.respond(
            to: "Explain on-device AI in one concise sentence."
        ).content
        #expect(!response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        print("DEVICE_RESULT|FM-01|PASS|\(response)")
    }

    @Test
    func reportsAndExercisesContentTaggingModelOnPhysicalDevice() async throws {
        let model = SystemLanguageModel(useCase: .contentTagging)
        print("DEVICE_RESULT|TAG-AVAILABILITY|\(model.availability)")

        guard case .available = model.availability else {
            print("DEVICE_RESULT|FM-05|BLOCKED_SYSTEM|\(model.availability)")
            return
        }

        let service = FoundationModelService(contentTaggingModel: model)
        let input = "The project team meets on Tuesday to review the next milestone."

        do {
            let tags = try await service.tag(input)
            let conformsToSchema =
                tags.topics.count <= 5 &&
                tags.entities.count <= 5 &&
                tags.actions.count <= 3 &&
                tags.emotions.count <= 3
            #expect(conformsToSchema)
            guard conformsToSchema else {
                print("DEVICE_RESULT|FM-05|FAIL_APP|Typed ContentTags exceeded its declared field limits")
                return
            }
            print(
                "DEVICE_RESULT|FM-05|PASS|topics=\(tags.topics);entities=\(tags.entities);actions=\(tags.actions);emotions=\(tags.emotions)"
            )
        } catch {
            let rawError = "\(error)"
            switch FoundationContentTaggingDiagnostic.classification(for: error) {
            case .blockedSystem:
                print("DEVICE_RESULT|FM-05|BLOCKED_SYSTEM|\(rawError)")
            case .failApp:
                print("DEVICE_RESULT|FM-05|FAIL_APP|\(rawError)")
                throw error
            }
        }
    }
}
#endif
