import CoreGraphics
import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

private struct FixedAdapterEntitlementChecker: FoundationModelAdapterEntitlementChecking {
    let isEntitled: Bool
}

private actor AdapterLoaderSpy {
    private(set) var calls: [URL] = []

    func record(_ url: URL) {
        calls.append(url)
    }
}

struct SystemExperienceTests {
    @Test
    func productionAdapterCheckerDoesNotPretendRuntimeEntitlementIsPublic() {
        let checker = FoundationModelAdapterBoundary.defaultEntitlementChecker

        #expect(String(describing: type(of: checker)).contains("SignedFoundationModelAdapterEntitlementChecker"))
        #expect(SignedFoundationModelAdapterEntitlementChecker.entitlementKey == "com.apple.developer.foundation-model-adapter")
        #expect(!checker.isEntitled)
    }

    @Test
    func adapterGateNeverInvokesLoaderWithoutEntitlementAssetOrExtension() async {
        let loader = AdapterLoaderSpy()
        let missingAsset = URL(fileURLWithPath: "/tmp/task12-missing.fmadapter")
        let wrongExtension = URL(fileURLWithPath: "/tmp/task12-missing.adapter")

        await #expect(throws: FoundationModelAdapterBoundaryError.entitlementRequired) {
            try await FoundationModelAdapterBoundary.loadIfReady(
                fileURL: missingAsset,
                entitlementChecker: FixedAdapterEntitlementChecker(isEntitled: false),
                loader: { url in
                    await loader.record(url)
                    return "loaded"
                }
            )
        }
        await #expect(throws: FoundationModelAdapterBoundaryError.assetRequired) {
            try await FoundationModelAdapterBoundary.loadIfReady(
                fileURL: missingAsset,
                entitlementChecker: FixedAdapterEntitlementChecker(isEntitled: true),
                loader: { url in
                    await loader.record(url)
                    return "loaded"
                }
            )
        }
        await #expect(throws: FoundationModelAdapterBoundaryError.incompatibleAsset) {
            try await FoundationModelAdapterBoundary.loadIfReady(
                fileURL: wrongExtension,
                entitlementChecker: FixedAdapterEntitlementChecker(isEntitled: true),
                loader: { url in
                    await loader.record(url)
                    return "loaded"
                }
            )
        }

        #expect(await loader.calls.isEmpty)
    }

    @Test
    func adapterPageStatusComesFromTheSetupGate() {
        let setupRequired = FoundationModelAdapterSetup(entitlementDeclared: false, assetURL: nil)
        let page = SystemExperienceContent.content(for: .customAdapter, adapterSetup: setupRequired)

        #expect(page.status.status == .setupRequired)
        #expect(page.status.detail.localizedCaseInsensitiveContains("signed"))
        #expect(page.status.detail.localizedCaseInsensitiveContains("fmadapter"))
        #expect(!page.status.detail.localizedCaseInsensitiveContains("executable"))
    }

    @Test
    func smartReplyContextContainsRealConversationEntries() {
        let context = SmartReplyConversationContextFactory.make()

        #expect(context.entries.count >= 2)
        #expect(context.entries.contains { !$0.text.isEmpty })
        #expect(context.entries.contains { $0.senderIdentifier == "other-participant" })
    }

    @Test
    func systemPagesDoNotOfferAppOwnedRunOrResultActions() {
        for id in [ExperienceID.writingTools, .genmoji, .smartReply, .appIntents, .customAdapter] {
            let page = SystemExperienceContent.content(for: id)
            #expect(!page.instructions.localizedCaseInsensitiveContains("run"))
            #expect(!page.usage.localizedCaseInsensitiveContains("result"))
        }
    }

    @Test
    func systemEntriesNeverClaimDirectModelExecution() {
        for id in [ExperienceID.writingTools, .genmoji, .smartReply, .appIntents, .customAdapter] {
            let page = SystemExperienceContent.content(for: id)
            #expect(page.executionKind != .directModel)
            #expect(!page.instructions.isEmpty)
        }
    }

    @Test
    func systemEntriesDeclareTheirInstalledSDKFrameworkAndEntryPoint() {
        #expect(SystemExperienceContent.content(for: .writingTools).framework == "UIKit")
        #expect(SystemExperienceContent.content(for: .writingTools).entryPoint.contains("writingToolsBehavior"))
        #expect(SystemExperienceContent.content(for: .genmoji).framework == "UIKit")
        #expect(SystemExperienceContent.content(for: .genmoji).entryPoint.contains("UITextInput"))
        #expect(SystemExperienceContent.content(for: .smartReply).framework == "UIKit")
        #expect(SystemExperienceContent.content(for: .smartReply).entryPoint.contains("UISmartReplySuggestion"))
        #expect(SystemExperienceContent.content(for: .appIntents).framework == "AppIntents")
        #expect(SystemExperienceContent.content(for: .appIntents).entryPoint.contains("AppIntent.perform"))
        #expect(SystemExperienceContent.content(for: .customAdapter).framework == "FoundationModels")
        #expect(SystemExperienceContent.content(for: .customAdapter).entryPoint.contains("SystemLanguageModel.Adapter"))
    }

    @Test
    func adapterWithoutEntitlementOrCompatibleAssetRemainsSetupOnly() {
        let content = SystemExperienceContent.content(for: .customAdapter)

        #expect(content.executionKind == .setupGuide)
        #expect(content.status.status == .setupRequired)
        #expect(content.limitations.localizedCaseInsensitiveContains("entitlement"))
        #expect(content.limitations.localizedCaseInsensitiveContains("fmadapter"))
    }

    @Test
    func adapterSetupNeverClaimsReadyEvenWhenAProbeHasBothInputs() {
        let setup = FoundationModelAdapterSetup(
            entitlementDeclared: true,
            assetURL: URL(fileURLWithPath: "/tmp/compatible.fmadapter"),
            assetExists: true
        )

        #expect(!setup.isExecutable)
        #expect(setup.status == .setupRequired)
        #expect(setup.gateDetail.localizedCaseInsensitiveContains("xcode"))
        #expect(setup.gateDetail.localizedCaseInsensitiveContains("signed"))
    }

    @Test
    func appIntentOutputIsHarmlessAndDeterministic() async throws {
        let intent = DescribeDemoCapabilityIntent.configured(for: "Writing Tools")
        let result = try await intent.perform()

        #expect(result.value == "Open On-device Experiences to try Writing Tools separately.")
    }

    @Test
    func appIntentDescriptionDoesNotClaimSiriModelAccess() {
        let content = SystemExperienceContent.content(for: .appIntents)

        #expect(content.limitations.localizedCaseInsensitiveContains("Siri"))
        #expect(content.limitations.localizedCaseInsensitiveContains("model"))
        #expect(!content.limitations.localizedCaseInsensitiveContains("private model access"))
    }

    @Test @MainActor
    func imageCreatorLoadCancellationLeavesCheckingStateAndAllowsRetry() async {
        let fake = RecordingImageCreator(styles: [.illustration])
        let factory = CancellingImageCreatorFactory(result: fake)
        let viewModel = ImageCreatorViewModel(creatorFactory: { try await factory.make() })
        let firstLoad = Task { @MainActor in await viewModel.load() }

        while !(await factory.started) { await Task.yield() }
        firstLoad.cancel()
        await firstLoad.value

        #expect(viewModel.availability == .checking)
        await viewModel.load()
        #expect(viewModel.availability == .available)
        #expect(await factory.callCount == 2)
    }

    @Test @MainActor
    func imageCreatorDoesNotPublishAFactoryResultAfterCancellationWhenFactoryIgnoresCancellation() async {
        let fake = RecordingImageCreator(styles: [.illustration])
        let factory = IgnoringCancellationImageCreatorFactory(result: fake)
        let viewModel = ImageCreatorViewModel(creatorFactory: { try await factory.make() })
        let loadTask = Task { @MainActor in await viewModel.load() }

        while !(await factory.started) { await Task.yield() }
        loadTask.cancel()
        await factory.release()
        await loadTask.value

        #expect(viewModel.availability == .checking)
        #expect(viewModel.styles.isEmpty)
        #expect(viewModel.selectedStyleID == nil)
    }

    @Test @MainActor
    func imageCreatorReportsUnavailableWhenTheFrameworkCannotBeInitialized() async {
        let viewModel = ImageCreatorViewModel(
            creatorFactory: { throw ImageCreatorBoundaryError.unavailable }
        )

        await viewModel.load()

        #expect(viewModel.availability == .unavailable("The image creator is unavailable on this device."))
        #expect(viewModel.styles.isEmpty)
    }

    @Test @MainActor
    func imageCreatorRejectsAnEmptyPromptWithoutCallingTheFramework() async {
        let fake = RecordingImageCreator(styles: [.illustration])
        let viewModel = ImageCreatorViewModel(creatorFactory: { fake })
        await viewModel.load()

        viewModel.input = "  \n"
        await viewModel.generate()

        #expect(viewModel.errorMessage == "Enter a prompt before generating an image.")
        #expect(fake.requests.isEmpty)
    }

    @Test @MainActor
    func imageCreatorPublishesTheFirstGeneratedImageAndTrimsPrompt() async {
        let image = GeneratedImage(identifier: "first", cgImage: makeTestImage())
        let fake = RecordingImageCreator(styles: [.illustration], images: [image])
        let viewModel = ImageCreatorViewModel(creatorFactory: { fake })
        await viewModel.load()

        viewModel.input = "  a fox in snow  "
        await viewModel.generate()

        #expect(viewModel.output?.identifier == "first")
        #expect(viewModel.runState == .succeeded)
        #expect(fake.requests.first?.prompt == "a fox in snow")
        #expect(fake.requests.first?.limit == 1)
    }

    @Test @MainActor
    func imageCreatorPassesTheSelectedStyleAnd26_4SafeConfiguration() async {
        let fake = RecordingImageCreator(styles: [.illustration, .sketch])
        let viewModel = ImageCreatorViewModel(creatorFactory: { fake })
        await viewModel.load()
        viewModel.selectedStyleID = ImageCreatorStyleOption.sketch.id
        viewModel.input = "a mountain"

        await viewModel.generate()

        #expect(fake.requests.first?.styleID == ImageCreatorStyleOption.sketch.id)
        #expect(fake.requests.first?.configuration == .default)
    }

    @Test @MainActor
    func imageCreatorPublishesFrameworkErrorsAsUserVisibleMessages() async {
        let fake = RecordingImageCreator(styles: [.illustration], failure: ImageCreatorBoundaryError.creationFailed)
        let viewModel = ImageCreatorViewModel(creatorFactory: { fake })
        await viewModel.load()
        viewModel.input = "a cat"

        await viewModel.generate()

        #expect(viewModel.output == nil)
        #expect(viewModel.errorMessage == "The image could not be created.")
        #expect(viewModel.runState == .failed("The image could not be created."))
    }

    @Test @MainActor
    func imageCreatorCanCancelAnInFlightGenerationAndReportsLatency() async {
        let fake = RecordingImageCreator(styles: [.illustration], suspends: true)
        var now = 10.0
        let viewModel = ImageCreatorViewModel(
            creatorFactory: { fake },
            clock: { now }
        )
        await viewModel.load()
        viewModel.input = "a slow scene"
        let generation = Task { @MainActor in await viewModel.generate() }
        while !viewModel.isRunning { await Task.yield() }
        now = 10.75

        viewModel.cancel()
        await generation.value

        #expect(viewModel.runState == .cancelled)
        #expect(viewModel.latency == 0.75)
        #expect(viewModel.output == nil)
    }

    @Test @MainActor
    func imageCreatorRejectsDuplicateRunsWhileKeepingTheOriginalRunActive() async {
        let fake = RecordingImageCreator(styles: [.illustration], suspends: true)
        let viewModel = ImageCreatorViewModel(creatorFactory: { fake })
        await viewModel.load()
        viewModel.input = "one scene"
        let first = Task { @MainActor in await viewModel.generate() }
        while !viewModel.isRunning { await Task.yield() }
        while fake.requests.isEmpty { await Task.yield() }

        viewModel.input = "another scene"
        await viewModel.generate()

        #expect(fake.requests.count == 1)
        #expect(viewModel.isRunning)
        #expect(viewModel.errorMessage == "An image generation run is already in progress.")
        viewModel.cancel()
        await first.value
    }

    @Test @MainActor
    func imagePlaygroundPageUsesIndependentSystemOwnedRoute() {
        #expect(ExperienceCatalog[.imageCreator].id != ExperienceCatalog[.imagePlayground].id)
        #expect(ExperienceCatalog[.imagePlayground].requirement == .systemUI)
    }

    @Test
    func imagePlaygroundClearsPreviousCompletionBeforeAChangedPromptIsPresented() {
        var state = ImagePlaygroundPresentationState()
        state.prompt = "first prompt"
        state.beginPresentation()
        state.recordCompletion(URL(fileURLWithPath: "/tmp/first.png"))

        state.prompt = "changed prompt"
        state.beginPresentation()

        #expect(state.completedURL == nil)
        #expect(state.isPresented)
    }

    @Test
    func imagePlaygroundCancelOrFailureAfterReopenCannotShowThePreviousCompletion() {
        var state = ImagePlaygroundPresentationState()
        state.beginPresentation()
        state.recordCompletion(URL(fileURLWithPath: "/tmp/first.png"))

        state.beginPresentation()
        state.recordCancellation()
        #expect(state.completedURL == nil)

        state.beginPresentation()
        state.recordFailure("system failed")
        #expect(state.completedURL == nil)
    }

    private func makeTestImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

#if !targetEnvironment(simulator)
struct PhysicalDeviceImageCreatorTests {
    @Test @MainActor
    func reportsImageCreatorAvailabilityOnPhysicalDevice() async {
        let viewModel = ImageCreatorViewModel()
        await viewModel.load()
        switch viewModel.availability {
        case .available:
            #expect(!viewModel.styles.isEmpty)
            print("DEVICE_RESULT|SYS-01|PASS|styles=\(viewModel.styles.count)")
        case .unavailable(let message):
            print("DEVICE_RESULT|SYS-01|BLOCKED_SYSTEM|\(message)")
        case .checking:
            Issue.record("ImageCreator remained in checking state")
            print("DEVICE_RESULT|SYS-01|FAIL_APP|checking did not finish")
        }
    }
}
#endif

private actor CancellingImageCreatorFactory {
    let result: any ImageCreatorServing
    private(set) var started = false
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<any ImageCreatorServing, Error>?

    init(result: any ImageCreatorServing) {
        self.result = result
    }

    func make() async throws -> any ImageCreatorServing {
        callCount += 1
        if callCount > 1 { return result }
        started = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor IgnoringCancellationImageCreatorFactory {
    let result: any ImageCreatorServing
    private(set) var started = false
    private var continuation: CheckedContinuation<any ImageCreatorServing, Never>?

    init(result: any ImageCreatorServing) {
        self.result = result
    }

    func make() async throws -> any ImageCreatorServing {
        started = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private final class RecordingImageCreator: ImageCreatorServing, @unchecked Sendable {
    let availableStyles: [ImageCreatorStyleOption]
    let images: [GeneratedImage]
    let failure: Error?
    let suspends: Bool
    private(set) var requests: [ImageCreatorRequest] = []

    init(
        styles: [ImageCreatorStyleOption],
        images: [GeneratedImage] = [],
        failure: Error? = nil,
        suspends: Bool = false
    ) {
        availableStyles = styles
        self.images = images
        self.failure = failure
        self.suspends = suspends
    }

    func images(for request: ImageCreatorRequest) -> AsyncThrowingStream<GeneratedImage, Error> {
        requests.append(request)
        return AsyncThrowingStream<GeneratedImage, Error>(bufferingPolicy: .unbounded) { continuation in
            if suspends {
                return
            }
            if let failure {
                continuation.finish(throwing: failure)
            } else {
                for image in images.prefix(request.limit) {
                    continuation.yield(image)
                }
                continuation.finish()
            }
        }
    }
}
