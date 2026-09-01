import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.985, green: 0.975, blue: 0.955)
    static let ink = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let secondaryInk = Color(red: 0.40, green: 0.40, blue: 0.42)
    static let cardStroke = Color.black.opacity(0.08)

    static func accent(for category: ExperienceCategory) -> Color {
        switch category {
        case .languageText: Color(red: 0.94, green: 0.30, blue: 0.18)
        case .cameraVision: Color(red: 0.32, green: 0.66, blue: 0.28)
        case .voiceSound: Color(red: 0.08, green: 0.42, blue: 0.96)
        case .createSystem: Color(red: 0.55, green: 0.28, blue: 0.78)
        }
    }

    static func categorySymbol(for category: ExperienceCategory) -> String {
        switch category {
        case .languageText: "textformat"
        case .cameraVision: "eye"
        case .voiceSound: "waveform"
        case .createSystem: "wand.and.stars"
        }
    }
}

extension ExperienceRequirement {
    var availabilityDescription: String {
        switch self {
        case .none: "Ready on this device"
        case .appleIntelligence: "Requires Apple Intelligence"
        case .languageAssets: "Requires language assets"
        case .microphone: "Requires microphone"
        case .photoLibrary: "Uses selected image access"
        case .systemUI: "System integration"
        case .entitlementAndAsset: "Requires entitlement and asset"
        }
    }
}
