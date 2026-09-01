import Testing
@testable import AppleOnDeviceModelDemo

struct ExperienceCatalogTests {
    @Test func smsClassificationIsListedInLanguageTextAndResolvesToItsDestination() {
        let item = ExperienceCatalog[.smsClassification]

        #expect(item.title == "SMS Classification")
        #expect(item.category == .languageText)
        #expect(item.requirement == .appleIntelligence)
        #expect(AppRouteResolver.items(in: .languageText).map(\.id).contains(.smsClassification))
        #expect(AppRouteResolver.destinationKind(for: .experience(.smsClassification)) == .experience(.smsClassification))
        #expect(ExperienceCatalog.pageContract(for: .smsClassification).destination == .experience(.smsClassification))
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

    @Test func homeDirectoryListsEveryExperienceExactlyOnceUnderItsCategory() {
        let sections = HomeDirectoryContent.sections
        let listedIDs = sections.flatMap(\.itemIDs)

        #expect(sections.map(\.category) == ExperienceCategory.allCases)
        #expect(listedIDs.count == ExperienceID.allCases.count)
        #expect(Set(listedIDs) == Set(ExperienceID.allCases))
        for section in sections {
            #expect(section.itemIDs == AppRouteResolver.items(in: section.category).map(\.id))
            #expect(section.itemIDs.allSatisfy { ExperienceCatalog[$0].category == section.category })
        }
    }

    @Test func displayCopyUsesValuesForAccessibilityAndStatusText() {
        #expect(ExperienceDisplayCopy.openingHint(for: "Speech Transcription") == "Opens Speech Transcription")
        #expect(ExperienceDisplayCopy.seeAllLabel(for: .languageText) == "See all Language & Text")
        #expect(ExperienceDisplayCopy.categorySummary(for: 7) == "Explore 7 native capability experiences.")
        #expect(ExperienceDisplayCopy.preparedInputMessage(for: "FoundationModels") == "Input is ready for the FoundationModels integration.")
    }

    @Test func gridCardPresentationKeepsStatusSemanticAndAccessible() {
        let presentation = ExperienceGridCardPresentation(experience: ExperienceCatalog[.foundationModel])

        #expect(presentation.title == "Foundation Model")
        #expect(presentation.status == "Requires Apple Intelligence")
        #expect(presentation.accessibilityLabel == "Foundation Model. Requires Apple Intelligence")
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

    @Test func categorySelectionAndSeeAllProduceOnlyCategoryRoutes() {
        for category in ExperienceCategory.allCases {
            #expect(AppRouteResolver.categorySelection(for: category) == .category(category))
            #expect(AppRouteResolver.seeAllSelection(for: category) == .category(category))
        }
    }

    @Test func categorySubsetsAndFeaturedOrderMatchTheHandDerivedGallery() {
        #expect(AppRouteResolver.items(in: .languageText).map(\.id) == [
            .foundationModel, .guidedGeneration, .contentTagging, .smsClassification, .streaming,
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

        #expect(ids.count == 18)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(ExperienceID.allCases))
    }

    @Test func everyExperienceHasTheHandDerivedCategory() {
        let expected: [ExperienceID: ExperienceCategory] = [
            .foundationModel: .languageText,
            .guidedGeneration: .languageText,
            .contentTagging: .languageText,
            .smsClassification: .languageText,
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
            .smsClassification: .appleIntelligence,
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

        #expect(Set(allRoutes).count == 22)
        #expect(Set(experienceRoutes).count == 18)
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

        #expect(homeItems.count == 18)
        #expect(languageItems.map(\.id) == [
            .foundationModel, .guidedGeneration, .contentTagging, .smsClassification, .streaming,
            .toolCalling, .translation, .naturalLanguage
        ])
        #expect(AppRoute.category(.languageText) != AppRoute.experience(.contentTagging))
    }
}
