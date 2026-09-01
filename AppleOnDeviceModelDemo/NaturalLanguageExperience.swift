import Foundation
import NaturalLanguage
import SwiftUI

struct NaturalLanguageFrameworkToken: Equatable, Sendable {
    let text: String
    let range: Range<Int>
    let lexicalClass: String
}

struct NaturalLanguageFrameworkEntity: Equatable, Sendable {
    let text: String
    let range: Range<Int>
    let tag: String
}

struct NaturalLanguageFrameworkResult: Equatable, Sendable {
    let languageCode: String?
    let tokens: [NaturalLanguageFrameworkToken]
    let entities: [NaturalLanguageFrameworkEntity]
    let sentimentScore: Double?
    let sentimentScores: [Double]?

    init(
        languageCode: String?,
        tokens: [NaturalLanguageFrameworkToken],
        entities: [NaturalLanguageFrameworkEntity],
        sentimentScore: Double?,
        sentimentScores: [Double]? = nil
    ) {
        self.languageCode = languageCode
        self.tokens = tokens
        self.entities = entities
        self.sentimentScore = sentimentScore
        self.sentimentScores = sentimentScores
    }
}

protocol NaturalLanguageFrameworkAdapter: AnyObject {
    func analyze(_ text: String) -> NaturalLanguageFrameworkResult
}

struct NaturalLanguageToken: Equatable, Sendable {
    let text: String
    let range: Range<Int>
    let lexicalClass: String
}

struct NaturalLanguageEntity: Equatable, Sendable {
    let text: String
    let range: Range<Int>
    let kind: String
}

struct NaturalLanguageAnalysis: Equatable, Sendable {
    let language: String
    let tokens: [NaturalLanguageToken]
    let entities: [NaturalLanguageEntity]
    let sentimentScore: Double
    let sentimentLabel: String
}

final class NaturalLanguageAnalyzer {
    private let adapter: any NaturalLanguageFrameworkAdapter

    init(adapter: any NaturalLanguageFrameworkAdapter = SystemNaturalLanguageFrameworkAdapter()) {
        self.adapter = adapter
    }

    func analyze(_ input: String) -> NaturalLanguageAnalysis {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NaturalLanguageAnalysis(
                language: "Undetermined",
                tokens: [],
                entities: [],
                sentimentScore: 0,
                sentimentLabel: "Neutral"
            )
        }

        let raw = adapter.analyze(input)
        let rawScores = raw.sentimentScores ?? raw.sentimentScore.map { [$0] } ?? []
        let score = Self.averageSentiment(rawScores)
        return NaturalLanguageAnalysis(
            language: Self.languageName(for: raw.languageCode),
            tokens: raw.tokens.compactMap { token in
                guard token.range.lowerBound >= 0,
                      token.range.upperBound <= input.count,
                      token.range.lowerBound < token.range.upperBound else { return nil }
                return NaturalLanguageToken(
                    text: token.text,
                    range: token.range,
                    lexicalClass: Self.lexicalClassName(for: token.lexicalClass)
                )
            },
            entities: raw.entities.compactMap { entity in
                guard entity.range.lowerBound >= 0,
                      entity.range.upperBound <= input.count,
                      entity.range.lowerBound < entity.range.upperBound else { return nil }
                return NaturalLanguageEntity(
                    text: entity.text,
                    range: entity.range,
                    kind: Self.entityKindName(for: entity.tag)
                )
            },
            sentimentScore: score,
            sentimentLabel: Self.sentimentLabel(for: score)
        )
    }

    static func languageName(for code: String?) -> String {
        switch code?.lowercased() {
        case "en": "English"
        case "zh", "zh-hans", "zh-hant": "Chinese"
        case "ja": "Japanese"
        case "ko": "Korean"
        case "fr": "French"
        case "de": "German"
        case "es": "Spanish"
        case "it": "Italian"
        case "pt": "Portuguese"
        case "ru": "Russian"
        case "ar": "Arabic"
        case "hi": "Hindi"
        case .none, "", "und": "Undetermined"
        default: code!.uppercased()
        }
    }

    static func lexicalClassName(for rawValue: String) -> String {
        switch rawValue {
        case "OtherWord": "Other word"
        case "OtherPunctuation": "Other punctuation"
        default: rawValue.isEmpty ? "Unknown" : rawValue
        }
    }

    static func entityKindName(for rawValue: String) -> String {
        switch rawValue {
        case "PlaceName", "Place": "Place"
        case "PersonalName", "Person": "Person"
        case "OrganizationName", "Organization": "Organization"
        case "PhoneNumber": "Phone number"
        case "EmailAddress": "Email address"
        case "URL": "URL"
        default: rawValue.isEmpty ? "Unknown" : rawValue
        }
    }

    static func normalizedSentiment(_ score: Double) -> Double {
        let clamped = min(max(score, -1), 1)
        return (clamped * 100).rounded() / 100
    }

    static func averageSentiment(_ scores: [Double]) -> Double {
        guard !scores.isEmpty else { return 0 }
        return normalizedSentiment(scores.reduce(0, +) / Double(scores.count))
    }

    static func sentimentLabel(for score: Double) -> String {
        if score < 0 { return "Negative" }
        if score > 0 { return "Positive" }
        return "Neutral"
    }
}

@MainActor
final class NaturalLanguageViewModel: ObservableObject {
    @Published var input = "Apple opened an office in London."
    @Published private(set) var result: NaturalLanguageAnalysis?
    @Published private(set) var errorMessage: String?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var isRunning = false
    @Published private(set) var inputSnapshot: String?

    let analyzer: NaturalLanguageAnalyzer
    private let currentTime: () -> TimeInterval
    private var operationTask: Task<Void, Never>?
    private var activeRequestToken: UUID?
    private var startedAt: TimeInterval?

    init(
        analyzer: NaturalLanguageAnalyzer = NaturalLanguageAnalyzer(),
        currentTime: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate },
        clock: (() -> TimeInterval)? = nil
    ) {
        self.analyzer = analyzer
        self.currentTime = clock ?? currentTime
    }

    var isInputEditable: Bool { !isRunning }

    func run() async {
        guard !isRunning else { return }
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            result = nil
            latency = nil
            errorMessage = "Enter text before analyzing."
            return
        }

        let token = UUID()
        let started = currentTime()
        inputSnapshot = request
        result = nil
        errorMessage = nil
        latency = nil
        isRunning = true
        startedAt = started
        activeRequestToken = token

        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else {
                self.finishCancellation(token: token, startedAt: started)
                return
            }
            let value = self.analyzer.analyze(request)
            guard !Task.isCancelled else { return }
            self.finish(value, token: token, startedAt: started)
        }
        operationTask = operation
        await withTaskCancellationHandler(operation: { await operation.value }, onCancel: {
            operation.cancel()
            Task { @MainActor [weak self] in self?.cancel(token: token) }
        })
        if Task.isCancelled { cancel(token: token) }
    }

    func cancel() { cancel(token: activeRequestToken) }
    func onDisappear() { cancel() }

    private func cancel(token: UUID?) {
        guard let token, activeRequestToken == token, isRunning else { return }
        operationTask?.cancel(); operationTask = nil; activeRequestToken = nil; isRunning = false
        if let startedAt { latency = currentTime() - startedAt }
    }

    private func finish(_ value: NaturalLanguageAnalysis, token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token, !Task.isCancelled else { return }
        result = value
        finishActive(token: token, startedAt: startedAt)
    }

    private func finishCancellation(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        finishActive(token: token, startedAt: startedAt)
    }

    private func finishActive(token: UUID, startedAt: TimeInterval) {
        guard activeRequestToken == token else { return }
        latency = currentTime() - startedAt
        activeRequestToken = nil; operationTask = nil; isRunning = false
    }
}

typealias NaturalLanguageExperienceViewModel = NaturalLanguageViewModel

private final class SystemNaturalLanguageFrameworkAdapter: NaturalLanguageFrameworkAdapter, @unchecked Sendable {
    func analyze(_ text: String) -> NaturalLanguageFrameworkResult {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .sentimentScore])
        tagger.string = text
        let fullRange = text.startIndex..<text.endIndex

        var tokens = [NaturalLanguageFrameworkToken]()
        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            tokens.append(.init(
                text: String(text[range]),
                range: Self.offsetRange(in: text, range: range),
                lexicalClass: tag?.rawValue ?? "Unknown"
            ))
            return true
        }

        var entities = [NaturalLanguageFrameworkEntity]()
        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            guard let tag else { return true }
            entities.append(.init(
                text: String(text[range]),
                range: Self.offsetRange(in: text, range: range),
                tag: tag.rawValue
            ))
            return true
        }

        var sentimentScores = [Double]()
        tagger.enumerateTags(in: fullRange, unit: .paragraph, scheme: .sentimentScore, options: []) { tag, _ in
            if let score = tag.flatMap({ Double($0.rawValue) }) {
                sentimentScores.append(score)
            }
            return true
        }

        return NaturalLanguageFrameworkResult(
            languageCode: recognizer.dominantLanguage?.rawValue,
            tokens: tokens,
            entities: entities,
            sentimentScore: sentimentScores.first,
            sentimentScores: sentimentScores
        )
    }

    private static func offsetRange(in text: String, range: Range<String.Index>) -> Range<Int> {
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        return start..<end
    }
}

struct NaturalLanguageExperienceView: View {
    @StateObject private var model: NaturalLanguageViewModel

    init(model: NaturalLanguageViewModel = NaturalLanguageViewModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExperienceIntro(experience: ExperienceCatalog[.naturalLanguage])
                TextEditor(text: $model.input)
                    .frame(minHeight: 130)
                    .padding(8)
                    .disabled(model.isRunning)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                HStack {
                    Button(model.isRunning ? "Analyzing…" : "Analyze text") {
                        Task { await model.run() }
                    }
                    .disabled(model.isRunning || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent(for: .languageText))
                    if model.isRunning {
                        Button("Cancel", action: model.cancel)
                            .buttonStyle(.bordered)
                    }
                }

                if let result = model.result {
                    ResultSurface(title: "Language", text: result.language)
                    ResultSurface(title: "Tokens", text: result.tokens.map { "\($0.text) [\($0.lexicalClass)] \($0.range)" }.joined(separator: "\n"))
                    ResultSurface(title: "Entities", text: result.entities.map { "\($0.text) (\($0.kind)) \($0.range)" }.joined(separator: "\n"))
                    ResultSurface(title: "Sentiment", text: "\(result.sentimentLabel) (\(String(format: "%.2f", result.sentimentScore)))")
                } else {
                    ResultSurface(title: "Result", text: "No run performed.")
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if let latency = model.latency {
                    Text(String(format: "Elapsed %.3fs", latency))
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                }

                UsageInstructions(experience: ExperienceCatalog[.naturalLanguage])
            }
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Natural Language")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.onDisappear() }
    }
}
