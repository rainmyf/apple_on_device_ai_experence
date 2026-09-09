import Foundation
import FoundationModels

enum CapabilityStatus: String, Equatable, Sendable {
    case ready = "Ready on this device"
    case requiresAppleIntelligence = "Requires Apple Intelligence"
    case appleIntelligenceDisabled = "Apple Intelligence Disabled"
    case modelNotReady = "Model Not Ready"
    case assetsRequired = "Assets Required"
    case permissionRequired = "Permission Required"
    case selectedItemAccess = "Selected Item Access"
    case deviceNotEligible = "Device Not Eligible"
    case systemUIOnly = "System UI"
    case setupRequired = "Setup Required"
    case unsupported = "Unsupported"

    static func foundation(
        _ availability: SystemLanguageModel.Availability
    ) -> Self {
        switch availability {
        case .available:
            .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                .deviceNotEligible
            case .modelNotReady:
                .modelNotReady
            case .appleIntelligenceNotEnabled:
                .appleIntelligenceDisabled
            default:
                .unsupported
            }
        }
    }
}

struct CapabilityAvailability: Equatable, Sendable {
    let status: CapabilityStatus
    let detail: String

    init(status: CapabilityStatus, detail: String) {
        self.status = status
        self.detail = detail
    }

    init(
        requirement: ExperienceRequirement,
        foundationAvailability: SystemLanguageModel.Availability? = nil
    ) {
        switch requirement {
        case .none:
            self.init(
                status: .ready,
                detail: "No additional setup is required for this capability."
            )
        case .appleIntelligence:
            if let foundationAvailability {
                self = .foundation(foundationAvailability)
            } else {
                self.init(
                    status: .requiresAppleIntelligence,
                    detail: "This capability requires Apple Intelligence."
                )
            }
        case .languageAssets:
            self.init(
                status: .assetsRequired,
                detail: "Download the required language assets before running this capability."
            )
        case .microphone:
            self.init(
                status: .permissionRequired,
                detail: "Allow microphone access before running this capability."
            )
        case .photoLibrary:
            self.init(
                status: .selectedItemAccess,
                detail: "Choose an image with PhotosPicker; this app uses only the selected item."
            )
        case .systemUI:
            self.init(
                status: .systemUIOnly,
                detail: "This capability is provided by a system UI and cannot run in-app."
            )
        case .entitlementAndAsset:
            self.init(
                status: .setupRequired,
                detail: "Required entitlement and local assets must be configured first."
            )
        }
    }

    static func foundation(
        _ availability: SystemLanguageModel.Availability
    ) -> Self {
        let status = CapabilityStatus.foundation(availability)
        let detail: String

        switch availability {
        case .available:
            detail = "Foundation Model is available on this device."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                detail = "This device is not eligible for Foundation Model."
            case .modelNotReady:
                detail = "Foundation Model assets are not ready yet."
            case .appleIntelligenceNotEnabled:
                detail = "Enable Apple Intelligence in Settings to use Foundation Model."
            default:
                detail = "Foundation Model availability is not supported by this app yet."
            }
        }

        return Self(status: status, detail: detail)
    }

    var canOpenPage: Bool { true }
    var canRunInApp: Bool { status == .ready || status == .selectedItemAccess }
}
