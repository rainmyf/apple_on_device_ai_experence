import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

@available(iOS 27.0, *)
struct ExperienceEntity: IndexedEntity, Hashable, Sendable {
    typealias ID = String

    let id: ID
    let title: String
    let summary: String
    let framework: String
    let minimumOSVersion: String
    let openedAPI: String
    let isOnDevice: Bool
    let lifecycle: ExperienceLifecycle

    init(definition: ExperienceDefinition) {
        id = definition.id.rawValue
        title = definition.title
        summary = definition.summary
        framework = definition.framework
        minimumOSVersion = definition.minimumOSVersion
        openedAPI = definition.openedAPI
        isOnDevice = definition.isOnDevice
        lifecycle = definition.lifecycle
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "On-device Experience"
    }

    static var defaultQuery: ExperienceEntityQuery {
        ExperienceEntityQuery()
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title), subtitle: LocalizedStringResource(stringLiteral: framework))
    }

    var experienceID: ExperienceID? {
        ExperienceID(rawValue: id)
    }

    var route: AppRoute? {
        experienceID.map(AppRoute.experience)
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
        attributes.title = title
        attributes.contentDescription = "\(summary) Framework: \(framework). API: \(openedAPI). Minimum: \(minimumOSVersion)."
        attributes.keywords = [title, framework, openedAPI, minimumOSVersion]
        attributes.domainIdentifier = ExperienceIndexing.domainIdentifier
        attributes.relatedUniqueIdentifier = id
        return attributes
    }

    var hideInSpotlight: Bool {
        experienceID == .smsClassification
    }
}

@available(iOS 27.0, *)
struct ExperienceEntityQuery: EntityStringQuery {
    func entities(for identifiers: [ExperienceEntity.ID]) async throws -> [ExperienceEntity] {
        identifiers.compactMap { identifier in
            guard let id = ExperienceID(rawValue: identifier), id != .smsClassification else { return nil }
            return ExperienceCatalog.all.first { $0.id == id }.map(ExperienceEntity.init(definition:))
        }
    }

    func suggestedEntities() async throws -> [ExperienceEntity] {
        ExperienceIndexing.visibleEntities
    }

    func entities(matching string: String) async throws -> [ExperienceEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !query.isEmpty else { return try await suggestedEntities() }
        return ExperienceIndexing.visibleEntities.filter { entity in
            [entity.title, entity.summary, entity.framework, entity.minimumOSVersion, entity.openedAPI]
                .joined(separator: " ")
                .localizedLowercase
                .contains(query)
        }
    }
}

@available(iOS 27.0, *)
enum ExperienceIndexing {
    static let domainIdentifier = "com.example.AppleOnDeviceModelDemo.experiences"
    static let identifierPrefix = "experience:"

    static let visibleDefinitions: [ExperienceDefinition] = ExperienceCatalog.all.filter {
        $0.id != .smsClassification
    }

    static let visibleEntities: [ExperienceEntity] = visibleDefinitions.map(ExperienceEntity.init(definition:))

    static func searchableItems() -> [CSSearchableItem] {
        visibleEntities.map { entity in
            let attributes = entity.attributeSet
            attributes.associateAppEntity(entity)
            return CSSearchableItem(
                uniqueIdentifier: identifier(for: entity.id),
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }
    }

    static func identifier(for entityID: ExperienceEntity.ID) -> String {
        identifierPrefix + entityID
    }

    static func entityID(from identifier: String) -> ExperienceEntity.ID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return String(identifier.dropFirst(identifierPrefix.count))
    }

    @MainActor
    static func indexVisibleExperiences() async throws {
        let index = CSSearchableIndex.default()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                index.indexSearchableItems(searchableItems()) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}
