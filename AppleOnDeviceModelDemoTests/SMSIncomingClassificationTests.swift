import Testing
@testable import AppleOnDeviceModelDemo

struct SMSIncomingClassificationTests {
    @Test
    func summaryUsesCategorySpecificFields() {
        let value = SMSIncomingClassification(category: .delivery, details: SMSIncomingDetails(pickupCode: "85692800", pickupLocation: "丰巢柜1号"), source: .model)
        #expect(value.summary.contains("85692800"))
        #expect(value.summary.contains("丰巢柜1号"))
    }

    @Test
    func invalidCategoryFallsBackToOrdinary() {
        let value = SMSIncomingPresentation.from(rawCategory: "not-a-category", source: .model)
        #expect(value.category == .ordinary)
        #expect(value.source == .fallback)
        #expect(value.fallbackReason == "invalidCategory")
    }
}
