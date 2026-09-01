import FoundationModels
import Testing
@testable import AppleOnDeviceModelDemo

struct CapabilityAvailabilityTests {
    @Test func mapsFoundationReasonsWithoutLosingMeaning() {
        #expect(CapabilityStatus.foundation(.available) == .ready)
        #expect(
            CapabilityStatus.foundation(.unavailable(.deviceNotEligible))
                == .deviceNotEligible
        )
        #expect(
            CapabilityStatus.foundation(.unavailable(.modelNotReady))
                == .modelNotReady
        )
        #expect(
            CapabilityStatus.foundation(.unavailable(.appleIntelligenceNotEnabled))
                == .appleIntelligenceDisabled
        )

        let cases: [(SystemLanguageModel.Availability, CapabilityStatus, String)] = [
            (.available, .ready, "available"),
            (.unavailable(.deviceNotEligible), .deviceNotEligible, "eligible"),
            (.unavailable(.modelNotReady), .modelNotReady, "ready"),
            (
                .unavailable(.appleIntelligenceNotEnabled),
                .appleIntelligenceDisabled,
                "Apple Intelligence"
            ),
        ]

        for (availability, expectedStatus, expectedMeaning) in cases {
            let result = CapabilityAvailability.foundation(availability)
            #expect(result.status == expectedStatus)
            #expect(!result.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(result.detail.localizedCaseInsensitiveContains(expectedMeaning))
        }
    }

    @Test func mapsEveryExperienceRequirementToItsBoundary() {
        let expected: [(ExperienceRequirement, CapabilityStatus)] = [
            (.none, .ready),
            (.appleIntelligence, .requiresAppleIntelligence),
            (.languageAssets, .assetsRequired),
            (.microphone, .permissionRequired),
            (.photoLibrary, .selectedItemAccess),
            (.systemUI, .systemUIOnly),
            (.entitlementAndAsset, .setupRequired),
        ]

        for (requirement, expectedStatus) in expected {
            let result = CapabilityAvailability(requirement: requirement)
            #expect(result.status == expectedStatus)
            #expect(!result.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test func photosPickerUsesSelectedItemAccessInsteadOfPhotoLibraryPermission() {
        let availability = CapabilityAvailability(requirement: .photoLibrary)

        #expect(availability.status == .selectedItemAccess)
        #expect(availability.canRunInApp)
        #expect(availability.detail.localizedCaseInsensitiveContains("selected"))
    }

    @Test func requirementAppleIntelligenceUsesActualFoundationAvailabilityWhenProvided() {
        #expect(
            CapabilityAvailability(
                requirement: .appleIntelligence,
                foundationAvailability: .available
            ).status == .ready
        )
        #expect(
            CapabilityAvailability(
                requirement: .appleIntelligence,
                foundationAvailability: .unavailable(.modelNotReady)
            ).status == .modelNotReady
        )
    }

    @Test func everyStatusCanOpenItsPageButOnlyReadyCanRunInApp() {
        let expected: [(CapabilityStatus, Bool, Bool)] = [
            (.ready, true, true),
            (.requiresAppleIntelligence, true, false),
            (.appleIntelligenceDisabled, true, false),
            (.modelNotReady, true, false),
            (.assetsRequired, true, false),
            (.permissionRequired, true, false),
            (.selectedItemAccess, true, true),
            (.deviceNotEligible, true, false),
            (.systemUIOnly, true, false),
            (.setupRequired, true, false),
            (.unsupported, true, false),
        ]

        for (status, expectedCanOpenPage, expectedCanRunInApp) in expected {
            let result = CapabilityAvailability(status: status, detail: "test detail")
            #expect(result.canOpenPage == expectedCanOpenPage)
            #expect(result.canRunInApp == expectedCanRunInApp)
        }
    }

    @Test func unsupportedStatusIsSafeForUnknownFutureAvailability() {
        let result = CapabilityAvailability(
            status: .unsupported,
            detail: "This availability value is not supported by this app yet."
        )

        #expect(result.canOpenPage)
        #expect(!result.canRunInApp)
    }
}
