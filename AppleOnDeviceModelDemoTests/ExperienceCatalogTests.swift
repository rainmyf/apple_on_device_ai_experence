import Testing
@testable import AppleOnDeviceModelDemo

struct ExperienceCatalogTests {
    @Test func everyExperiencePublishesVersionedAPIOnDeviceAndLifecycleMetadata() {
        #expect(ExperienceCatalog.all.count == ExperienceID.allCases.count)

        let expected: [ExperienceID: (String, String, Bool, ExperienceLifecycle)] = [
            .foundationModel: ("iOS 26.0", "SystemLanguageModel.default", true, .active),
            .guidedGeneration: ("iOS 26.0", "LanguageModelSession.respond(to:)", true, .active),
            .contentTagging: ("iOS 26.0", "Generable", true, .active),
            .streaming: ("iOS 26.0", "LanguageModelSession.streamResponse(to:)", true, .active),
            .toolCalling: ("iOS 26.0", "LanguageModelSession.Tool", true, .active),
            .translation: ("iOS 26.0", "TranslationSession", true, .active),
            .naturalLanguage: ("iOS 2.0", "NLTagger", true, .active),
            .vision: ("iOS 13.0", "VNRecognizeTextRequest", true, .active),
            .speechTranscription: ("iOS 26.0", "SpeechTranscriber", true, .active),
            .soundRecognition: ("iOS 13.0", "SNAudioStreamAnalyzer", true, .active),
            .imageCreator: ("iOS 26.4", "ImageCreator", true, .deprecated),
            .imagePlayground: ("iOS 18.1", "ImagePlaygroundViewController", true, .active),
            .writingTools: ("iOS 18.0", "SwiftUI.View.writingToolsBehavior(_:)", true, .active),
            .genmoji: ("iOS 26.0", "UITextView", true, .active),
            .smartReply: ("iOS 18.4", "UIConversationContext + UISmartReplySuggestion", true, .active),
            .appIntents: ("iOS 16.0", "AppIntent", true, .active),
            .customAdapter: ("iOS 26.0", "SystemLanguageModel.Adapter", true, .obsoleted),
        ]

        for item in ExperienceCatalog.all {
            #expect((item.minimumOSVersion, item.openedAPI, item.isOnDevice, item.lifecycle) == expected[item.id]!)
        }
    }

    @Test func iOS27MetadataKeepsSpecialLifecycleBoundariesExplicit() {
        #expect(ExperienceCatalog[.imageCreator].minimumOSVersion == "iOS 26.4")
        #expect(ExperienceCatalog[.imageCreator].openedAPI == "ImageCreator")
        #expect(ExperienceCatalog[.imageCreator].lifecycle == .deprecated)

        #expect(ExperienceCatalog[.customAdapter].minimumOSVersion == "iOS 26.0")
        #expect(ExperienceCatalog[.customAdapter].openedAPI == "SystemLanguageModel.Adapter")
        #expect(ExperienceCatalog[.customAdapter].lifecycle == .obsoleted)
    }

    @Test func homepageOffersBothDirectionsAndEveryVisibleCategory() {
        #expect(HomeDirectionContent.entries.map(\.route) == [
            .experience(.foundationModel),
            .experience(.appIntents),
        ])
        #expect(HomeDirectionContent.entries.map(\.title) == [
            "App → On-device model",
            "系统智能调用 App",
        ])
        #expect(HomeDirectoryContent.sections.map(\.category) == ExperienceCategory.allCases)
    }

    @Test func visibleExperienceCardsExposeTheirMinimumOSVersionBadge() {
        let presentation = ExperienceGridCardPresentation(experience: ExperienceCatalog[.imageCreator])

        #expect(presentation.versionBadge == "iOS 26.4")
    }

    @Test func everyExperienceHasOneDestinationMetadataAndActionBoundary() {
        let contracts = ExperienceCatalog.pageContracts

        #expect(contracts.count == ExperienceID.allCases.count)
        #expect(Set(contracts.map(\.id)) == Set(ExperienceID.allCases))
        #expect(Set(contracts.map(\.destination)).count == ExperienceID.allCases.count)

        for contract in contracts {
            #expect(contract.destination == .experience(contract.id))
            #expect(!contract.metadata.intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!contract.metadata.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!contract.metadata.usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(contract.metadata.actionBoundaries.count == 1)
        }
    }

    @Test func catalogContractHasNoAggregateOrExternalServiceMessaging() {
        let forbidden = ["benchmark", "run all", "run-all", "cloud"]
        for contract in ExperienceCatalog.pageContracts {
            let text = [
                contract.metadata.intro,
                contract.metadata.status,
                contract.metadata.usage,
                contract.metadata.actionBoundaries.map(\.rawValue).joined(separator: " ")
            ].joined(separator: " ").lowercased()

            for term in forbidden {
                #expect(!text.contains(term))
            }
        }
    }

    @Test func homeCuratedSectionsMatchTheHandDerivedFourCategoryModel() {
        let expected: [ExperienceCategory: [ExperienceID]] = [
            .languageText: [.foundationModel, .translation, .contentTagging],
            .cameraVision: [.vision],
            .voiceSound: [.speechTranscription, .soundRecognition],
            .createSystem: [.imageCreator, .imagePlayground, .writingTools, .genmoji, .appIntents],
        ]

        #expect(HomeCuratedContent.sections.map(\.category) == ExperienceCategory.allCases)
        for section in HomeCuratedContent.sections {
            #expect(section.itemIDs == expected[section.category])
            for id in section.itemIDs {
                #expect(ExperienceCatalog[id].category == section.category)
            }
        }
    }

    @Test func homeDirectoryListsEveryVisibleExperienceExactlyOnceUnderItsCategory() {
        let sections = HomeDirectoryContent.sections
        let listedIDs = sections.flatMap(\.itemIDs)
        let expectedIDs = Set(ExperienceID.allCases)

        #expect(sections.map(\.category) == ExperienceCategory.allCases)
        #expect(listedIDs.count == expectedIDs.count)
        #expect(Set(listedIDs) == expectedIDs)
        for section in sections {
            #expect(section.itemIDs == AppRouteResolver.items(in: section.category).map(\.id))
            #expect(section.itemIDs.allSatisfy { ExperienceCatalog[$0].category == section.category })
        }
    }

    @Test func displayCopyUsesValuesForAccessibilityAndStatusText() {
        #expect(ExperienceDisplayCopy.openingHint(for: "Speech Transcription") == "Opens Speech Transcription")
        #expect(ExperienceDisplayCopy.categorySummary(for: 7) == "Explore 7 native capability experiences.")
        #expect(ExperienceDisplayCopy.preparedInputMessage(for: "FoundationModels") == "Input is ready for the FoundationModels integration.")
    }

    @Test func gridCardPresentationKeepsStatusSemanticAndAccessible() {
        let presentation = ExperienceGridCardPresentation(experience: ExperienceCatalog[.foundationModel])

        #expect(presentation.title == "Foundation Model")
        #expect(presentation.status == "Requires Apple Intelligence")
        #expect(presentation.accessibilityLabel == "Foundation Model. iOS 26.0. Requires Apple Intelligence")
    }

    @Test func gridCardPolicyPreservesTwoColumnGalleryWithBoundedText() {
        #expect(ExperienceGridCardPolicy.columnCount == 2)
        #expect(ExperienceGridCardPolicy.titleLineLimit == 2)
        #expect(ExperienceGridCardPolicy.statusLineLimit == 3)
    }

    @Test func everyCatalogEntryResolvesToAnExperienceRoute() {
        for item in ExperienceCatalog.all {
            #expect(AppRoute.experience(item.id) == .experience(item.id))
        }
    }

    @Test func everyCatalogEntryUsesThePureRouteResolver() {
        for item in ExperienceCatalog.all {
            #expect(AppRouteResolver.route(for: item) == .experience(item.id))
        }
    }

    @Test func everyExperienceAndCategoryResolvesToExactlyOneDestinationKind() {
        for id in ExperienceID.allCases {
            let destination = AppRouteResolver.destinationKind(for: .experience(id))
            #expect(destination == .experience(id))
        }

        for category in ExperienceCategory.allCases {
            let destination = AppRouteResolver.destinationKind(for: .category(category))
            #expect(destination == .category(category))
        }
    }

    @Test func homeSelectionProducesOnlyAnExperienceRoute() {
        let selected = ExperienceCatalog.featured[1]

        #expect(AppRouteResolver.homeSelection(for: selected) == .experience(.contentTagging))
    }

    @Test func categorySelectionProducesOnlyCategoryRoutes() {
        for category in ExperienceCategory.allCases {
            #expect(AppRouteResolver.categorySelection(for: category) == .category(category))
        }
    }

    @Test func categorySubsetsAndFeaturedOrderMatchTheHandDerivedGallery() {
        #expect(AppRouteResolver.items(in: .languageText).map(\.id) == [
            .foundationModel, .guidedGeneration, .contentTagging, .streaming,
            .toolCalling, .translation, .naturalLanguage
        ])
        #expect(AppRouteResolver.items(in: .cameraVision).map(\.id) == [.vision])
        #expect(AppRouteResolver.items(in: .voiceSound).map(\.id) == [
            .speechTranscription, .soundRecognition
        ])
        #expect(AppRouteResolver.items(in: .createSystem).map(\.id) == [
            .imageCreator, .imagePlayground, .writingTools, .genmoji,
            .smartReply, .appIntents, .customAdapter
        ])
        #expect(AppRouteResolver.featuredItems.map(\.id) == [
            .speechTranscription, .contentTagging, .imageCreator
        ])
    }

    @Test func unavailableEntriesRemainNavigable() {
        let unavailable = ExperienceCatalog.all.filter { $0.requirement != .none }

        #expect(unavailable.count == 16)
        for item in unavailable {
            #expect(AppRouteResolver.route(for: item) == .experience(item.id))
            #expect(AppRouteResolver.destinationKind(for: AppRouteResolver.route(for: item)) == .experience(item.id))
        }
    }

    @Test func containsEveryApprovedExperienceExactlyOnce() {
        let ids = ExperienceCatalog.all.map(\.id)

        #expect(ids.count == 17)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(ExperienceID.allCases))
    }

    @Test func everyExperienceHasTheHandDerivedCategory() {
        let expected: [ExperienceID: ExperienceCategory] = [
            .foundationModel: .languageText,
            .guidedGeneration: .languageText,
            .contentTagging: .languageText,
            .streaming: .languageText,
            .toolCalling: .languageText,
            .translation: .languageText,
            .naturalLanguage: .languageText,
            .vision: .cameraVision,
            .speechTranscription: .voiceSound,
            .soundRecognition: .voiceSound,
            .imageCreator: .createSystem,
            .imagePlayground: .createSystem,
            .writingTools: .createSystem,
            .genmoji: .createSystem,
            .smartReply: .createSystem,
            .appIntents: .createSystem,
            .customAdapter: .createSystem,
        ]

        #expect(ExperienceCatalog.all.count == expected.count)
        for definition in ExperienceCatalog.all {
            #expect(expected[definition.id] == definition.category)
        }
    }

    @Test func contentTaggingIsLanguageAndTranslationDoesNotRequireAI() {
        #expect(ExperienceCatalog[.contentTagging].category == .languageText)
        #expect(ExperienceCatalog[.translation].requirement == .languageAssets)
    }

    @Test func everyExperienceHasTheHandDerivedRequirementBoundary() {
        let expected: [ExperienceID: ExperienceRequirement] = [
            .foundationModel: .appleIntelligence,
            .guidedGeneration: .appleIntelligence,
            .contentTagging: .appleIntelligence,
            .streaming: .appleIntelligence,
            .toolCalling: .appleIntelligence,
            .translation: .languageAssets,
            .naturalLanguage: .none,
            .vision: .photoLibrary,
            .speechTranscription: .microphone,
            .soundRecognition: .microphone,
            .imageCreator: .appleIntelligence,
            .imagePlayground: .systemUI,
            .writingTools: .systemUI,
            .genmoji: .systemUI,
            .smartReply: .systemUI,
            .appIntents: .none,
            .customAdapter: .entitlementAndAsset,
        ]

        for definition in ExperienceCatalog.all {
            #expect(expected[definition.id] == definition.requirement)
        }
    }

    @Test func featuredItemsAreIndependentDestinations() {
        #expect(ExperienceCatalog.featured.map(\.id) == [
            .speechTranscription, .contentTagging, .imageCreator
        ])
        #expect(Set(ExperienceCatalog.featured.map(\.id)).count == ExperienceCatalog.featured.count)
    }

    @Test func allExperienceAndCategoryRoutesAreUnique() {
        let experienceRoutes = ExperienceID.allCases.map(AppRoute.experience)
        let categoryRoutes = ExperienceCategory.allCases.map(AppRoute.category)
        let allRoutes = experienceRoutes + categoryRoutes

        #expect(Set(allRoutes).count == 21)
        #expect(Set(experienceRoutes).count == 17)
        #expect(Set(categoryRoutes).count == 4)

        for definition in ExperienceCatalog.all {
            let route = AppRoute.experience(definition.id)
            guard case let .experience(id) = route else {
                #expect(Bool(false))
                continue
            }
            #expect(id == definition.id)
        }
    }

    @Test func catalogReadsArePureValues() {
        let homeItems = ExperienceCatalog.all
        let languageItems = homeItems.filter { $0.category == .languageText }

        #expect(homeItems.count == 17)
        #expect(languageItems.map(\.id) == [
            .foundationModel, .guidedGeneration, .contentTagging, .streaming,
            .toolCalling, .translation, .naturalLanguage
        ])
        #expect(AppRoute.category(.languageText) != AppRoute.experience(.contentTagging))
    }
}
