enum ExperienceCategory: String, CaseIterable, Hashable, Sendable {
    case languageText = "Language & Text"
    case cameraVision = "Camera & Vision"
    case voiceSound = "Voice & Sound"
    case createSystem = "Create & System"
}

enum ExperienceID: String, CaseIterable, Hashable, Sendable {
    case foundationModel, guidedGeneration, contentTagging, smsClassification, streaming
    case toolCalling, translation, naturalLanguage, vision
    case speechTranscription, soundRecognition, imageCreator
    case imagePlayground, writingTools, genmoji, smartReply
    case appIntents, customAdapter
}

enum ExperienceRequirement: Equatable, Sendable {
    case none, appleIntelligence, languageAssets, microphone
    case photoLibrary, systemUI, entitlementAndAsset
}

struct ExperienceDefinition: Identifiable, Hashable, Sendable {
    let id: ExperienceID
    let title: String
    let summary: String
    let framework: String
    let category: ExperienceCategory
    let requirement: ExperienceRequirement
    let symbolName: String
}

enum ExperienceActionBoundary: String, CaseIterable, Hashable, Sendable {
    case foundationModelPrompt = "Foundation Model prompt"
    case guidedGeneration = "Guided structured generation"
    case contentTagging = "Content tagging"
    case smsClassification = "SMS classification"
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

    static func seeAllLabel(for category: ExperienceCategory) -> String {
        "See all \(category.rawValue)"
    }

    static func categorySummary(for count: Int) -> String {
        "Explore \(count) native capability experiences."
    }

    static func preparedInputMessage(for framework: String) -> String {
        "Input is ready for the \(framework) integration."
    }
}
