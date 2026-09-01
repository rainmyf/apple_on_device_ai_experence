@preconcurrency import AVFAudio
import Combine
import Foundation
import SoundAnalysis
import SwiftUI

struct SoundClassification: Equatable, Identifiable, Sendable {
    let label: String
    let confidence: Double

    var id: String { label }

    /// Keeps only displayable candidates, ranking ties by label so that a
    /// stream update is deterministic even when confidences are equal.
    static func filtered(
        _ classifications: [SoundClassification],
        threshold: Double,
        limit: Int = 3
    ) -> [SoundClassification] {
        guard limit > 0 else { return [] }
        return classifications
            .filter { $0.confidence >= threshold }
            .sorted {
                if $0.confidence != $1.confidence {
                    return $0.confidence > $1.confidence
                }
                return $0.label < $1.label
            }
            .prefix(limit)
            .map { $0 }
    }
}

enum SoundAnalysisInputError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case alreadyRecording
    case audioFormatUnavailable
    case audioSessionActivationFailed
    case audioSessionDeactivationFailed
    case requestUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone permission was denied. Enable it in Settings and try again."
        case .alreadyRecording:
            "A sound analysis run is already in progress."
        case .audioFormatUnavailable:
            "No valid microphone audio format is available."
        case .audioSessionActivationFailed:
            "The audio session could not be activated."
        case .audioSessionDeactivationFailed:
            "The audio session could not be deactivated cleanly."
        case .requestUnavailable:
            "The built-in sound classifier is unavailable on this device."
        }
    }
}

enum SoundAnalysisRunState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case finalizing
    case succeeded
    case failed(String)
    case cancelled
}

struct SoundAnalysisDeactivationResult {
    let error: Error?
    let cleanupErrorMessage: String?
}

@MainActor
protocol SoundAnalysisServing: AnyObject {
    var isRecording: Bool { get }

    func startAnalyzing(
        onClassifications: @escaping SoundAnalysisInputService.ClassificationHandler,
        onError: @escaping SoundAnalysisInputService.ErrorHandler
    ) async throws

    func stopAnalyzing() async throws
}

/// Converts SoundAnalysis framework callbacks into values safe for the UI.
/// The framework's observer is intentionally separate from the view model so
/// no framework objects escape the audio callback or MainActor boundary.
final class SoundAnalysisResultsObserverAdapter: NSObject, SNResultsObserving {
    typealias ClassificationHandler = @MainActor @Sendable ([SoundClassification]) -> Void
    typealias ErrorHandler = @MainActor @Sendable (String) -> Void

    private let onClassifications: ClassificationHandler
    private let onError: ErrorHandler

    init(
        onClassifications: @escaping ClassificationHandler,
        onError: @escaping ErrorHandler
    ) {
        self.onClassifications = onClassifications
        self.onError = onError
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let classifications = result.classifications.map {
            SoundClassification(label: $0.identifier, confidence: $0.confidence)
        }
        let handler = onClassifications
        Task { @MainActor in handler(classifications) }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        let handler = onError
        Task { @MainActor in handler(error.localizedDescription) }
    }

    func requestDidComplete(_ request: SNRequest) {}
}

@MainActor
final class SoundAnalysisInputService: SoundAnalysisServing {
    typealias ClassificationHandler = @MainActor @Sendable ([SoundClassification]) -> Void
    typealias ErrorHandler = @MainActor @Sendable (String) -> Void

    private let audioEngine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private var observer: SoundAnalysisResultsObserverAdapter?
    private let audioSessionDeactivator: () throws -> Void

    private(set) var isRecording = false
    private(set) var lastCleanupErrorMessage: String?
    private var isStarting = false

    init(audioSessionDeactivator: @escaping () throws -> Void = {
        try AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }) {
        self.audioSessionDeactivator = audioSessionDeactivator
    }

    func startAnalyzing(
        onClassifications: @escaping ClassificationHandler,
        onError: @escaping ErrorHandler
    ) async throws {
        guard !isRecording, !isStarting else { throw SoundAnalysisInputError.alreadyRecording }
        isStarting = true
        defer { isStarting = false }
        lastCleanupErrorMessage = nil
        guard await requestMicrophonePermission() else {
            throw SoundAnalysisInputError.microphonePermissionDenied
        }

        do {
            try configureAudioSession()
            let inputNode = audioEngine.inputNode
            audioEngine.prepare()
            guard let inputFormat = Self.resolveInputFormat(
                initialValue: inputNode.outputFormat(forBus: 0),
                isUsable: { $0.channelCount > 0 && $0.sampleRate > 0 },
                refreshedValue: {
                    audioEngine.prepare()
                    return inputNode.outputFormat(forBus: 0)
                }
            ) else {
                throw SoundAnalysisInputError.audioFormatUnavailable
            }

            let analyzer = SNAudioStreamAnalyzer(format: inputFormat)
            let request: SNClassifySoundRequest
            do {
                request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            } catch {
                throw SoundAnalysisInputError.requestUnavailable
            }
            let observer = SoundAnalysisResultsObserverAdapter(
                onClassifications: onClassifications,
                onError: onError
            )
            try analyzer.add(request, withObserver: observer)
            self.analyzer = analyzer
            self.request = request
            self.observer = observer

            installTap(inputNode: inputNode, analyzer: analyzer)
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            await cleanUpAfterFailedStart()
            throw error
        }
    }

    func stopAnalyzing() async throws {
        guard isRecording || analyzer != nil else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        analyzer?.completeAnalysis()
        analyzer?.removeAllRequests()
        analyzer = nil
        request = nil
        observer = nil
        isRecording = false

        let deactivationResult = Self.combineFinalizationAndDeactivation(
            finalizationError: nil,
            deactivate: audioSessionDeactivator
        )
        lastCleanupErrorMessage = deactivationResult.cleanupErrorMessage
        if deactivationResult.error != nil {
            throw SoundAnalysisInputError.audioSessionDeactivationFailed
        }
    }

    static func combineFinalizationAndDeactivation(
        finalizationError: Error?,
        deactivate: () throws -> Void
    ) -> SoundAnalysisDeactivationResult {
        do {
            try deactivate()
            return SoundAnalysisDeactivationResult(error: finalizationError, cleanupErrorMessage: nil)
        } catch {
            let cleanupError = SoundAnalysisInputError.audioSessionDeactivationFailed
            return SoundAnalysisDeactivationResult(
                error: finalizationError ?? cleanupError,
                cleanupErrorMessage: cleanupError.localizedDescription
            )
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
        } catch {
            do {
                try session.setCategory(.record)
                try session.setActive(true)
            } catch {
                throw SoundAnalysisInputError.audioSessionActivationFailed
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated private func installTap(
        inputNode: AVAudioInputNode,
        analyzer: SNAudioStreamAnalyzer
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { buffer, when in
            analyzer.analyze(buffer, atAudioFramePosition: when.sampleTime)
        }
    }

    private func cleanUpAfterFailedStart() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        analyzer?.removeAllRequests()
        analyzer = nil
        request = nil
        observer = nil
        isRecording = false
        do {
            try audioSessionDeactivator()
        } catch {
            lastCleanupErrorMessage = SoundAnalysisInputError.audioSessionDeactivationFailed.localizedDescription
        }
    }
}

extension SoundAnalysisInputService {
    static func resolveInputFormat<Value>(
        initialValue: Value,
        isUsable: (Value) -> Bool,
        refreshedValue: () -> Value
    ) -> Value? {
        if isUsable(initialValue) { return initialValue }
        let refreshed = refreshedValue()
        return isUsable(refreshed) ? refreshed : nil
    }
}

@MainActor
final class SoundAnalysisExperienceViewModel: ObservableObject {
    @Published private(set) var classifications: [SoundClassification] = []
    @Published private(set) var analysisLatency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var runState: SoundAnalysisRunState = .idle

    private let soundService: any SoundAnalysisServing
    private let currentTime: () -> TimeInterval
    private let threshold: Double
    private let limit: Int
    private var recordingStartedAt: TimeInterval?
    private var lifecycleGeneration = 0
    private var stopTask: Task<Void, Never>?
    private var hasStreamError = false

    init(
        soundService: any SoundAnalysisServing = SoundAnalysisInputService(),
        threshold: Double = 0.1,
        limit: Int = 3,
        currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    ) {
        self.soundService = soundService
        self.threshold = threshold
        self.limit = limit
        self.currentTime = currentTime
    }

    func startAnalyzing() async {
        guard !isRecording, !isStarting, !isFinalizing else {
            errorMessage = SoundAnalysisInputError.alreadyRecording.localizedDescription
            return
        }
        classifications = []
        analysisLatency = nil
        errorMessage = nil
        hasStreamError = false
        isStarting = true
        runState = .starting
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let startedAt = currentTime()
        defer { isStarting = false }

        do {
            try await soundService.startAnalyzing(
                onClassifications: { [weak self] values in
                    guard let self else { return }
                    guard generation == self.lifecycleGeneration else { return }
                    self.classifications = SoundClassification.filtered(
                        values,
                        threshold: self.threshold,
                        limit: self.limit
                    )
                },
                onError: { [weak self] message in
                    guard let self else { return }
                    guard generation == self.lifecycleGeneration else { return }
                    self.hasStreamError = true
                    self.errorMessage = message
                    self.runState = .failed(message)
                }
            )
            try Task.checkCancellation()
            guard generation == lifecycleGeneration else {
                try? await soundService.stopAnalyzing()
                return
            }
            recordingStartedAt = startedAt
            isRecording = soundService.isRecording
            if !hasStreamError {
                runState = isRecording ? .recording : .succeeded
            }
        } catch is CancellationError {
            guard generation == lifecycleGeneration else {
                if soundService.isRecording {
                    try? await soundService.stopAnalyzing()
                }
                return
            }
            if soundService.isRecording {
                try? await soundService.stopAnalyzing()
            }
            isRecording = false
            recordingStartedAt = nil
            runState = .cancelled
        } catch {
            guard generation == lifecycleGeneration else {
                if soundService.isRecording {
                    try? await soundService.stopAnalyzing()
                }
                return
            }
            isRecording = false
            errorMessage = error.localizedDescription
            runState = .failed(error.localizedDescription)
        }
    }

    func stopAnalyzing() async {
        guard isRecording, !isFinalizing else { return }
        isFinalizing = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStop()
        }
        stopTask = task
        await task.value
        stopTask = nil
    }

    func cancelAnalyzing() async {
        if isFinalizing {
            await stopTask?.value
            return
        }
        guard isRecording else {
            if isStarting {
                lifecycleGeneration += 1
                isStarting = false
                runState = .cancelled
            }
            return
        }
        // Invalidate callbacks from the active run before awaiting audio
        // teardown. SoundAnalysis may deliver a queued result during stop.
        lifecycleGeneration += 1
        try? await soundService.stopAnalyzing()
        isRecording = false
        recordingStartedAt = nil
        isFinalizing = false
        errorMessage = nil
        runState = .cancelled
    }

    private func performStop() async {
        defer {
            isFinalizing = false
            recordingStartedAt = nil
        }
        let streamError = hasStreamError ? errorMessage : nil
        runState = .finalizing
        do {
            try await soundService.stopAnalyzing()
            if let recordingStartedAt {
                analysisLatency = currentTime() - recordingStartedAt
            }
            isRecording = soundService.isRecording
            let finalStreamError = hasStreamError ? errorMessage : streamError
            if let finalStreamError {
                errorMessage = finalStreamError
                runState = .failed(finalStreamError)
            } else {
                runState = .succeeded
            }
        } catch is CancellationError {
            isRecording = soundService.isRecording
            let finalStreamError = hasStreamError ? errorMessage : streamError
            if let finalStreamError {
                errorMessage = finalStreamError
                runState = .failed(finalStreamError)
            } else {
                errorMessage = nil
                runState = .cancelled
            }
        } catch {
            isRecording = soundService.isRecording
            let finalStreamError = hasStreamError ? errorMessage : streamError
            if let finalStreamError {
                errorMessage = finalStreamError
                runState = .failed(finalStreamError)
            } else {
                errorMessage = error.localizedDescription
                runState = .failed(error.localizedDescription)
            }
        }
        hasStreamError = false
    }
}

struct SoundAnalysisExperienceView: View {
    @StateObject private var viewModel = SoundAnalysisExperienceViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExperienceIntro(experience: ExperienceCatalog[.soundRecognition])
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.headline)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 10) {
                    if viewModel.classifications.isEmpty {
                        ResultSurface(title: "Sound labels", text: "No confident sound labels yet.")
                    } else {
                        ForEach(viewModel.classifications) { classification in
                            HStack {
                                Text(classification.label)
                                Spacer()
                                Text(String(format: "%.0f%%", classification.confidence * 100))
                                    .foregroundStyle(AppTheme.secondaryInk)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Button {
                    Task {
                        if viewModel.isRecording {
                            await viewModel.stopAnalyzing()
                        } else {
                            await viewModel.startAnalyzing()
                        }
                    }
                } label: {
                    Label(
                        viewModel.isFinalizing ? "Finishing…" : (viewModel.isRecording ? "Stop analysis" : "Start analysis"),
                        systemImage: viewModel.isFinalizing ? "ellipsis.circle" : (viewModel.isRecording ? "stop.circle.fill" : "waveform.badge.mic")
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent(for: .voiceSound))
                .disabled(viewModel.isStarting || viewModel.isFinalizing)

                if let latency = viewModel.analysisLatency {
                    ResultSurface(title: "Analysis elapsed", text: String(format: "%.3f seconds", latency))
                }
                if let errorMessage = viewModel.errorMessage {
                    ResultSurface(title: "Sound analysis status", text: errorMessage)
                }

                UsageInstructions(experience: ExperienceCatalog[.soundRecognition])
                Text("SoundAnalysis labels audio events; it does not transcribe speech or produce a transcript. Audio is processed locally when supported.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Sound Recognition")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { Task { await viewModel.cancelAnalyzing() } }
    }

    private var statusTitle: String {
        switch viewModel.runState {
        case .starting: "Preparing sound classifier…"
        case .recording: "Analyzing microphone audio"
        case .finalizing: "Finishing sound analysis…"
        case .succeeded: "Ready"
        case .failed: "Unavailable"
        case .cancelled: "Cancelled"
        case .idle: "Ready to analyze"
        }
    }

    private var statusSymbol: String {
        switch viewModel.runState {
        case .recording: "waveform"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "xmark.circle"
        default: "waveform.circle"
        }
    }

    private var statusColor: Color {
        switch viewModel.runState {
        case .failed: .orange
        case .cancelled: AppTheme.secondaryInk
        default: AppTheme.accent(for: .voiceSound)
        }
    }
}
