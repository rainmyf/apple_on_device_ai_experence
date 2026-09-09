import Testing
@testable import AppleOnDeviceModelDemo

struct NaturalLanguageExperienceTests {
    @Test @MainActor func viewModelPublishesSnapshotAndDeterministicElapsedTime() async {
        let adapter = StubNaturalLanguageFrameworkAdapter(result: .init(
            languageCode: "en", tokens: [], entities: [], sentimentScore: 0.25
        ))
        var clockValues = [4.0, 4.5]
        let model = NaturalLanguageViewModel(
            analyzer: NaturalLanguageAnalyzer(adapter: adapter),
            currentTime: { clockValues.removeFirst() }
        )
        model.input = "  hello  "
        await model.run()

        #expect(model.inputSnapshot == "hello")
        #expect(model.result?.sentimentLabel == "Positive")
        #expect(model.latency == 0.5)
        #expect(model.errorMessage == nil)
    }

    @Test @MainActor func viewModelCancellationDoesNotPublishAnError() async {
        let model = NaturalLanguageViewModel()
        model.input = "hello"
        let run = Task { @MainActor in await model.run() }
        model.cancel()
        await run.value

        #expect(model.errorMessage == nil)
        #expect(!model.isRunning)
    }

    @Test func analyzerMapsFrameworkValuesToStableDisplayValues() {
        let adapter = StubNaturalLanguageFrameworkAdapter(result: .init(
            languageCode: "en",
            tokens: [
                .init(text: "Apple", range: 0..<5, lexicalClass: "Noun"),
                .init(text: "opened", range: 6..<12, lexicalClass: "Verb"),
            ],
            entities: [.init(text: "London", range: 26..<32, tag: "Place")],
            sentimentScore: 0.6
        ))

        let result = NaturalLanguageAnalyzer(adapter: adapter).analyze("Apple opened an office in London.")

        #expect(result.language == "English")
        #expect(result.tokens == [
            .init(text: "Apple", range: 0..<5, lexicalClass: "Noun"),
            .init(text: "opened", range: 6..<12, lexicalClass: "Verb"),
        ])
        #expect(result.entities == [.init(text: "London", range: 26..<32, kind: "Place")])
        #expect(result.sentimentScore == 0.6)
        #expect(result.sentimentLabel == "Positive")
    }

    @Test func analyzerKeepsUnicodeRangesAndMixedLanguageText() {
        let input = "你好, café London"
        let adapter = StubNaturalLanguageFrameworkAdapter(result: .init(
            languageCode: "zh",
            tokens: [
                .init(text: "你好", range: 0..<2, lexicalClass: "OtherWord"),
                .init(text: "café", range: 4..<8, lexicalClass: "Noun"),
                .init(text: "London", range: 9..<15, lexicalClass: "Noun"),
            ],
            entities: [.init(text: "London", range: 9..<15, tag: "Place")],
            sentimentScore: -0.3
        ))

        let result = NaturalLanguageAnalyzer(adapter: adapter).analyze(input)

        #expect(result.language == "Chinese")
        #expect(result.tokens.map(\.range) == [0..<2, 4..<8, 9..<15])
        #expect(result.tokens.map(\.text) == ["你好", "café", "London"])
        #expect(result.tokens[0].lexicalClass == "Other word")
        #expect(result.entities == [.init(text: "London", range: 9..<15, kind: "Place")])
        #expect(result.sentimentLabel == "Negative")
    }

    @Test func analyzerUsesNeutralEmptyDisplayWithoutCallingFramework() {
        let adapter = StubNaturalLanguageFrameworkAdapter(result: .init(
            languageCode: "en", tokens: [.init(text: "unexpected", range: 0..<10, lexicalClass: "Noun")],
            entities: [], sentimentScore: 1
        ))

        let result = NaturalLanguageAnalyzer(adapter: adapter).analyze("   \n")

        #expect(result.language == "Undetermined")
        #expect(result.tokens.isEmpty)
        #expect(result.entities.isEmpty)
        #expect(result.sentimentScore == 0)
        #expect(result.sentimentLabel == "Neutral")
        #expect(!adapter.wasCalled)
    }

    @Test func analyzerMapsSentimentBoundariesDeterministically() {
        for (score, label) in [(-0.25, "Negative"), (-0.01, "Negative"), (0.0, "Neutral"), (0.25, "Positive")] {
            let result = NaturalLanguageAnalyzer(
                adapter: StubNaturalLanguageFrameworkAdapter(result: .init(
                    languageCode: "en", tokens: [], entities: [], sentimentScore: score
                ))
            ).analyze("text")
            #expect(result.sentimentLabel == label)
        }
    }

    @Test func analyzerAveragesSentimentAcrossParagraphsBeforeLabeling() {
        let result = NaturalLanguageAnalyzer(
            adapter: StubNaturalLanguageFrameworkAdapter(result: .init(
                languageCode: "en", tokens: [], entities: [], sentimentScore: nil,
                sentimentScores: [0.8, -0.4]
            ))
        ).analyze("Great.\nAwful.")

        #expect(result.sentimentScore == 0.2)
        #expect(result.sentimentLabel == "Positive")
    }
}

#if !targetEnvironment(simulator)
struct PhysicalDeviceNaturalLanguageTests {
    @Test @MainActor
    func exercisesNaturalLanguageFrameworkOnPhysicalDevice() async {
        let viewModel = NaturalLanguageViewModel()
        viewModel.input = "Apple opened a research office in Moscow."
        await viewModel.run()

        if let result = viewModel.result {
            #expect(!result.language.isEmpty)
            #expect(!result.tokens.isEmpty)
            print("DEVICE_RESULT|LANG-06|PASS|language=\(result.language)|tokens=\(result.tokens.count)|entities=\(result.entities.count)|sentiment=\(result.sentimentLabel)")
        } else {
            Issue.record("NaturalLanguage returned no result: \(viewModel.errorMessage ?? "unknown error")")
            print("DEVICE_RESULT|LANG-06|FAIL_APP|\(viewModel.errorMessage ?? "unknown error")")
        }
    }
}
#endif

private final class StubNaturalLanguageFrameworkAdapter: NaturalLanguageFrameworkAdapter, @unchecked Sendable {
    let result: NaturalLanguageFrameworkResult
    private(set) var wasCalled = false

    init(result: NaturalLanguageFrameworkResult) {
        self.result = result
    }

    func analyze(_ text: String) -> NaturalLanguageFrameworkResult {
        wasCalled = true
        return result
    }
}
