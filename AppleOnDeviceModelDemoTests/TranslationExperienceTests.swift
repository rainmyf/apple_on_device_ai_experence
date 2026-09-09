import Foundation
import Testing
import Translation
@testable import AppleOnDeviceModelDemo

@MainActor
struct TranslationExperienceTests {
    @Test func assetStatusesMapToReadyDownloadOrUnsupportedBoundaries() {
        #expect(TranslationAssetAvailability(.installed) == .ready)
        #expect(TranslationAssetAvailability(.supported) == .assetsRequired)
        #expect(TranslationAssetAvailability(.unsupported) == .unsupported)
    }

    @Test func viewModelBuildsExactSourceTargetConfiguration() {
        let viewModel = TranslationViewModel(
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            assetAvailability: .ready,
            translator: { _ in "translated" }
        )

        #expect(viewModel.configuration.source == .init(identifier: "en"))
        #expect(viewModel.configuration.target == .init(identifier: "zh-Hans"))
        #expect(viewModel.requiresAppleIntelligence == false)
        #expect(viewModel.usesCloudFallback == false)
    }

    @Test func emptyInputIsRejectedBeforeTranslation() async {
        var calls = 0
        let viewModel = TranslationViewModel(assetAvailability: .ready, translator: { _ in
            calls += 1
            return "unexpected"
        })
        viewModel.input = "  \n"

        await viewModel.translate()

        #expect(calls == 0)
        #expect(viewModel.output == nil)
        #expect(viewModel.errorMessage == "Enter text to translate.")
        #expect(viewModel.runState == .failed("Enter text to translate."))
    }

    @Test func successfulTranslationPublishesOutputAndLatency() async {
        var clockValues = [10.0, 10.4]
        let viewModel = TranslationViewModel(
            assetAvailability: .ready,
            translator: { text in "ZH:\(text)" },
            clock: { clockValues.removeFirst() }
        )
        viewModel.input = "Hello"

        await viewModel.translate()

        #expect(viewModel.output == "ZH:Hello")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.runState == .succeeded)
        #expect(abs((viewModel.latency ?? .nan) - 0.4) < 0.000_001)
        #expect(viewModel.isRunning == false)
    }

    @Test func unavailableAssetsAreReportedWithoutCallingTranslator() async {
        var calls = 0
        let viewModel = TranslationViewModel(assetAvailability: .assetsRequired, translator: { _ in
            calls += 1
            return "unexpected"
        })
        viewModel.input = "Hello"

        await viewModel.translate()

        #expect(calls == 0)
        #expect(viewModel.output == nil)
        #expect(viewModel.errorMessage == "Translation language assets are not ready.")
        #expect(viewModel.availabilityDetail == "Download the source and target language assets to run this page.")
    }

    @Test func translatorErrorsArePublishedAsErrors() async {
        let viewModel = TranslationViewModel(assetAvailability: .ready, translator: { _ in
            throw TranslationTestError.failed
        })
        viewModel.input = "Hello"

        await viewModel.translate()

        #expect(viewModel.output == nil)
        #expect(viewModel.errorMessage == "translation failed")
        #expect(viewModel.runState == .failed("translation failed"))
    }

    @Test func cancellationIsVisibleAndNotReportedAsError() async {
        let viewModel = TranslationViewModel(assetAvailability: .ready, translator: { _ in
            throw CancellationError()
        })
        viewModel.input = "Hello"

        await viewModel.translate()

        #expect(viewModel.output == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.runState == .cancelled)
    }

    @Test func duplicateTranslationIsSuppressedWhileFirstIsRunning() async {
        var release: (() -> Void)?
        var calls = 0
        let viewModel = TranslationViewModel(assetAvailability: .ready, translator: { _ in
            calls += 1
            return await withCheckedContinuation { continuation in
                release = { continuation.resume(returning: "first") }
            }
        })
        viewModel.input = "Hello"

        let first = Task { await viewModel.translate() }
        while release == nil { await Task.yield() }
        await viewModel.translate()

        #expect(calls == 1)
        #expect(viewModel.isRunning)
        release?()
        await first.value
        #expect(viewModel.output == "first")
    }

    @Test func changingLanguagesInvalidatesConfiguration() {
        let viewModel = TranslationViewModel(sourceLanguage: "en", targetLanguage: "fr", assetAvailability: .ready, translator: { _ in "" })
        let oldVersion = viewModel.configuration.version

        viewModel.setLanguages(source: "de", target: "ja")

        #expect(viewModel.configuration.source == .init(identifier: "de"))
        #expect(viewModel.configuration.target == .init(identifier: "ja"))
        #expect(viewModel.configuration.version > oldVersion)
    }

    @Test func sameLanguagePairIsUnsupportedWithoutMisreportingMissingAssets() async {
        let viewModel = TranslationViewModel(
            sourceLanguage: "en",
            targetLanguage: "en",
            translator: { _ in "unexpected" },
            availabilityProvider: { _, _ in .supported }
        )

        await viewModel.refreshAvailability()

        #expect(viewModel.availability == .unsupported)
        #expect(viewModel.availabilityDetail == "This language pair is not supported by the system translation service.")
    }

    @Test func realAvailabilityProviderIsAskedForCurrentSourceAndTarget() async {
        var observed: (String, String)?
        let viewModel = TranslationViewModel(
            sourceLanguage: "en",
            targetLanguage: "fr",
            translator: { _ in "translated" },
            availabilityProvider: { source, target in
                observed = (source.languageCode?.identifier ?? "", target?.languageCode?.identifier ?? "")
                return .installed
            }
        )

        await viewModel.refreshAvailability()

        #expect(observed?.0 == "en")
        #expect(observed?.1 == "fr")
        #expect(viewModel.availability == .ready)
    }

    @Test func cancellationErrorAlreadyCancelledIsAVisibleCancellation() async {
        let viewModel = TranslationViewModel(assetAvailability: .ready, translator: { _ in
            throw TranslationError.alreadyCancelled
        })
        viewModel.input = "Hello"

        await viewModel.translate()

        #expect(viewModel.runState == .cancelled)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func cancellingInjectedTranslatorCancelsChildTaskAndResetsRunningState() async {
        let cancellation = CancellationProbe()
        let viewModel = TranslationViewModel(assetAvailability: .ready, translator: { _ in
            cancellation.started = true
            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    cancellation.release = { result in continuation.resume(with: result) }
                }
            }, onCancel: {
                cancellation.cancellationObserved = true
                cancellation.release?(.failure(CancellationError()))
            })
        })
        viewModel.input = "Hello"

        let task = Task { await viewModel.translate() }
        while !cancellation.started { await Task.yield() }
        viewModel.cancel()

        #expect(cancellation.cancellationObserved)
        #expect(!viewModel.isRunning)
        #expect(viewModel.runState == .cancelled)
        await task.value
    }

    @Test func languageChangeCancelsAndDetachesPreviousSession() async {
        let session = TestTranslationSession()
        let viewModel = TranslationViewModel(assetAvailability: .ready, translator: { _ in "unused" })
        let version = viewModel.configuration.version
        await viewModel.attach(session: session, configurationVersion: version)

        viewModel.setLanguages(source: "de", target: "ja")

        #expect(session.cancelWasCalled)
        #expect(!viewModel.isReady)
        #expect(viewModel.availability == .assetsRequired)
    }

    @Test func staleSessionCannotAttachAfterConfigurationChanges() async {
        let oldSession = TestTranslationSession(isReady: true)
        let viewModel = TranslationViewModel(assetAvailability: .ready, translator: { _ in "unused" })
        let oldVersion = viewModel.configuration.version
        viewModel.setLanguages(source: "de", target: "ja")

        await viewModel.attach(session: oldSession, configurationVersion: oldVersion)

        #expect(!viewModel.isReady)
        #expect(viewModel.selectedSourceLanguage == "de")
        #expect(viewModel.selectedTargetLanguage == "ja")
    }

    @Test func deactivationCancelsActiveTranslationAndSession() async {
        let session = TestTranslationSession(translationDelay: .seconds(60))
        let viewModel = TranslationViewModel(assetAvailability: .ready, translator: { _ in
            "unused"
        }, availabilityProvider: { _, _ in .installed })
        let version = viewModel.configuration.version
        await viewModel.attach(session: session, configurationVersion: version)
        viewModel.input = "Hello"
        let task = Task { await viewModel.translate() }
        while !viewModel.isRunning { await Task.yield() }

        viewModel.deactivate()

        #expect(session.cancelWasCalled)
        #expect(!viewModel.isRunning)
        #expect(viewModel.runState == .cancelled)
        await task.value
    }

    @Test func delayedAvailabilityFromOldConfigurationCannotOverwriteNewLanguageState() async {
        let provider = DelayedStatusProvider()
        let viewModel = TranslationViewModel(
            sourceLanguage: "en",
            targetLanguage: "fr",
            translator: { _ in "unused" },
            availabilityProvider: { source, target in
                await provider.status(from: source, to: target)
            }
        )

        let oldRefresh = Task { await viewModel.refreshAvailability() }
        while await provider.callCount == 0 { await Task.yield() }
        viewModel.setLanguages(source: "de", target: "ja")
        await provider.release(.installed)
        await oldRefresh.value

        #expect(viewModel.selectedSourceLanguage == "de")
        #expect(viewModel.selectedTargetLanguage == "ja")
        #expect(viewModel.availability == .assetsRequired)
        #expect(!viewModel.isReady)
    }

    @Test func oldPrepareCompletionCannotMarkNewConfigurationReady() async {
        let prepareGate = PrepareGate()
        let provider = ImmediateStatusProvider()
        let session = TestTranslationSession(prepareGate: prepareGate)
        let viewModel = TranslationViewModel(
            sourceLanguage: "en",
            targetLanguage: "fr",
            assetAvailability: .ready,
            translator: { _ in "unused" },
            availabilityProvider: { source, target in
                await provider.status(from: source, to: target)
            }
        )
        let version = viewModel.configuration.version
        await viewModel.attach(session: session, configurationVersion: version)
        viewModel.input = "Hello"
        let oldRun = Task { await viewModel.translate() }
        while !session.prepareStarted { await Task.yield() }

        viewModel.setLanguages(source: "de", target: "ja")
        await prepareGate.release()
        await oldRun.value

        #expect(viewModel.selectedSourceLanguage == "de")
        #expect(viewModel.selectedTargetLanguage == "ja")
        #expect(viewModel.availability == .assetsRequired)
        #expect(!viewModel.isReady)
    }
}

#if !targetEnvironment(simulator)
struct PhysicalDeviceTranslationTests {
    @Test
    func reportsEnglishToSimplifiedChineseAssetStatusOnPhysicalDevice() async {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: "en"),
            to: Locale.Language(identifier: "zh-Hans")
        )
        print("DEVICE_RESULT|LANG-01|\(TranslationAssetAvailability(status) == .ready ? "PASS" : "BLOCKED_SYSTEM")|\(status)")
    }
}
#endif

private enum TranslationTestError: LocalizedError {
    case failed
    var errorDescription: String? { "translation failed" }
}

@MainActor
private final class TestTranslationSession: TranslationSessionServicing {
    var isReadyValue: Bool
    let translationDelay: Duration?
    let prepareGate: PrepareGate?
    private(set) var prepareStarted = false
    private(set) var cancelWasCalled = false

    init(isReady: Bool = true, translationDelay: Duration? = nil, prepareGate: PrepareGate? = nil) {
        isReadyValue = isReady
        self.translationDelay = translationDelay
        self.prepareGate = prepareGate
    }

    var isReady: Bool { get async { isReadyValue } }

    func prepareTranslation() async throws {
        prepareStarted = true
        await prepareGate?.wait()
    }

    func translate(_ string: String) async throws -> String {
        if let translationDelay { try await Task.sleep(for: translationDelay) }
        return "session:\(string)"
    }

    func cancel() { cancelWasCalled = true }
}

private final class CancellationProbe: @unchecked Sendable {
    var started = false
    var cancellationObserved = false
    var release: ((Result<String, Error>) -> Void)?
}

private actor DelayedStatusProvider {
    private(set) var callCount = 0
    private var waiter: CheckedContinuation<LanguageAvailability.Status, Never>?

    func status(from _: Locale.Language, to _: Locale.Language?) async -> LanguageAvailability.Status {
        callCount += 1
        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func release(_ status: LanguageAvailability.Status) {
        waiter?.resume(returning: status)
        waiter = nil
    }
}

private actor ImmediateStatusProvider {
    func status(from _: Locale.Language, to _: Locale.Language?) -> LanguageAvailability.Status { .installed }
}

private actor PrepareGate {
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
}
