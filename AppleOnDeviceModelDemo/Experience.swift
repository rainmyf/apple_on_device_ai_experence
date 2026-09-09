enum ExperienceCategory: String, CaseIterable, Hashable, Sendable {
    case languageText = "Language & Text"
    case cameraVision = "Camera & Vision"
    case voiceSound = "Voice & Sound"
    case createSystem = "Create & System"
}

enum ExperienceID: String, CaseIterable, Hashable, Sendable {
    case foundationModel, guidedGeneration, contentTagging, streaming
    case toolCalling, translation, naturalLanguage, vision
    case speechTranscription, soundRecognition, imageCreator
    case imagePlayground, writingTools, genmoji, smartReply
    case appIntents, customAdapter
}

enum ExperienceRequirement: Equatable, Sendable {
    case none, appleIntelligence, languageAssets, microphone
    case photoLibrary, systemUI, entitlementAndAsset
}

enum ExperienceLifecycle: String, CaseIterable, Hashable, Sendable {
    case active = "Active"
    case deprecated = "Deprecated"
    case obsoleted = "Obsoleted"
}

struct ExperienceDefinition: Identifiable, Hashable, Sendable {
    let id: ExperienceID
    let title: String
    let summary: String
    let framework: String
    let category: ExperienceCategory
    let requirement: ExperienceRequirement
    let symbolName: String
    let minimumOSVersion: String
    let openedAPI: String
    let isOnDevice: Bool
    let lifecycle: ExperienceLifecycle

    var versionBadge: String {
        minimumOSVersion
    }
}

enum ExperienceActionBoundary: String, CaseIterable, Hashable, Sendable {
    case foundationModelPrompt = "Foundation Model prompt"
    case guidedGeneration = "Guided structured generation"
    case contentTagging = "Content tagging"
    case streaming = "Streaming response"
    case toolCalling = "Local tool calling"
    case translation = "System translation"
    case naturalLanguage = "Natural language analysis"
    case vision = "Vision analysis"
    case speechTranscription = "Speech transcription"
    case soundRecognition = "Sound recognition"
    case imageCreator = "Image creation"
    case imagePlayground = "Image Playground system UI"
    case writingTools = "Writing Tools system UI"
    case genmoji = "Genmoji system UI"
    case smartReply = "Smart Reply system UI"
    case appIntents = "App Intent action"
    case customAdapter = "Custom adapter setup"
}

struct ExperiencePageMetadata: Equatable, Sendable {
    let intro: String
    let status: String
    let usage: String
    let actionBoundaries: Set<ExperienceActionBoundary>
}

struct ExperiencePageContract: Equatable, Sendable {
    let id: ExperienceID
    let destination: ExperienceDestinationKind
    let metadata: ExperiencePageMetadata
}

struct HomeCuratedSection: Equatable, Sendable {
    let category: ExperienceCategory
    let itemIDs: [ExperienceID]
}

struct HomeDirectionEntry: Equatable, Sendable {
    let title: String
    let summary: String
    let route: AppRoute
}

enum HomeDirectionContent {
    static let entries: [HomeDirectionEntry] = [
        HomeDirectionEntry(
            title: "App → On-device model",
            summary: "Start with an app prompt and inspect the native model boundary.",
            route: .experience(.foundationModel)
        ),
        HomeDirectionEntry(
            title: "系统智能调用 App",
            summary: "验证系统智能如何发现并调用 App 的本地实况窗动作。",
            route: .experience(.appIntents)
        ),
    ]
}

enum HomeCuratedContent {
    static let sections: [HomeCuratedSection] = [
        HomeCuratedSection(category: .languageText, itemIDs: [.foundationModel, .translation, .contentTagging]),
        HomeCuratedSection(category: .cameraVision, itemIDs: [.vision]),
        HomeCuratedSection(category: .voiceSound, itemIDs: [.speechTranscription, .soundRecognition]),
        HomeCuratedSection(category: .createSystem, itemIDs: [.imageCreator, .imagePlayground, .writingTools, .genmoji, .appIntents]),
    ]

    static func items(in category: ExperienceCategory) -> [ExperienceDefinition] {
        sections.first { $0.category == category }?.itemIDs.map { ExperienceCatalog[$0] } ?? []
    }
}

enum HomeDirectoryContent {
    static let sections: [HomeCuratedSection] = ExperienceCategory.allCases.map { category in
        HomeCuratedSection(
            category: category,
            itemIDs: AppRouteResolver.items(in: category).map(\.id)
        )
    }
}

enum ExperienceDisplayCopy {
    static func openingHint(for title: String) -> String {
        "Opens \(title)"
    }

    static func categorySummary(for count: Int) -> String {
        "Explore \(count) native capability experiences."
    }

    static func preparedInputMessage(for framework: String) -> String {
        "Input is ready for the \(framework) integration."
    }
}
