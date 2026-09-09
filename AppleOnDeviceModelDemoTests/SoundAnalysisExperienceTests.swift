import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

@MainActor
struct SoundAnalysisExperienceTests {
    @Test
    func classificationsKeepTopThreeAboveThreshold() {
        let output = SoundClassification.filtered([
            .init(label: "speech", confidence: 0.9),
            .init(label: "music", confidence: 0.7),
            .init(label: "noise", confidence: 0.5),
            .init(label: "silence", confidence: 0.02)
        ], threshold: 0.1, limit: 3)

        #expect(output.map(\.label) == ["speech", "music", "noise"])
    }

    @Test
    func filteringUsesLabelAsDeterministicTieBreak() {
        let output = SoundClassification.filtered([
            .init(label: "zeta", confidence: 0.5),
            .init(label: "alpha", confidence: 0.5),
            .init(label: "middle", confidence: 0.5)
        ], threshold: 0.1, limit: 3)

        #expect(output.map(\.label) == ["alpha", "middle", "zeta"])
    }

    @Test
    func emptyOrBelowThresholdResultsAreValidEmptyState() {
        #expect(SoundClassification.filtered([], threshold: 0.1, limit: 3).isEmpty)
        #expect(SoundClassification.filtered([
            .init(label: "silence", confidence: 0.09)
        ], threshold: 0.1, limit: 3).isEmpty)
    }

    @Test
    func inputFormatIsRefreshedOnceWhenInitialFormatIsNotUsable() {
        var refreshCount = 0
        let output = SoundAnalysisInputService.resolveInputFormat(
            initialValue: (channels: 0, rate: 0.0),
            isUsable: { $0.channels > 0 && $0.rate > 0 },
            refreshedValue: {
                refreshCount += 1
                return (channels: 1, rate: 48_000.0)
            }
        )

        #expect(output?.channels == 1)
        #expect(output?.rate == 48_000.0)
        #expect(refreshCount == 1)
    }

    @Test
    func deactivationFailureIsRecordedWithoutReplacingPrimaryError() {
        let primary = SoundAnalysisInputError.audioFormatUnavailable
        let result = SoundAnalysisInputService.combineFinalizationAndDeactivation(
            finalizationError: primary,
            deactivate: { throw SoundCleanupTestError.failed }
        )

        #expect(result.error?.localizedDescription == primary.localizedDescription)
        #expect(result.cleanupErrorMessage == SoundAnalysisInputError.audioSessionDeactivationFailed.localizedDescription)
    }

    @Test
    func viewModelPublishesEachFilteredClassificationUpdate() async {
        let service = SoundServiceStub()
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)

        await viewModel.startAnalyzing()
        service.publish([
            .init(label: "music", confidence: 0.8),
            .init(label: "speech", confidence: 0.9)
        ])
        service.publish([
            .init(label: "rain", confidence: 0.95)
        ])

        #expect(viewModel.classifications.map(\.label) == ["rain"])
        #expect(viewModel.runState == .recording)
    }

    @Test
    func viewModelPublishesLatencyAfterStop() async {
        let service = SoundServiceStub()
        var times = [10.0, 10.75].makeIterator()
        let viewModel = SoundAnalysisExperienceViewModel(
            soundService: service,
            currentTime: { times.next()! }
        )

        await viewModel.startAnalyzing()
        await viewModel.stopAnalyzing()

        #expect(viewModel.analysisLatency == 0.75)
        #expect(viewModel.runState == .succeeded)
        #expect(!viewModel.isRecording)
    }

    @Test
    func duplicateStartsAreSuppressedWithExplicitError() async {
        let service = SoundServiceStub()
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)

        await viewModel.startAnalyzing()
        await viewModel.startAnalyzing()

        #expect(service.startCallCount == 1)
        #expect(viewModel.errorMessage == SoundAnalysisInputError.alreadyRecording.localizedDescription)
        #expect(viewModel.isRecording)
    }

    @Test
    func duplicateStopsDoNotStopTheServiceTwice() async {
        let service = SoundServiceStub()
        service.stopGate = SoundAsyncGate()
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)

        await viewModel.startAnalyzing()
        let first = Task { @MainActor in await viewModel.stopAnalyzing() }
        await service.stopGate?.waitUntilEntered()
        let second = Task { @MainActor in await viewModel.stopAnalyzing() }
        await Task.yield()

        #expect(service.stopCallCount == 1)
        await service.stopGate?.open()
        await first.value
        await second.value
    }

    @Test
    func streamErrorsArePublishedWithoutPretendingTheyAreTranscripts() async {
        let service = SoundServiceStub()
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)

        await viewModel.startAnalyzing()
        service.publishError("Sound analysis failed")

        #expect(viewModel.errorMessage == "Sound analysis failed")
        #expect(viewModel.classifications.isEmpty)
        #expect(viewModel.runState == .failed("Sound analysis failed"))
    }

    @Test
    func streamErrorThenStopKeepsFailedTerminalStateAndMessage() async {
        let service = SoundServiceStub()
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)

        await viewModel.startAnalyzing()
        service.publishError("Late sound analysis failure")
        await viewModel.stopAnalyzing()

        #expect(viewModel.runState == .failed("Late sound analysis failure"))
        #expect(viewModel.errorMessage == "Late sound analysis failure")
        #expect(!viewModel.isFinalizing)
    }

    @Test
    func cancellingBlockedStartRejectsLateSuccess() async {
        let service = SoundServiceStub()
        service.startGate = SoundAsyncGate()
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)
        let startTask = Task { @MainActor in await viewModel.startAnalyzing() }

        await service.startGate?.waitUntilEntered()
        await viewModel.cancelAnalyzing()
        #expect(viewModel.runState == .cancelled)
        await service.startGate?.open()
        await startTask.value

        #expect(viewModel.runState == .cancelled)
        #expect(!viewModel.isRecording)
    }

    @Test
    func cancellingBlockedStartRejectsLateError() async {
        let service = SoundServiceStub()
        service.startGate = SoundAsyncGate()
        service.startError = SoundAnalysisInputError.audioFormatUnavailable
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)
        let startTask = Task { @MainActor in await viewModel.startAnalyzing() }

        await service.startGate?.waitUntilEntered()
        await viewModel.cancelAnalyzing()
        #expect(viewModel.runState == .cancelled)
        await service.startGate?.open()
        await startTask.value

        #expect(viewModel.runState == .cancelled)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isRecording)
    }

    @Test
    func lateStreamErrorDuringBlockedStopWinsOverSuccess() async {
        let service = SoundServiceStub()
        service.stopGate = SoundAsyncGate()
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)

        await viewModel.startAnalyzing()
        let stopTask = Task { @MainActor in await viewModel.stopAnalyzing() }
        await service.stopGate?.waitUntilEntered()
        service.publishError("Failure while finalizing")
        await service.stopGate?.open()
        await stopTask.value

        #expect(viewModel.runState == .failed("Failure while finalizing"))
        #expect(viewModel.errorMessage == "Failure while finalizing")
        #expect(!viewModel.isFinalizing)
    }

    @Test
    func cancellingRecordingInvalidatesLateResultAndErrorCallbacks() async {
        let service = SoundServiceStub()
        service.stopGate = SoundAsyncGate()
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)

        await viewModel.startAnalyzing()
        let cancelTask = Task { @MainActor in await viewModel.cancelAnalyzing() }
        await service.stopGate?.waitUntilEntered()
        service.publish([
            .init(label: "late", confidence: 1.0)
        ])
        service.publishError("Late callback")
        await service.stopGate?.open()
        await cancelTask.value

        #expect(viewModel.runState == .cancelled)
        #expect(viewModel.classifications.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func cancellationIsNormalTerminalState() async {
        let service = SoundServiceStub()
        let viewModel = SoundAnalysisExperienceViewModel(soundService: service)

        await viewModel.startAnalyzing()
        await viewModel.cancelAnalyzing()

        #expect(viewModel.runState == .cancelled)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isRecording)
    }
}

#if !targetEnvironment(simulator)
@MainActor
private final class PhysicalSoundCapture {
    var classifications: [SoundClassification] = []
    var error = ""
}

struct PhysicalDeviceSoundAnalysisTests {
    @Test @MainActor
    func classifiesAcousticInputOnPhysicalDevice() async throws {
        let capture = PhysicalSoundCapture()
        let service = SoundAnalysisInputService()
        print("DEVICE_RESULT|SOUND-READY|Start acoustic phrase now")

        try await service.startAnalyzing(
            onClassifications: { values in
                capture.classifications = SoundClassification.filtered(values, threshold: 0.1)
                if let first = capture.classifications.first {
                    print("DEVICE_RESULT|SOUND-PARTIAL|\(first.label)|\(first.confidence)")
                }
            },
            onError: { message in
                capture.error = message
                print("DEVICE_RESULT|SOUND-ERROR|\(message)")
            }
        )
        try await Task.sleep(for: .seconds(8))
        try await service.stopAnalyzing()

        #expect(capture.error.isEmpty)
        #expect(!capture.classifications.isEmpty)
        if let first = capture.classifications.first {
            print("DEVICE_RESULT|AUDIO-08|PASS|\(first.label)|\(first.confidence)")
        } else {
            print("DEVICE_RESULT|AUDIO-08|FAIL_APP|No classification returned")
        }
    }
}
#endif

@MainActor
private final class SoundServiceStub: SoundAnalysisServing {
    var isRecording = false
    var startCallCount = 0
    var stopCallCount = 0
    var startError: Error?
    var stopError: Error?
    var stopGate: SoundAsyncGate?
    var startGate: SoundAsyncGate?
    private var classificationsHandler: SoundAnalysisInputService.ClassificationHandler?
    private var errorHandler: SoundAnalysisInputService.ErrorHandler?

    func startAnalyzing(
        onClassifications: @escaping SoundAnalysisInputService.ClassificationHandler,
        onError: @escaping SoundAnalysisInputService.ErrorHandler
    ) async throws {
        startCallCount += 1
        classificationsHandler = onClassifications
        errorHandler = onError
        if let startGate { await startGate.enter() }
        if let startError { throw startError }
        isRecording = true
    }

    func stopAnalyzing() async throws {
        stopCallCount += 1
        if let stopGate { await stopGate.enter() }
        isRecording = false
        if let stopError { throw stopError }
    }

    func publish(_ classifications: [SoundClassification]) {
        classificationsHandler?(classifications)
    }

    func publishError(_ message: String) {
        errorHandler?(message)
    }
}

private actor SoundAsyncGate {
    private var entered = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }

    func open() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private enum SoundCleanupTestError: Error {
    case failed
}
