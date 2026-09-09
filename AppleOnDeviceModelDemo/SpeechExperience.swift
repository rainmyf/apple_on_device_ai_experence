import Combine
import Foundation
import SwiftUI

enum SpeechRunState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case finalizing
    case succeeded
    case failed(String)
    case cancelled
}

@MainActor
final class SpeechExperienceViewModel: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var speechLatency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparingAssets = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var runState: SpeechRunState = .idle

    private let speechService: any SpeechInputServing
    private let currentTime: () -> TimeInterval
    private var recordingStartedAt: TimeInterval?
    private var isStarting = false
    private var lifecycleGeneration = 0
    private var hasStreamError = false
    private var stopTask: Task<Void, Never>?

    init(
        speechService: any SpeechInputServing = SpeechInputService(),
        currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    ) {
        self.speechService = speechService
        self.currentTime = currentTime
    }

    func startRecording() async {
        guard !isRecording, !isStarting, !isFinalizing else {
            // Keep the active run's state intact while explaining why the
            // duplicate request was ignored.
            errorMessage = SpeechInputError.alreadyRecording.localizedDescription
            return
        }

        transcript = ""
        speechLatency = nil
        errorMessage = nil
        hasStreamError = false
        isFinalizing = false
        isStarting = true
        isPreparingAssets = true
        runState = .starting
        let startedAt = currentTime()
        lifecycleGeneration += 1
        let generation = lifecycleGeneration

        defer {
            isStarting = false
            isPreparingAssets = false
        }

        do {
            try await speechService.startTranscribing(
                locale: .current,
                onTranscript: { [weak self] text in
                    guard let self else { return }
                    self.transcript = text
                },
                onError: { [weak self] message in
                    guard let self else { return }
                    self.hasStreamError = true
                    self.errorMessage = message
                    self.runState = .failed(message)
                }
            )
            try Task.checkCancellation()
            guard generation == lifecycleGeneration else {
                if speechService.isRecording {
                    try? await speechService.stopTranscribing()
                }
                return
            }
            recordingStartedAt = startedAt
            isRecording = speechService.isRecording
            if runState == .starting {
                errorMessage = nil
            }
            runState = isRecording ? .recording : .succeeded
        } catch is CancellationError {
            isRecording = false
            recordingStartedAt = nil
            runState = .cancelled
        } catch {
            isRecording = false
            recordingStartedAt = nil
            publish(error: error)
        }
    }

    func stopRecording() async {
        guard isRecording, !isFinalizing else { return }
        isFinalizing = true
        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStopRecording()
        }
        stopTask = task
        await task.value
        if stopTask != nil {
            stopTask = nil
        }
    }

    private func performStopRecording() async {
        defer {
            isFinalizing = false
        }
        let initialStreamError = hasStreamError ? errorMessage : nil
        errorMessage = initialStreamError
        runState = .finalizing

        do {
            try await speechService.stopTranscribing()
            if let recordingStartedAt {
                speechLatency = currentTime() - recordingStartedAt
            }
            isRecording = speechService.isRecording
            // The analyzer can publish its terminal error while stop awaits
            // finalization. Re-read actor state after the await so that late
            // errors cannot be overwritten by a successful stop.
            let finalStreamError = hasStreamError ? errorMessage : initialStreamError
            if let finalStreamError {
                runState = .failed(finalStreamError)
            } else {
                runState = .succeeded
            }
        } catch is CancellationError {
            isRecording = speechService.isRecording
            runState = .cancelled
            errorMessage = nil
        } catch {
            isRecording = speechService.isRecording
            publish(error: error)
        }

        recordingStartedAt = nil
        hasStreamError = false
        if !isRecording, runState == .finalizing {
            runState = .succeeded
        }
    }

    /// Finalizes the active SpeechAnalyzer input and intentionally reports a
    /// cancellation as a normal terminal state rather than an error.
    func cancelRecording() async {
        if isFinalizing {
            await stopTask?.value
            return
        }
        guard isRecording else {
            if isStarting {
                lifecycleGeneration += 1
                isStarting = false
                isPreparingAssets = false
                runState = .cancelled
            }
            return
        }

        do {
            try await speechService.stopTranscribing()
        } catch is CancellationError {
            // Expected when the analyzer is cancelled while finalizing.
        } catch {
            // Cancellation is user initiated; do not surface cleanup errors.
        }
        isRecording = speechService.isRecording
        recordingStartedAt = nil
        isFinalizing = false
        runState = .cancelled
        errorMessage = nil
    }

    private func publish(error: Error) {
        let message = error.localizedDescription
        publish(message: message)
    }

    private func publish(error: SpeechInputError) {
        publish(message: error.localizedDescription)
    }

    private func publish(message: String) {
        errorMessage = message
        runState = .failed(message)
    }
}

struct SpeechExperienceView: View {
    @StateObject private var viewModel = SpeechExperienceViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExperienceIntro(experience: ExperienceCatalog[.speechTranscription])

                VStack(alignment: .leading, spacing: 10) {
                    Label(statusTitle, systemImage: statusSymbol)
                        .font(.headline)
                        .foregroundStyle(statusColor)

                    ResultSurface(
                        title: "Live transcript",
                        text: viewModel.transcript.isEmpty ? "Speak to see a transcript." : viewModel.transcript
                    )

                    Button {
                        Task {
                            if viewModel.isRecording {
                                await viewModel.stopRecording()
                            } else {
                                await viewModel.startRecording()
                            }
                        }
                    } label: {
                        Label(
                            viewModel.isFinalizing ? "Finishing…" : (viewModel.isRecording ? "Stop and finalize" : "Start recording"),
                            systemImage: viewModel.isFinalizing ? "ellipsis.circle" : (viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent(for: .voiceSound))
                    .disabled(viewModel.isPreparingAssets || viewModel.isFinalizing)
                }

                if let latency = viewModel.speechLatency {
                    ResultSurface(title: "Finalization latency", text: String(format: "%.3f seconds", latency))
                }
                if let errorMessage = viewModel.errorMessage {
                    ResultSurface(title: "Speech status", text: errorMessage)
                }

                UsageInstructions(experience: ExperienceCatalog[.speechTranscription])
                Text("Audio is processed locally by the system Speech framework when supported.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Speech Transcription")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            Task { await viewModel.cancelRecording() }
        }
    }

    private var statusTitle: String {
        switch viewModel.runState {
        case .starting: "Preparing on-device Speech assets…"
        case .recording: "Listening"
        case .finalizing: "Finalizing transcript…"
        case .succeeded: "Ready"
        case .failed: "Unavailable"
        case .cancelled: "Cancelled"
        case .idle: "Ready to record"
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
