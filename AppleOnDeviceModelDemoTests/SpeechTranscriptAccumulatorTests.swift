import Foundation
import AVFAudio
import Speech
import Testing
@testable import AppleOnDeviceModelDemo

struct SpeechTranscriptAccumulatorTests {
    @Test @MainActor
    func liveSpeechUsesApplesSpokenAudioSessionConfiguration() {
        #expect(SpeechInputService.liveAudioSessionCategory == .playAndRecord)
        #expect(SpeechInputService.liveAudioSessionMode == .spokenAudio)
    }

    @Test @MainActor
    func converterKeepsAContinuousSessionAcrossBuffers() throws {
        let input = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        let output = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let converter = try SpeechAudioBufferConverter(
            inputFormat: input,
            outputFormat: output
        )

        let first = try converter.convert(makeNonZeroBuffer(format: input, frames: 4_800))
        let second = try converter.convert(makeNonZeroBuffer(format: input, frames: 4_800))

        #expect(first.format.sampleRate == 16_000)
        #expect(second.format.sampleRate == 16_000)
        // A streaming sample-rate converter carries filter delay across
        // chunks, so individual output lengths are not exactly 1,600.
        // The contract is continuous, non-empty audio from both calls.
        #expect(first.frameLength > 0)
        #expect(second.frameLength > 0)
        #expect(first.frameLength + second.frameLength >= 2_800)
        #expect(containsNonZeroSample(first))
        #expect(containsNonZeroSample(second))
    }

    private func makeNonZeroBuffer(format: AVAudioFormat, frames: Int) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frames)
        )!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<frames {
                buffer.floatChannelData![channel][frame] = 0.25
            }
        }
        return buffer
    }

    private func containsNonZeroSample(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) where channels[channel][frame] != 0 {
                return true
            }
        }
        return false
    }

    @Test @MainActor
    func activatesAudioSessionBeforeAccessingInputNode() async throws {
        var events: [String] = []

        let input = await SpeechInputService.activateBeforeAccessingInput(
            activateSession: {
                events.append("activate")
            },
            accessInput: {
                events.append("input")
                return "microphone"
            }
        )

        #expect(input == "microphone")
        #expect(events == ["activate", "input"])
    }

    @Test @MainActor
    func resolvesAnalyzerFormatFromTheCurrentMicrophoneFormat() async {
        let microphoneFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        var resolverCalls = 0

        let resolved = await SpeechInputService.compatibleAnalyzerFormat(
            microphoneFormat: microphoneFormat,
            resolver: { format in
                resolverCalls += 1
                #expect(format.sampleRate == 48_000)
                return format
            }
        )

        #expect(resolved?.sampleRate == 48_000)
        #expect(resolverCalls == 1)
    }

    @Test @MainActor
    func refreshesAnInvalidInputFormatAfterEnginePreparation() {
        var prepareCalls = 0
        let resolved = SpeechInputService.resolveInputFormat(
            initialValue: (channels: 0, rate: 0.0),
            isUsable: { $0.channels > 0 && $0.rate > 0 },
            refreshedValue: {
                prepareCalls += 1
                return (channels: 1, rate: 48_000.0)
            }
        )

        #expect(resolved?.channels == 1)
        #expect(resolved?.rate == 48_000.0)
        #expect(prepareCalls == 1)
    }

    @Test @MainActor
    func installedSpeechAssetsDoNotTriggerAnInstallationRequest() {
        #expect(SpeechInputService.assetInstallationNeeded(for: .installed) == false)
        #expect(SpeechInputService.assetInstallationNeeded(for: .supported) == true)
        #expect(SpeechInputService.assetInstallationNeeded(for: .downloading) == true)
        #expect(SpeechInputService.assetInstallationNeeded(for: .unsupported) == false)
    }

    @Test func replacesVolatileTextWithFinalText() {
        var accumulator = SpeechTranscriptAccumulator()

        accumulator.consume(text: "Hello ", isFinal: true)
        accumulator.consume(text: "wor", isFinal: false)
        #expect(accumulator.transcript == "Hello wor")

        accumulator.consume(text: "world.", isFinal: true)
        #expect(accumulator.transcript == "Hello world.")
    }

    @Test func resetClearsAllText() {
        var accumulator = SpeechTranscriptAccumulator()
        accumulator.consume(text: "Temporary", isFinal: false)

        accumulator.reset()

        #expect(accumulator.transcript.isEmpty)
    }
    @Test @MainActor
    func speechExperiencePublishesLiveTranscriptAndFinalLatency() async {
        let service = SpeechServiceStub()
        var times = [10.0, 10.6].makeIterator()
        let viewModel = SpeechExperienceViewModel(
            speechService: service,
            currentTime: { times.next()! }
        )

        await viewModel.startRecording()
        service.publishTranscript("Hello ")
        service.publishTranscript("Hello world")
        await viewModel.stopRecording()

        #expect(viewModel.transcript == "Hello world")
        #expect(abs((viewModel.speechLatency ?? 0) - 0.6) < 0.000_001)
        #expect(viewModel.isRecording == false)
        #expect(viewModel.runState == .succeeded)
    }

    @Test @MainActor
    func speechExperiencePreservesPartialThenFinalOrdering() async {
        let service = SpeechServiceStub()
        let viewModel = SpeechExperienceViewModel(speechService: service)

        await viewModel.startRecording()
        service.publishTranscript("one")
        service.publishTranscript("two")
        service.publishTranscript("two")

        #expect(viewModel.transcript == "two")
        #expect(service.publishedTranscripts == ["one", "two", "two"])
    }

    @Test @MainActor
    func speechExperienceReportsPermissionDeniedAndDoesNotRecord() async {
        let service = SpeechServiceStub()
        service.startError = SpeechInputError.microphonePermissionDenied
        let viewModel = SpeechExperienceViewModel(speechService: service)

        await viewModel.startRecording()

        #expect(viewModel.isRecording == false)
        #expect(viewModel.runState == .failed(SpeechInputError.microphonePermissionDenied.localizedDescription))
        #expect(viewModel.errorMessage == SpeechInputError.microphonePermissionDenied.localizedDescription)
    }

    @Test @MainActor
    func speechExperiencePreventsDuplicateStartWhileRecording() async {
        let service = SpeechServiceStub()
        let viewModel = SpeechExperienceViewModel(speechService: service)

        await viewModel.startRecording()
        await viewModel.startRecording()

        #expect(service.startCallCount == 1)
        #expect(viewModel.errorMessage == SpeechInputError.alreadyRecording.localizedDescription)
    }

    @Test @MainActor
    func speechExperienceHandlesCancellationDuringFinalize() async {
        let service = SpeechServiceStub()
        service.stopError = CancellationError()
        let viewModel = SpeechExperienceViewModel(speechService: service)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.runState == .cancelled)
        #expect(viewModel.isRecording == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test @MainActor
    func speechExperienceSurfacesStreamErrors() async {
        let service = SpeechServiceStub()
        let viewModel = SpeechExperienceViewModel(speechService: service)

        await viewModel.startRecording()
        service.publishError("Speech stream failed")

        #expect(viewModel.errorMessage == "Speech stream failed")
        #expect(viewModel.runState == .failed("Speech stream failed"))
    }

    @Test @MainActor
    func speechExperienceReportsFinalizeErrors() async {
        let service = SpeechServiceStub()
        service.stopError = SpeechInputError.audioFormatUnavailable
        let viewModel = SpeechExperienceViewModel(speechService: service)

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.runState == .failed(SpeechInputError.audioFormatUnavailable.localizedDescription))
        #expect(viewModel.isRecording == false)
    }

    @Test @MainActor
    func speechExperiencePreventsDuplicateStartDuringAssetPreparation() async {
        let service = SpeechServiceStub()
        service.startGate = AsyncGate()
        let viewModel = SpeechExperienceViewModel(speechService: service)

        let firstStart = Task { @MainActor in
            await viewModel.startRecording()
        }
        await service.startGate?.waitUntilEntered()
        #expect(viewModel.isPreparingAssets)
        await viewModel.startRecording()
        await service.startGate?.open()
        await firstStart.value

        #expect(service.startCallCount == 1)
        #expect(viewModel.isRecording)
    }

    @Test @MainActor
    func speechExperienceKeepsFinalizationInFlightForDuplicateStops() async {
        let service = SpeechServiceStub()
        service.stopGate = AsyncGate()
        service.stopError = SpeechInputError.audioFormatUnavailable
        let viewModel = SpeechExperienceViewModel(speechService: service)

        await viewModel.startRecording()
        let firstStop = Task { @MainActor in
            await viewModel.stopRecording()
        }
        await service.stopGate?.waitUntilEntered()
        let secondStop = Task { @MainActor in
            await viewModel.stopRecording()
        }
        await Task.yield()

        #expect(service.stopCallCount == 1)
        #expect(viewModel.runState == .finalizing)
        #expect(viewModel.isRecording)

        await service.stopGate?.open()
        await firstStop.value
        await secondStop.value

        #expect(viewModel.runState == .failed(SpeechInputError.audioFormatUnavailable.localizedDescription))
        #expect(viewModel.isRecording == false)
    }

    @Test @MainActor
    func cancellationDuringFinalizationJoinsTheExistingStop() async {
        let service = SpeechServiceStub()
        service.stopGate = AsyncGate()
        let viewModel = SpeechExperienceViewModel(speechService: service)

        await viewModel.startRecording()
        let stopTask = Task { @MainActor in
            await viewModel.stopRecording()
        }
        await service.stopGate?.waitUntilEntered()

        let cancelTask = Task { @MainActor in
            await viewModel.cancelRecording()
        }
        await Task.yield()

        #expect(service.stopCallCount == 1)
        #expect(viewModel.runState == .finalizing)
        #expect(viewModel.isRecording)

        await service.stopGate?.open()
        await stopTask.value
        await cancelTask.value

        #expect(service.stopCallCount == 1)
        #expect(viewModel.runState == .succeeded)
        #expect(viewModel.isRecording == false)
    }

    @Test @MainActor
    func streamErrorArrivingDuringFinalizationIsNotOverwrittenBySuccess() async {
        let service = SpeechServiceStub()
        service.stopGate = AsyncGate()
        let viewModel = SpeechExperienceViewModel(speechService: service)

        await viewModel.startRecording()
        let stopTask = Task { @MainActor in
            await viewModel.stopRecording()
        }
        await service.stopGate?.waitUntilEntered()
        service.publishError("Late Speech stream failure")

        #expect(viewModel.runState == .failed("Late Speech stream failure"))
        await service.stopGate?.open()
        await stopTask.value

        #expect(viewModel.runState == .failed("Late Speech stream failure"))
        #expect(viewModel.errorMessage == "Late Speech stream failure")
    }

    @Test @MainActor
    func audioSessionDeactivationFailureIsObservableButDoesNotReplacePrimaryError() {
        let cleanup = SpeechInputService.deactivationError(primaryError: nil) {
            throw SpeechCleanupTestError.deactivation
        }
        #expect(cleanup?.localizedDescription == "Audio session deactivation failed.")

        let primary = SpeechInputError.audioFormatUnavailable
        let preserved = SpeechInputService.deactivationError(primaryError: primary) {
            throw SpeechCleanupTestError.deactivation
        }
        #expect(preserved?.localizedDescription == primary.localizedDescription)
    }

    @Test @MainActor
    func finalizationErrorSurvivesSuccessfulAudioSessionDeactivation() {
        let primary = SpeechInputError.audioFormatUnavailable
        let outcome = SpeechInputService.combineFinalizationAndDeactivation(
            finalizationError: primary,
            deactivate: {}
        )

        #expect(outcome.error?.localizedDescription == primary.localizedDescription)
        #expect(outcome.cleanupErrorMessage == nil)
    }

    @Test @MainActor
    func finalizationErrorRemainsPrimaryWhenDeactivationAlsoFails() {
        let primary = SpeechInputError.audioFormatUnavailable
        let outcome = SpeechInputService.combineFinalizationAndDeactivation(
            finalizationError: primary,
            deactivate: { throw SpeechCleanupTestError.deactivation }
        )

        #expect(outcome.error?.localizedDescription == primary.localizedDescription)
        #expect(outcome.cleanupErrorMessage == SpeechInputError.audioSessionDeactivationFailed.localizedDescription)
    }

    @Test @MainActor
    func installedSpeechAssetsSkipTheInstallationRequest() async throws {
        let box = AssetStatusBox(statuses: [.installed])
        let preparer = SpeechAssetPreparer(
            statusProvider: { box.nextStatus() },
            install: { box.recordInstall() }
        )

        try await preparer.prepare()

        #expect(box.installCount() == 0)
        #expect(box.statusCount() == 1)
    }

    @Test @MainActor
    func supportedSpeechAssetsDownloadThenRequireInstalledPostStatus() async throws {
        let box = AssetStatusBox(statuses: [.supported, .installed])
        let preparer = SpeechAssetPreparer(
            statusProvider: { box.nextStatus() },
            install: { box.recordInstall() }
        )

        try await preparer.prepare()

        #expect(box.installCount() == 1)
        #expect(box.statusCount() == 2)
    }

    @Test @MainActor
    func unsupportedOrUninstalledPostStatusFailsAssetPreparation() async {
        let unsupported = AssetStatusBox(statuses: [.unsupported])
        let unsupportedPreparer = SpeechAssetPreparer(
            statusProvider: { unsupported.nextStatus() },
            install: { unsupported.recordInstall() }
        )
        await #expect(throws: SpeechInputError.speechAssetsUnavailable) {
            try await unsupportedPreparer.prepare()
        }

        let incomplete = AssetStatusBox(statuses: [.downloading, .supported])
        let incompletePreparer = SpeechAssetPreparer(
            statusProvider: { incomplete.nextStatus() },
            install: { incomplete.recordInstall() }
        )
        await #expect(throws: SpeechInputError.speechAssetsUnavailable) {
            try await incompletePreparer.prepare()
        }

        let failedInstall = AssetStatusBox(statuses: [.supported])
        let failedInstallPreparer = SpeechAssetPreparer(
            statusProvider: { failedInstall.nextStatus() },
            install: { throw SpeechInputError.speechAssetsUnavailable }
        )
        await #expect(throws: SpeechInputError.speechAssetsUnavailable) {
            try await failedInstallPreparer.prepare()
        }
    }
}

private enum SpeechCleanupTestError: Error {
    case deactivation
}

@MainActor
private final class AssetStatusBox {
    private var statuses: [AssetInventory.Status]
    private var installs = 0
    private var reads = 0

    init(statuses: [AssetInventory.Status]) {
        self.statuses = statuses
    }

    func nextStatus() -> AssetInventory.Status {
        reads += 1
        return statuses.isEmpty ? .unsupported : statuses.removeFirst()
    }

    func recordInstall() {
        installs += 1
    }

    func installCount() -> Int { installs }
    func statusCount() -> Int { reads }
}

@MainActor
private final class SpeechServiceStub: SpeechInputServing {
    var isRecording = false
    var startError: Error?
    var stopError: Error?
    var stopGate: AsyncGate?
    var stopCallCount = 0
    var startCallCount = 0
    var startGate: AsyncGate?
    var publishedTranscripts: [String] = []
    private var transcriptHandler: SpeechInputService.TranscriptHandler?
    private var errorHandler: SpeechInputService.ErrorHandler?

    func startTranscribing(
        locale: Locale,
        onTranscript: @escaping SpeechInputService.TranscriptHandler,
        onError: @escaping SpeechInputService.ErrorHandler
    ) async throws {
        startCallCount += 1
        transcriptHandler = onTranscript
        errorHandler = onError
        if let startGate {
            await startGate.enter()
        }
        if let startError { throw startError }
        isRecording = true
    }

    func stopTranscribing() async throws {
        stopCallCount += 1
        if let stopGate {
            await stopGate.enter()
        }
        if let stopError {
            isRecording = false
            throw stopError
        }
        isRecording = false
    }

    func publishTranscript(_ transcript: String) {
        publishedTranscripts.append(transcript)
        transcriptHandler?(transcript)
    }

    func publishError(_ message: String) {
        errorHandler?(message)
    }
}

private actor AsyncGate {
    private var entered = false
    private var openContinuations: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        await withCheckedContinuation { continuation in
            openContinuations.append(continuation)
        }
    }

    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }

    func open() {
        let continuations = openContinuations
        openContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

#if !targetEnvironment(simulator)
@MainActor
private final class PhysicalSpeechCapture {
    var transcript = ""
    var error = ""
}

struct PhysicalDeviceSpeechTests {
    @Test @MainActor
    func transcribesAcousticInputOnPhysicalDevice() async throws {
        let capture = PhysicalSpeechCapture()
        let service = SpeechInputService()

        try await service.startTranscribing(
            locale: Locale(identifier: "en_US"),
            onTranscript: { text in
                capture.transcript = text
                print("DEVICE_RESULT|AUDIO-PARTIAL|\(text)")
            },
            onError: { message in
                capture.error = message
                print("DEVICE_RESULT|AUDIO-ERROR|\(message)")
            }
        )
        print("DEVICE_RESULT|AUDIO-READY|Start acoustic phrase now")

        try await Task.sleep(for: .seconds(12))
        try await service.stopTranscribing()

        #expect(capture.error.isEmpty)
        #expect(!capture.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if capture.transcript.isEmpty {
            print("DEVICE_RESULT|AUDIO-03|FAIL_APP|No transcript returned")
        } else {
            print("DEVICE_RESULT|AUDIO-03|PASS|\(capture.transcript)")
        }
    }
}
#endif
