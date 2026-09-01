import AppIntents

struct DescribeDemoCapabilityIntent: AppIntent {
    static let title: LocalizedStringResource = "Describe an On-device Capability"

    @Parameter(title: "Capability")
    var capability: String

    init() {}

    init(capability: String) {
        self.init()
        self.capability = capability
    }

    static func configured(for capability: String) -> Self {
        let intent = Self(capability: capability)
        return intent
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: "Open On-device Experiences to try \(capability) separately.")
    }
}
