import SwiftUI

struct ExperienceDestinationView: View {
    let experience: ExperienceDefinition

    @ViewBuilder
    var body: some View {
        Group {
            switch experience.id {
            case .foundationModel:
                OnDeviceModelLabView()
            case .guidedGeneration:
                GuidedGenerationExperienceView()
            case .contentTagging:
                ContentTaggingExperienceView()
            case .naturalLanguage:
                NaturalLanguageExperienceView()
            case .translation:
                TranslationExperienceView()
            case .streaming:
                FoundationStreamingExperienceView()
            case .toolCalling:
                FoundationToolCallingExperienceView()
            case .vision:
                VisionExperienceView()
            case .speechTranscription:
                SpeechExperienceView()
            case .soundRecognition:
                SoundAnalysisExperienceView()
            case .imageCreator:
                ImageCreatorExperienceView()
            case .imagePlayground:
                ImagePlaygroundExperienceView()
            case .writingTools:
                WritingToolsExperienceView()
            case .genmoji:
                GenmojiExperienceView()
            case .smartReply:
                SmartReplyExperienceView()
            case .appIntents:
                AppIntentsExperienceView()
            case .customAdapter:
                CustomAdapterExperienceView()
            }
        }
        .dismissibleKeyboard()
    }
}
