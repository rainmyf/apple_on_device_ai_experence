enum ExperienceCatalog {
    static let all: [ExperienceDefinition] = [
        ExperienceDefinition(
            id: .foundationModel,
            title: "Foundation Model",
            summary: "Ask the on-device language model for a free-form response.",
            framework: "FoundationModels",
            category: .languageText,
            requirement: .appleIntelligence,
            symbolName: "sparkles",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "SystemLanguageModel.default",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .guidedGeneration,
            title: "Guided Generation",
            summary: "Generate structured Swift output with guided constraints.",
            framework: "FoundationModels",
            category: .languageText,
            requirement: .appleIntelligence,
            symbolName: "list.bullet.rectangle",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "LanguageModelSession.respond(to:)",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .contentTagging,
            title: "Content Tagging",
            summary: "Extract topics, entities, actions, and emotions from text.",
            framework: "FoundationModels",
            category: .languageText,
            requirement: .appleIntelligence,
            symbolName: "tag",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "Generable",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .smsClassification,
            title: "SMS Classification",
            summary: "Classify one SMS and highlight the entities in its original text.",
            framework: "FoundationModels",
            category: .languageText,
            requirement: .appleIntelligence,
            symbolName: "message.badge.filled.fill",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "LanguageModelSession.respond(to:)",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .streaming,
            title: "Streaming",
            summary: "See incremental language model output as it arrives.",
            framework: "FoundationModels",
            category: .languageText,
            requirement: .appleIntelligence,
            symbolName: "text.line.first.and.arrowtriangle.forward",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "LanguageModelSession.streamResponse(to:)",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .toolCalling,
            title: "Tool Calling",
            summary: "Connect a language model session to a local deterministic tool.",
            framework: "FoundationModels",
            category: .languageText,
            requirement: .appleIntelligence,
            symbolName: "wrench.and.screwdriver",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "LanguageModelSession.Tool",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .translation,
            title: "Translation",
            summary: "Translate text with the system language assets.",
            framework: "Translation",
            category: .languageText,
            requirement: .languageAssets,
            symbolName: "character.bubble",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "TranslationSession",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .naturalLanguage,
            title: "Natural Language",
            summary: "Identify language, tokenize text, and find named entities.",
            framework: "NaturalLanguage",
            category: .languageText,
            requirement: .none,
            symbolName: "textformat",
            minimumOSVersion: "iOS 2.0",
            openedAPI: "NLTagger",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .vision,
            title: "Vision",
            summary: "Inspect a selected image with supported vision modes.",
            framework: "Vision",
            category: .cameraVision,
            requirement: .photoLibrary,
            symbolName: "viewfinder",
            minimumOSVersion: "iOS 13.0",
            openedAPI: "VNRecognizeTextRequest",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .speechTranscription,
            title: "Speech Transcription",
            summary: "Turn microphone speech into a live, finalized transcript.",
            framework: "Speech",
            category: .voiceSound,
            requirement: .microphone,
            symbolName: "waveform",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "SpeechTranscriber",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .soundRecognition,
            title: "Sound Recognition",
            summary: "Analyze a recording and rank the sounds it contains.",
            framework: "SoundAnalysis",
            category: .voiceSound,
            requirement: .microphone,
            symbolName: "waveform.badge.mic",
            minimumOSVersion: "iOS 13.0",
            openedAPI: "SNAudioStreamAnalyzer",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .imageCreator,
            title: "Image Creator",
            summary: "Create an image from a prompt when the API is available.",
            framework: "Image Playground",
            category: .createSystem,
            requirement: .appleIntelligence,
            symbolName: "photo.artframe",
            minimumOSVersion: "iOS 26.4",
            openedAPI: "ImageCreator",
            isOnDevice: true,
            lifecycle: .deprecated
        ),
        ExperienceDefinition(
            id: .imagePlayground,
            title: "Image Playground",
            summary: "Open the system-provided image generation experience.",
            framework: "ImagePlayground",
            category: .createSystem,
            requirement: .systemUI,
            symbolName: "wand.and.stars",
            minimumOSVersion: "iOS 18.1",
            openedAPI: "ImagePlaygroundViewController",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .writingTools,
            title: "Writing Tools",
            summary: "Use the system writing tools on editable text.",
            framework: "UIKit",
            category: .createSystem,
            requirement: .systemUI,
            symbolName: "pencil.and.outline",
            minimumOSVersion: "iOS 18.0",
            openedAPI: "SwiftUI.View.writingToolsBehavior(_:)",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .genmoji,
            title: "Genmoji",
            summary: "Follow the system text-input path for Genmoji.",
            framework: "UIKit",
            category: .createSystem,
            requirement: .systemUI,
            symbolName: "face.smiling",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "UITextView",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .smartReply,
            title: "Smart Reply",
            summary: "Explain the supported system conversation integration boundary.",
            framework: "UIKit",
            category: .createSystem,
            requirement: .systemUI,
            symbolName: "arrowshape.turn.up.left.2",
            minimumOSVersion: "iOS 18.4",
            openedAPI: "UIConversationContext + UISmartReplySuggestion",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .appIntents,
            title: "App Intents",
            summary: "Expose a harmless app action for system invocation.",
            framework: "AppIntents",
            category: .createSystem,
            requirement: .none,
            symbolName: "app.badge",
            minimumOSVersion: "iOS 16.0",
            openedAPI: "AppIntent",
            isOnDevice: true,
            lifecycle: .active
        ),
        ExperienceDefinition(
            id: .customAdapter,
            title: "Custom Adapter",
            summary: "Inspect local adapter assets and entitlement requirements.",
            framework: "FoundationModels",
            category: .createSystem,
            requirement: .entitlementAndAsset,
            symbolName: "shippingbox",
            minimumOSVersion: "iOS 26.0",
            openedAPI: "SystemLanguageModel.Adapter",
            isOnDevice: true,
            lifecycle: .obsoleted
        ),
    ]

    static let featured: [ExperienceDefinition] = [
        ExperienceCatalog[.speechTranscription],
        ExperienceCatalog[.contentTagging],
        ExperienceCatalog[.imageCreator],
    ]

    static let pageContracts: [ExperiencePageContract] = all.map { definition in
        ExperiencePageContract(
            id: definition.id,
            destination: .experience(definition.id),
            metadata: ExperiencePageMetadata(
                intro: definition.summary,
                status: definition.requirement.availabilityDescription,
                usage: usage(for: definition.id),
                actionBoundaries: [boundary(for: definition.id)]
            )
        )
    }

    static func pageContract(for id: ExperienceID) -> ExperiencePageContract {
        pageContracts.first { $0.id == id }!
    }

    static func pageMetadata(for id: ExperienceID) -> ExperiencePageMetadata {
        pageContract(for: id).metadata
    }

    static subscript(id: ExperienceID) -> ExperienceDefinition {
        all.first { $0.id == id }!
    }

    private static func boundary(for id: ExperienceID) -> ExperienceActionBoundary {
        switch id {
        case .foundationModel: .foundationModelPrompt
        case .guidedGeneration: .guidedGeneration
        case .contentTagging: .contentTagging
        case .smsClassification: .smsClassification
        case .streaming: .streaming
        case .toolCalling: .toolCalling
        case .translation: .translation
        case .naturalLanguage: .naturalLanguage
        case .vision: .vision
        case .speechTranscription: .speechTranscription
        case .soundRecognition: .soundRecognition
        case .imageCreator: .imageCreator
        case .imagePlayground: .imagePlayground
        case .writingTools: .writingTools
        case .genmoji: .genmoji
        case .smartReply: .smartReply
        case .appIntents: .appIntents
        case .customAdapter: .customAdapter
        }
    }

    private static func usage(for id: ExperienceID) -> String {
        switch id {
        case .foundationModel:
            "Enter one prompt, then review the response from the native model session."
        case .guidedGeneration:
            "Enter text, then review the typed fields returned by the guided request."
        case .contentTagging:
            "Enter text, then review topics, entities, actions, and emotions."
        case .smsClassification:
            "Paste one SMS, optionally choose a bundled sample, and review its source-preserving labels."
        case .streaming:
            "Enter one prompt, then observe ordered partial text and cancel when needed."
        case .toolCalling:
            "Ask for a local fact, then inspect the deterministic tool result."
        case .translation:
            "Choose a supported language pair, provide text, and review the translated output."
        case .naturalLanguage:
            "Provide text, then inspect language, token, entity, and sentiment details."
        case .vision:
            "Select one image and one supported mode, then inspect the findings."
        case .speechTranscription:
            "Allow microphone access, start speaking, and stop to review the transcript."
        case .soundRecognition:
            "Allow microphone access, record a sample, and review ranked sound labels."
        case .imageCreator:
            "Provide a prompt and review the generated image only when the system API is ready."
        case .imagePlayground:
            "Open the system experience and complete image creation in its own UI."
        case .writingTools:
            "Edit the sample text and invoke the system writing tools from the text editor."
        case .genmoji:
            "Edit the sample text and use the system text-input path for Genmoji."
        case .smartReply:
            "Review the conversation context and wait for suggestions from the system integration."
        case .appIntents:
            "Run the harmless app action and review its deterministic result."
        case .customAdapter:
            "Inspect the local adapter asset and signed setup state before attempting a load."
        }
    }
}
