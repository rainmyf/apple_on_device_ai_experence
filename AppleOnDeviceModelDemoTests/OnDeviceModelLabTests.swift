import Foundation
import FoundationModels
import Testing
@testable import AppleOnDeviceModelDemo

struct OnDeviceModelLabTests {
    @Test
    func selectedProfileBuildsTheNativeDynamicProfileContract() {
        let recorder = OnDeviceModelLabToolCallRecorder()
        let dynamicProfile = OnDeviceModelLabDynamicProfile(selection: .image, recorder: recorder)
        let erasedProfile = LanguageModelSession.AnyDynamicProfile(dynamicProfile)

        #expect(dynamicProfile.selection == .image)
        #expect(dynamicProfile.toolNames == ["OCRTool", "BarcodeReaderTool"])
        #expect(dynamicProfile.hasToolCallHandler)
        _ = erasedProfile
    }

    @Test
    func profilesExposeTheThreeOnDeviceBoundaries() {
        #expect(OnDeviceModelProfile.allCases == [.text, .image, .localSearch])
        #expect(OnDeviceModelProfile.text.requiredToolNames.isEmpty)
        #expect(OnDeviceModelProfile.image.requiredToolNames == ["OCRTool", "BarcodeReaderTool"])
        #expect(OnDeviceModelProfile.localSearch.requiredToolNames == ["SpotlightSearchTool"])
        #expect(OnDeviceModelProfile.image.requiredCapabilities == [.vision, .toolCalling])
        #expect(OnDeviceModelProfile.localSearch.requiredCapabilities == [.toolCalling])
    }

    @Test
    func inputValidationRejectsEmptyTextAndAttachmentlessImage() throws {
        #expect(throws: OnDeviceModelLabError.emptyInput) {
            try OnDeviceModelLabRequest.make(text: "   ", profile: .text)
        }
        #expect(throws: OnDeviceModelLabError.attachmentRequired) {
            try OnDeviceModelLabRequest.make(text: "Describe this", profile: .image)
        }
    }

    @Test
    func inputValidationTrimsTextAndPreservesImageURL() throws {
        let url = URL(fileURLWithPath: "/tmp/photo.png")
        let request = try OnDeviceModelLabRequest.make(
            text: "  What is here?  ", profile: .image, imageURL: url
        )
        #expect(request.text == "What is here?")
        #expect(request.imageURL == url)
    }

    @Test @MainActor
    func sendReusesOneSessionAndPublishesContextTurnsAndLatency() async throws {
        let session = OnDeviceModelLabFakeSession(responses: ["first", "second"])
        var factoryCount = 0
        let lab = OnDeviceModelLab(
            availability: .available,
            sessionFactory: { _, _, _ in
                factoryCount += 1
                return session
            },
            clock: { 10 }
        )
        lab.text = "hello"

        await lab.send()
        lab.text = "follow up"
        await lab.send()

        #expect(factoryCount == 1)
        #expect(session.inputs.map(\.text) == ["hello", "follow up"])
        #expect(lab.turns.count == 2)
        #expect(lab.turns.map(\.response) == ["first", "second"])
        #expect((lab.latency ?? -1) >= 0)
    }

    @Test @MainActor
    func unavailableModelDoesNotCreateSession() async {
        let sessionCreated = LockedBoolean()
        let lab = OnDeviceModelLab(
            availability: .deviceNotEligible,
            sessionFactory: { _, _, _ in
                sessionCreated.value = true
                return OnDeviceModelLabFakeSession(responses: ["unexpected"])
            }
        )
        lab.text = "hello"

        await lab.send()

        #expect(!sessionCreated.value)
        #expect(lab.errorMessage?.contains("Device Not Eligible") == true)
    }

    @Test @MainActor
    func imageProfileRequiresVisionAndToolCallingBeforeSessionCreation() async {
        let sessionCreated = LockedBoolean()
        let lab = OnDeviceModelLab(
            availability: .available,
            capabilitiesOverride: .snapshot(
                availability: .available,
                variant: "Core 3",
                capabilities: [.vision],
                contextSize: 32768
            ),
            sessionFactory: { _, _, _ in
                sessionCreated.value = true
                return OnDeviceModelLabFakeSession(responses: ["unexpected"])
            }
        )
        lab.selectedProfile = .image
        lab.text = "Read this"
        lab.imageURL = URL(fileURLWithPath: "/tmp/photo.png")

        await lab.send()

        #expect(!sessionCreated.value)
        #expect(lab.errorMessage?.contains("toolCalling") == true)
    }

    @Test @MainActor
    func cancellationClearsRunningStateWithoutAddingTurn() async {
        let session = OnDeviceModelLabBlockingSession()
        let lab = OnDeviceModelLab(
            availability: .available,
            sessionFactory: { _, _, _ in session }
        )
        lab.text = "wait"
        let task = Task { @MainActor in await lab.send() }
        while !session.started { await Task.yield() }

        lab.cancel()
        await task.value

        #expect(!lab.isRunning)
        #expect(lab.turns.isEmpty)
        #expect(lab.wasCancelled)
    }

    @Test
    func realModelSnapshotUsesAvailabilityVariantCapabilitiesAndContextSize() {
        let snapshot = OnDeviceModelLabCapabilities.snapshot(
            availability: .available,
            variant: "Core Advanced 3",
            capabilities: [.vision, .toolCalling],
            contextSize: 32768
        )

        #expect(snapshot.variant == "Core Advanced 3")
        #expect(snapshot.capabilityNames == ["vision", "toolCalling"])
        #expect(snapshot.contextSize == 32768)
    }
}

@MainActor
private final class OnDeviceModelLabFakeSession: OnDeviceModelLabSessionServing {
    let responses: [String]
    var inputs = [OnDeviceModelLabRequest]()
    private var index = 0

    init(responses: [String]) { self.responses = responses }

    func respond(to input: OnDeviceModelLabRequest) async throws -> OnDeviceModelLabResponse {
        inputs.append(input)
        defer { index += 1 }
        return OnDeviceModelLabResponse(
            text: responses[min(index, responses.count - 1)],
            toolNames: input.profile.requiredToolNames
        )
    }
}

@MainActor
private final class OnDeviceModelLabBlockingSession: OnDeviceModelLabSessionServing {
    var started = false

    func respond(to input: OnDeviceModelLabRequest) async throws -> OnDeviceModelLabResponse {
        started = true
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            throw CancellationError()
        }
        return OnDeviceModelLabResponse(text: "unexpected", toolNames: [])
    }
}

private final class LockedBoolean: @unchecked Sendable {
    var value = false
}
