@preconcurrency import AVFAudio
import Foundation
import Speech

private final class AudioConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var wasSupplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

final class SpeechAudioBufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw SpeechInputError.audioConversionFailed
        }
        converter.primeMethod = .none
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard inputBuffer.frameLength > 0, inputBuffer.format.sampleRate > 0 else {
            throw SpeechInputError.audioConversionFailed
        }

        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(
            max(1, ceil(Double(inputBuffer.frameLength) * ratio) + 1)
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            throw SpeechInputError.audioConversionFailed
        }

        let converterInput = AudioConverterInput(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            guard !converterInput.wasSupplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            converterInput.wasSupplied = true
            inputStatus.pointee = .haveData
            return converterInput.buffer
        }

        guard status != .error, conversionError == nil, outputBuffer.frameLength > 0 else {
            throw conversionError ?? SpeechInputError.audioConversionFailed
        }
        return outputBuffer
    }
}

private final class SpeechAudioConversionLogState: @unchecked Sendable {
    var bufferCount = 0
}

struct SpeechTranscriptAccumulator: Sendable {
    private(set) var finalizedTranscript = ""
    private(set) var volatileTranscript = ""

    var transcript: String {
        finalizedTranscript + volatileTranscript
    }

    mutating func consume(text: String, isFinal: Bool) {
        if isFinal {
            volatileTranscript = ""
            finalizedTranscript += text
        } else {
            volatileTranscript = text
        }
    }

    mutating func consume(result: SpeechTranscriber.Result) {
        consume(text: String(result.text.characters), isFinal: result.isFinal)
    }

    mutating func reset() {
        finalizedTranscript = ""
        volatileTranscript = ""
    }
}

enum SpeechInputError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case localeNotSupported
    case speechAssetsUnavailable
    case audioFormatUnavailable
    case audioConversionFailed
    case alreadyRecording
    case audioSessionDeactivationFailed

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone permission was denied. Enable it in Settings and try again."
        case .localeNotSupported:
            "SpeechTranscriber does not support the current locale."
        case .speechAssetsUnavailable:
            "The on-device Speech model assets are unavailable."
        case .audioFormatUnavailable:
            "No audio format compatible with SpeechAnalyzer is available."
        case .audioConversionFailed:
            "Microphone audio could not be converted for SpeechAnalyzer."
        case .alreadyRecording:
            "A recording is already in progress."
        case .audioSessionDeactivationFailed:
            "Audio session deactivation failed."
        }
    }
}

@MainActor
protocol SpeechAssetPreparing: AnyObject {
    func prepare() async throws
}

struct SpeechDeactivationResult {
    let error: Error?
    let cleanupErrorMessage: String?
}

@MainActor
final class SpeechAssetPreparer: SpeechAssetPreparing {
    typealias StatusProvider = @MainActor () async -> AssetInventory.Status
    typealias Installer = @MainActor () async throws -> Void

    private let statusProvider: StatusProvider
    private let install: Installer

    init(statusProvider: @escaping StatusProvider, install: @escaping Installer) {
        self.statusProvider = statusProvider
        self.install = install
    }

    init(transcriber: SpeechTranscriber) {
        statusProvider = {
            await AssetInventory.status(forModules: [transcriber])
        }
        install = {
            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) else {
                throw SpeechInputError.speechAssetsUnavailable
            }
            try await request.downloadAndInstall()
        }
    }

    func prepare() async throws {
        let initialStatus = await statusProvider()
        guard initialStatus != .unsupported else {
            throw SpeechInputError.speechAssetsUnavailable
        }
        guard initialStatus != .installed else { return }

        try await install()
        guard await statusProvider() == .installed else {
            throw SpeechInputError.speechAssetsUnavailable
        }
    }
}

@MainActor
protocol SpeechInputServing: AnyObject {
    var isRecording: Bool { get }

    func startTranscribing(
        locale: Locale,
        onTranscript: @escaping SpeechInputService.TranscriptHandler,
        onError: @escaping SpeechInputService.ErrorHandler
    ) async throws

    func stopTranscribing() async throws
}

@MainActor
final class SpeechInputService {
    static let liveAudioSessionCategory: AVAudioSession.Category = .playAndRecord
    static let liveAudioSessionMode: AVAudioSession.Mode = .spokenAudio

    typealias TranscriptHandler = @MainActor @Sendable (String) -> Void
    typealias ErrorHandler = @MainActor @Sendable (String) -> Void

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var audioBufferConverter: SpeechAudioBufferConverter?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private let audioSessionDeactivator: () throws -> Void

    private(set) var isRecording = false
    private(set) var lastCleanupErrorMessage: String?

    init(audioSessionDeactivator: @escaping () throws -> Void = {
        try AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }) {
        self.audioSessionDeactivator = audioSessionDeactivator
    }

    func startTranscribing(
        locale requestedLocale: Locale = .current,
        onTranscript: @escaping TranscriptHandler,
        onError: @escaping ErrorHandler
    ) async throws {
#if targetEnvironment(simulator)
        onError("模拟器不支持端侧语音转写，请在真机或 mac 上运行。")
        throw SpeechInputError.speechAssetsUnavailable
#else

        lastCleanupErrorMessage = nil
        guard !isRecording else {
            throw SpeechInputError.alreadyRecording
        }
        guard await requestMicrophonePermission() else {
            throw SpeechInputError.microphonePermissionDenied
        }

        let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        )
        guard let locale else {
            throw SpeechInputError.localeNotSupported
        }

        print("[SpeechInput] Using locale: \(locale.identifier)")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let assetPreparer: any SpeechAssetPreparing = SpeechAssetPreparer(transcriber: transcriber)
        try await assetPreparer.prepare()

        do {
            let inputNode = try await Self.activateBeforeAccessingInput(
                activateSession: { try await self.configureAudioSession() },
                accessInput: { self.audioEngine.inputNode }
            )
            print("[SpeechInput] Input node: \(inputNode)")
            let initialMicrophoneFormat = inputNode.outputFormat(forBus: 0)
            print("[SpeechInput] Input node format before check: ch=\(initialMicrophoneFormat.channelCount), rate=\(initialMicrophoneFormat.sampleRate)")
            guard let microphoneFormat = Self.resolveInputFormat(
                initialFormat: initialMicrophoneFormat,
                refreshedFormat: {
                    audioEngine.prepare()
                    let refreshed = inputNode.outputFormat(forBus: 0)
                    print("[SpeechInput] Input node format after prepare: ch=\(refreshed.channelCount), rate=\(refreshed.sampleRate)")
                    return refreshed
                }
            ) else {
                onError("未检测到有效的麦克风输入格式。请检查系统输入设备与麦克风权限，并确保未被其他应用占用。")
                throw SpeechInputError.audioFormatUnavailable
            }

            guard let analyzerFormat = await Self.compatibleAnalyzerFormat(
                microphoneFormat: microphoneFormat,
                resolver: { format in
                    await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [transcriber],
                        considering: format
                    )
                }
            ) else {
                throw SpeechInputError.audioFormatUnavailable
            }
            print(
                "[SpeechInput] Analyzer format: common=\(analyzerFormat.commonFormat.rawValue), "
                    + "interleaved=\(analyzerFormat.isInterleaved), ch=\(analyzerFormat.channelCount), "
                    + "rate=\(analyzerFormat.sampleRate)"
            )
            let sessionConverter = try SpeechAudioBufferConverter(
                inputFormat: microphoneFormat,
                outputFormat: analyzerFormat
            )
            audioBufferConverter = sessionConverter
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.prepareToAnalyze(in: analyzerFormat)

            let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.analyzer = analyzer
            inputContinuation = continuation

            resultsTask = Task {
                var accumulator = SpeechTranscriptAccumulator()
                do {
                    for try await result in transcriber.results {
                        accumulator.consume(result: result)
                        onTranscript(accumulator.transcript)
                    }
                } catch is CancellationError {
                    // Normal when the user stops or a setup failure is cleaned up.
                } catch {
                    onError(error.localizedDescription)
                }
            }

            try await analyzer.start(inputSequence: inputSequence)
            installMicrophoneTap(
                inputNode: inputNode,
                converter: sessionConverter,
                continuation: continuation,
                onError: onError
            )
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            await cleanUpAfterFailedStart()
            throw error
        }
#endif
    }

    static func activateBeforeAccessingInput<Input>(
        activateSession: () async throws -> Void,
        accessInput: () -> Input
    ) async rethrows -> Input {
        try await activateSession()
        return accessInput()
    }

    /// Input nodes may report a zero-channel/zero-rate format until the
    /// engine has been prepared. Keep the retry policy pure for tests.
    static func resolveInputFormat(
        initialFormat: AVAudioFormat,
        refreshedFormat: () -> AVAudioFormat
    ) -> AVAudioFormat? {
        resolveInputFormat(
            initialValue: initialFormat,
            isUsable: { $0.channelCount > 0 && $0.sampleRate > 0 },
            refreshedValue: refreshedFormat
        )
    }

    static func resolveInputFormat<Value>(
        initialValue: Value,
        isUsable: (Value) -> Bool,
        refreshedValue: () -> Value
    ) -> Value? {
        if isUsable(initialValue) { return initialValue }
        let refreshed = refreshedValue()
        return isUsable(refreshed) ? refreshed : nil
    }

    /// Inject the analyzer's dynamic format lookup at this boundary in tests;
    /// production passes SpeechAnalyzer.bestAvailableAudioFormat directly.
    static func compatibleAnalyzerFormat(
        microphoneFormat: AVAudioFormat,
        resolver: (AVAudioFormat) async -> AVAudioFormat?
    ) async -> AVAudioFormat? {
        guard microphoneFormat.channelCount > 0, microphoneFormat.sampleRate > 0 else {
            return nil
        }
        return await resolver(microphoneFormat)
    }

    static func assetInstallationNeeded(for status: AssetInventory.Status) -> Bool {
        switch status {
        case .installed, .unsupported:
            false
        case .supported, .downloading:
            true
        @unknown default:
            false
        }
    }

    static func deactivationError(
        primaryError: Error?,
        deactivate: () throws -> Void
    ) -> Error? {
        combineFinalizationAndDeactivation(
            finalizationError: primaryError,
            deactivate: deactivate
        ).error
    }

    static func combineFinalizationAndDeactivation(
        finalizationError: Error?,
        deactivate: () throws -> Void
    ) -> SpeechDeactivationResult {
        do {
            try deactivate()
            return SpeechDeactivationResult(error: finalizationError, cleanupErrorMessage: nil)
        } catch {
            let cleanupError = SpeechInputError.audioSessionDeactivationFailed
            return SpeechDeactivationResult(
                error: finalizationError ?? cleanupError,
                cleanupErrorMessage: cleanupError.localizedDescription
            )
        }
    }

    func stopTranscribing() async throws {
        guard isRecording else { return }
        lastCleanupErrorMessage = nil
        print("[SpeechInput] Stopping transcription")

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        isRecording = false

        var finalizationError: Error?
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                finalizationError = error
                await analyzer.cancelAndFinishNow()
            }
        }
        _ = await resultsTask?.result
        resultsTask = nil
        analyzer = nil
        audioBufferConverter = nil

        let deactivationResult = Self.combineFinalizationAndDeactivation(
            finalizationError: finalizationError,
            deactivate: audioSessionDeactivator
        )
        if let cleanupErrorMessage = deactivationResult.cleanupErrorMessage {
            lastCleanupErrorMessage = cleanupErrorMessage
        }
        print("[SpeechInput] Transcription stopped and audio session deactivated")
        if let error = deactivationResult.error {
            throw error
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        print("[SpeechInput] Configuring audio session for recording")
        do {
            try session.setCategory(
                Self.liveAudioSessionCategory,
                mode: Self.liveAudioSessionMode
            )
            try session.setActive(true)
            print("[SpeechInput] Audio session activated with .playAndRecord/.spokenAudio")
        } catch {
            print("[SpeechInput] Failed to set .record/.measurement: \(error). Falling back to .record")
            try session.setCategory(.record)
            try session.setActive(true)
            print("[SpeechInput] Audio session activated with .record")
        }
    }

    nonisolated private func installMicrophoneTap(
        inputNode: AVAudioInputNode,
        converter: SpeechAudioBufferConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        onError: @escaping ErrorHandler
    ) {
        let logState = SpeechAudioConversionLogState()
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: nil
        ) { buffer, _ in
            do {
                let convertedBuffer = try converter.convert(buffer)
#if DEBUG
                logState.bufferCount += 1
                if logState.bufferCount == 1 || logState.bufferCount.isMultiple(of: 16) {
                    let nonZeroFrameCount = Self.nonZeroFrameCount(in: convertedBuffer)
                    print(
                        "[SpeechInput][DEBUG] Converted buffer: frames=\(convertedBuffer.frameLength), "
                            + "rate=\(convertedBuffer.format.sampleRate), nonZeroFrames=\(nonZeroFrameCount)"
                    )
                }
#endif
                let yieldResult = continuation.yield(AnalyzerInput(buffer: convertedBuffer))
#if DEBUG
                if logState.bufferCount == 1 || logState.bufferCount.isMultiple(of: 16) {
                    print("[SpeechInput][DEBUG] Analyzer input yield: \(yieldResult)")
                }
#endif
            } catch {
                print("[SpeechInput] Microphone tap conversion error: \(error)")
                print("[SpeechInput] Last buffer stats: frames=\(buffer.frameLength), rate=\(buffer.format.sampleRate), ch=\(buffer.format.channelCount)")
                Task { @MainActor in
                    onError(error.localizedDescription)
                }
            }
        }
    }

    nonisolated private static func nonZeroFrameCount(in buffer: AVAudioPCMBuffer) -> Int {
        var count = 0
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channels = buffer.floatChannelData else { return 0 }
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<Int(buffer.format.channelCount) where channels[channel][frame] != 0 {
                    count += 1
                    break
                }
            }
        case .pcmFormatInt16:
            guard let channels = buffer.int16ChannelData else { return 0 }
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<Int(buffer.format.channelCount) where channels[channel][frame] != 0 {
                    count += 1
                    break
                }
            }
        case .pcmFormatInt32:
            guard let channels = buffer.int32ChannelData else { return 0 }
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<Int(buffer.format.channelCount) where channels[channel][frame] != 0 {
                    count += 1
                    break
                }
            }
        default:
            return 0
        }
        return count
    }

    private func cleanUpAfterFailedStart() async {
        print("[SpeechInput] Cleaning up after failed start")
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        audioBufferConverter = nil
        resultsTask?.cancel()
        resultsTask = nil
        isRecording = false
        do {
            try audioSessionDeactivator()
        } catch {
            lastCleanupErrorMessage = SpeechInputError.audioSessionDeactivationFailed.localizedDescription
        }
    }
}

extension SpeechInputService: SpeechInputServing {}
