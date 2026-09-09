import Combine
import Foundation
import SwiftUI
@preconcurrency import Translation

enum TranslationAssetAvailability: Equatable, Sendable {
    case ready
    case assetsRequired
    case unsupported

    init(_ status: LanguageAvailability.Status) {
        switch status {
        case .installed: self = .ready
        case .supported: self = .assetsRequired
        case .unsupported: self = .unsupported
        @unknown default: self = .unsupported
        }
    }
}

enum TranslationRunState: Equatable, Sendable {
    case idle
    case running
    case succeeded
    case failed(String)
    case cancelled
}

@MainActor
protocol TranslationSessionServicing: AnyObject {
    var isReady: Bool { get async }
    func prepareTranslation() async throws
    func translate(_ string: String) async throws -> String
    func cancel()
}

@MainActor
private final class SystemTranslationSessionAdapter: TranslationSessionServicing {
    let session: TranslationSession

    init(session: TranslationSession) {
        self.session = session
    }

    var isReady: Bool { get async { await session.isReady } }

    func prepareTranslation() async throws {
        try await session.prepareTranslation()
    }

    func translate(_ string: String) async throws -> String {
        try await session.translate(string).targetText
    }

    func cancel() {
        session.cancel()
    }
}

@MainActor
final class TranslationViewModel: ObservableObject {
    typealias Translator = (String) async throws -> String
    typealias AvailabilityProvider = (Locale.Language, Locale.Language?) async -> LanguageAvailability.Status

    @Published var input = ""
    @Published private(set) var output: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var isRunning = false
    @Published private(set) var runState: TranslationRunState = .idle
    @Published private(set) var isReady: Bool
    @Published private(set) var availability: TranslationAssetAvailability
    @Published private(set) var configuration: TranslationSession.Configuration

    private var sourceLanguageCode: String
    private var targetLanguageCode: String
    private var session: (any TranslationSessionServicing)?
    private let translator: Translator?
    private let availabilityProvider: AvailabilityProvider
    private let clock: () -> TimeInterval
    private var cancellationRequested = false
    private var isActive = true
    private var attachmentGeneration = UUID()
    private var activeTask: Task<Void, Never>?
    private var activeRunToken: UUID?
    private var activeStartedAt: TimeInterval?
    private var activeConfigurationVersion: Int?
    private var activeSessionIdentity: ObjectIdentifier?

    init(
        sourceLanguage: String = "en",
        targetLanguage: String = "zh-Hans",
        assetAvailability: TranslationAssetAvailability? = nil,
        translator: Translator? = nil,
        availabilityProvider: @escaping AvailabilityProvider = { source, target in
            await LanguageAvailability().status(from: source, to: target)
        },
        clock: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    ) {
        self.sourceLanguageCode = sourceLanguage
        self.targetLanguageCode = targetLanguage
        self.availability = assetAvailability ?? .assetsRequired
        self.isReady = assetAvailability == .ready
        self.translator = translator
        self.availabilityProvider = availabilityProvider
        self.clock = clock
        self.configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceLanguage),
            target: Locale.Language(identifier: targetLanguage)
        )
    }

    var availabilityDetail: String {
        switch availability {
        case .ready:
            "Translation is ready on this device."
        case .assetsRequired:
            "Download the source and target language assets to run this page."
        case .unsupported:
            "This language pair is not supported by the system translation service."
        }
    }

    /// Translation is a system language service and has no Apple Intelligence dependency.
    var requiresAppleIntelligence: Bool { false }
    var usesCloudFallback: Bool { false }
    var selectedSourceLanguage: String { sourceLanguageCode }
    var selectedTargetLanguage: String { targetLanguageCode }
    var currentAttachmentGeneration: UUID { attachmentGeneration }

    func setLanguages(source: String, target: String) {
        cancel()
        session = nil
        attachmentGeneration = UUID()
        sourceLanguageCode = source
        targetLanguageCode = target
        var next = TranslationSession.Configuration(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: target)
        )
        next.invalidate()
        configuration = next
        if source == target {
            availability = .unsupported
        } else {
            availability = .assetsRequired
        }
        isReady = false
    }

    func attach(session: TranslationSession, configurationVersion: Int? = nil, attachmentGeneration: UUID? = nil) async {
        await attach(
            session: SystemTranslationSessionAdapter(session: session),
            configurationVersion: configurationVersion,
            attachmentGeneration: attachmentGeneration
        )
    }

    func attach(
        session: any TranslationSessionServicing,
        configurationVersion: Int? = nil,
        attachmentGeneration: UUID? = nil
    ) async {
        guard isActive,
              configurationVersion == nil || configurationVersion == configuration.version,
              attachmentGeneration == nil || attachmentGeneration == self.attachmentGeneration else { return }
        self.session = session
        await refreshAvailability(session: session)
    }

    func refreshAvailability() async {
        guard sourceLanguageCode != targetLanguageCode else {
            availability = .unsupported
            isReady = false
            return
        }
        let expectedVersion = configuration.version
        let expectedSource = sourceLanguageCode
        let expectedTarget = targetLanguageCode
        let expectedRunToken = activeRunToken
        let expectedGeneration = attachmentGeneration
        let status = await availabilityProvider(
            Locale.Language(identifier: expectedSource),
            Locale.Language(identifier: expectedTarget)
        )
        guard configuration.version == expectedVersion,
              sourceLanguageCode == expectedSource,
              targetLanguageCode == expectedTarget,
              activeRunToken == expectedRunToken,
              isActive,
              attachmentGeneration == expectedGeneration else { return }
        availability = TranslationAssetAvailability(status)
        isReady = availability == .ready
    }

    func translate() async {
        guard !isRunning else { return }
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            publishValidationError("Enter text to translate.")
            return
        }
        guard availability != .unsupported else {
            publishValidationError("This language pair is not supported by the system translation service.")
            return
        }
        guard session != nil || availability == .ready else {
            publishValidationError("Translation language assets are not ready.")
            return
        }

        output = nil
        errorMessage = nil
        latency = nil
        isRunning = true
        runState = .running
        cancellationRequested = false
        let token = UUID()
        let startedAt = clock()
        activeStartedAt = startedAt
        let sessionAtStart = session
        let translatorAtStart = translator
        let configurationVersion = configuration.version
        activeRunToken = token
        activeConfigurationVersion = configurationVersion
        activeSessionIdentity = sessionAtStart.map(ObjectIdentifier.init)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performTranslation(
                request,
                token: token,
                session: sessionAtStart,
                translator: translatorAtStart,
                configurationVersion: configurationVersion,
                startedAt: startedAt
            )
        }
        activeTask = task
        await task.value
        if activeTask != nil, activeRunToken == token {
            activeTask = nil
        }
    }

    func cancel() {
        activeTask?.cancel()
        session?.cancel()
        cancellationRequested = true
        guard isRunning else { return }
        if let startedAt = activeStartedAt {
            latency = clock() - startedAt
        }
        isRunning = false
        errorMessage = nil
        runState = .cancelled
        activeRunToken = nil
        activeStartedAt = nil
        activeConfigurationVersion = nil
        activeSessionIdentity = nil
    }

    func deactivate() {
        cancel()
        isActive = false
        attachmentGeneration = UUID()
        session = nil
    }

    private func refreshAvailability(session: any TranslationSessionServicing) async {
        guard sourceLanguageCode != targetLanguageCode else {
            availability = .unsupported
            isReady = false
            return
        }
        let expectedVersion = configuration.version
        let expectedSource = sourceLanguageCode
        let expectedTarget = targetLanguageCode
        let expectedSessionIdentity = ObjectIdentifier(session)
        let expectedRunToken = activeRunToken
        let expectedGeneration = attachmentGeneration
        let status = await availabilityProvider(
            Locale.Language(identifier: expectedSource),
            Locale.Language(identifier: expectedTarget)
        )
        guard configuration.version == expectedVersion,
              sourceLanguageCode == expectedSource,
              targetLanguageCode == expectedTarget,
              activeRunToken == expectedRunToken,
              isActive,
              attachmentGeneration == expectedGeneration,
              self.session.map({ ObjectIdentifier($0) == expectedSessionIdentity }) == true else { return }
        availability = TranslationAssetAvailability(status)
        let sessionReady = await session.isReady
        guard configuration.version == expectedVersion,
              sourceLanguageCode == expectedSource,
              targetLanguageCode == expectedTarget,
              activeRunToken == expectedRunToken,
              isActive,
              attachmentGeneration == expectedGeneration,
              self.session.map({ ObjectIdentifier($0) == expectedSessionIdentity }) == true else { return }
        isReady = availability == .ready && sessionReady
    }

    private func performTranslation(
        _ request: String,
        token: UUID,
        session: (any TranslationSessionServicing)?,
        translator: Translator?,
        configurationVersion: Int,
        startedAt: TimeInterval
    ) async {
        defer {
            if activeRunToken == token {
                latency = clock() - startedAt
                isRunning = false
                activeStartedAt = nil
                activeRunToken = nil
                activeTask = nil
                activeConfigurationVersion = nil
                activeSessionIdentity = nil
            }
        }

        do {
            try ensureCurrent(token, configurationVersion: configurationVersion, session: session)
            try await prepareTranslation(session: session, token: token, configurationVersion: configurationVersion)
            try ensureCurrent(token, configurationVersion: configurationVersion, session: session)
            let translated: String
            if let session {
                translated = try await session.translate(request)
            } else if let translator {
                translated = try await translator(request)
            } else {
                throw TranslationViewModelError.sessionUnavailable
            }
            try Task.checkCancellation()
            try ensureCurrent(token, configurationVersion: configurationVersion, session: session)
            output = translated
            runState = .succeeded
        } catch {
            if error is CancellationError || TranslationError.alreadyCancelled ~= error || cancellationRequested {
                errorMessage = nil
                if activeRunToken == token {
                    runState = .cancelled
                }
            } else if activeRunToken == token {
                let message = error.localizedDescription
                errorMessage = message
                runState = .failed(message)
            }
        }
    }

    private func prepareTranslation(
        session: (any TranslationSessionServicing)?,
        token: UUID,
        configurationVersion: Int
    ) async throws {
        guard let session else { return }
        try ensureCurrent(token, configurationVersion: configurationVersion, session: session)
        try await session.prepareTranslation()
        try ensureCurrent(token, configurationVersion: configurationVersion, session: session)
        let expectedSource = sourceLanguageCode
        let expectedTarget = targetLanguageCode
        let status = await availabilityProvider(
            Locale.Language(identifier: expectedSource),
            Locale.Language(identifier: expectedTarget)
        )
        try ensureCurrent(token, configurationVersion: configurationVersion, session: session)
        availability = TranslationAssetAvailability(status)
        let sessionReady = await session.isReady
        try ensureCurrent(token, configurationVersion: configurationVersion, session: session)
        isReady = availability == .ready && sessionReady
        guard isReady else { throw TranslationViewModelError.assetsNotReady }
    }

    private func ensureCurrent(
        _ token: UUID,
        configurationVersion: Int? = nil,
        session: (any TranslationSessionServicing)? = nil
    ) throws {
        guard activeRunToken == token,
              !cancellationRequested,
              configurationVersion == nil || activeConfigurationVersion == configurationVersion,
              sessionMatches(session) else {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    private func sessionMatches(_ expected: (any TranslationSessionServicing)?) -> Bool {
        guard let expected else {
            return session == nil && activeSessionIdentity == nil
        }
        let expectedIdentity = ObjectIdentifier(expected)
        return activeSessionIdentity == expectedIdentity &&
            session.map { ObjectIdentifier($0) == expectedIdentity } == true
    }

    private func publishValidationError(_ message: String) {
        output = nil
        errorMessage = message
        latency = nil
        runState = .failed(message)
    }
}

private enum TranslationViewModelError: LocalizedError {
    case sessionUnavailable
    case assetsNotReady

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable: "Translation session is not attached."
        case .assetsNotReady: "Translation language assets are not ready."
        }
    }
}

struct TranslationExperienceView: View {
    @StateObject private var viewModel = TranslationViewModel()
    private let languages = [
        ("en", "English"),
        ("zh-Hans", "Chinese (Simplified)"),
        ("fr", "French"),
        ("de", "German"),
    ]

    var body: some View {
        let configuration = viewModel.configuration
        let attachmentGeneration = viewModel.currentAttachmentGeneration
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ExperienceIntro(experience: ExperienceCatalog[.translation])

                HStack {
                    Menu {
                        ForEach(languages, id: \.0) { code, name in
                            Button(name) {
                                viewModel.setLanguages(source: code, target: viewModel.selectedTargetLanguage)
                            }
                        }
                    } label: {
                        Label("From: \(viewModel.selectedSourceLanguage)", systemImage: "arrow.up")
                    }
                    Menu {
                        ForEach(languages, id: \.0) { code, name in
                            Button(name) {
                                viewModel.setLanguages(source: viewModel.selectedSourceLanguage, target: code)
                            }
                        }
                    } label: {
                        Label("To: \(viewModel.selectedTargetLanguage)", systemImage: "arrow.down")
                    }
                }

                TextEditor(text: $viewModel.input)
                    .frame(minHeight: 130)
                    .padding(8)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Availability")
                        .font(.headline)
                    Text(viewModel.availabilityDetail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text(viewModel.isReady ? "Ready" : "Waiting for language assets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.isReady ? .green : .orange)
                }

                HStack {
                    Button("Translate") {
                        Task { await viewModel.translate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent(for: .languageText))
                    if viewModel.isRunning {
                        Button("Cancel", action: viewModel.cancel)
                            .buttonStyle(.bordered)
                    }
                }

                ResultSurface(title: "Translation", text: viewModel.output ?? viewModel.errorMessage ?? "No run performed.")
                if let latency = viewModel.latency {
                    Text("Last run: \(latency, specifier: "%.3f") s · \(viewModel.runState.displayName)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                UsageInstructions(experience: ExperienceCatalog[.translation])
            }
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        .translationTask(configuration) { session in
            await viewModel.attach(
                session: session,
                configurationVersion: configuration.version,
                attachmentGeneration: attachmentGeneration
            )
        }
        .onDisappear { viewModel.deactivate() }
    }

}

private extension TranslationRunState {
    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}
