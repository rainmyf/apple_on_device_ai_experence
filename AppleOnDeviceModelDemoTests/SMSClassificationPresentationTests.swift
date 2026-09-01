import Testing
@testable import AppleOnDeviceModelDemo

struct SMSClassificationPresentationTests {
    @Test func presentationReconstructsTheOriginalSourceInSourceOrder() {
        let source = "😀建设银行本期应还2750元。"
        let result = SMSAnnotationResult(
            domain: "repayment_information",
            entities: [
                SMSAnnotationEntity(text: "2750元", label: "due_amount", start: 10, end: 15),
                SMSAnnotationEntity(text: "建设银行", label: "org", start: 2, end: 6),
            ]
        )

        let presentation = SMSClassificationPresentation(source: source, result: result)

        #expect(presentation.segments.map(\.text).joined() == source)
        #expect(presentation.segments.map(\.text) == ["😀", "建设银行", "本期应还", "2750元", "。"])
        #expect(presentation.segments.map(\.label) == [nil, "org", nil, "due_amount", nil])
    }

    @Test func presentationKeepsEverySourceCharacterVisibleWhenThereAreNoEntities() {
        let source = "原始短信：请勿改写 😀"
        let presentation = SMSClassificationPresentation(source: source, result: nil)

        #expect(presentation.segments.map(\.text).joined() == source)
        #expect(presentation.segments.count == 1)
        #expect(presentation.segments[0].label == nil)
    }

    @Test func entityLabelsAreIncludedInAccessibleDescriptions() {
        let source = "建设银行本期应还2750元"
        let result = SMSAnnotationResult(
            domain: "repayment_information",
            entities: [
                SMSAnnotationEntity(text: "建设银行", label: "org", start: 0, end: 4),
                SMSAnnotationEntity(text: "2750元", label: "due_amount", start: 8, end: 13),
            ]
        )

        let presentation = SMSClassificationPresentation(source: source, result: result)

        #expect(presentation.accessibilityLabel == "建设银行本期应还2750元. Annotations: 建设银行 (org); 2750元 (due_amount)")
        #expect(presentation.accessibilityLabel.hasPrefix(source + ". Annotations:"))
        #expect(presentation.accessibilityLabel.contains("建设银行"))
        #expect(presentation.accessibilityLabel.contains("org"))
        #expect(presentation.accessibilityLabel.contains("2750元"))
        #expect(presentation.accessibilityLabel.contains("due_amount"))
    }

    @Test func accessibilityDescriptionKeepsUnannotatedCharactersInSourceOrder() {
        let source = "😀建设银行，本期应还2750元。"
        let result = SMSAnnotationResult(
            domain: "repayment_information",
            entities: [
                SMSAnnotationEntity(text: "建设银行", label: "org", start: 2, end: 6),
                SMSAnnotationEntity(text: "2750元", label: "due_amount", start: 11, end: 16),
            ]
        )

        let description = SMSClassificationPresentation(source: source, result: result).accessibilityLabel

        #expect(description == "😀建设银行，本期应还2750元。. Annotations: 建设银行 (org); 2750元 (due_amount)")
        #expect(description.contains("😀建设银行，本期应还2750元。"))
        #expect(description.firstIndex(of: "😀")! < description.firstIndex(of: "建")!)
        #expect(description.firstIndex(of: "，")! < description.firstIndex(of: "2")!)
        #expect(description.firstIndex(of: "。")! < description.range(of: ". Annotations:")!.lowerBound)
    }

    @Test func pageCopyExplainsTheOnDeviceImplementationBoundary() {
        let copy = SMSClassificationExperienceCopy.implementationPrinciple

        #expect(copy.contains("SystemLanguageModel.default"))
        #expect(copy.localizedCaseInsensitiveContains("Apple"))
        #expect(copy.localizedCaseInsensitiveContains("端侧"))
        #expect(copy.localizedCaseInsensitiveContains("local bundled rules/samples"))
        #expect(copy.localizedCaseInsensitiveContains("no network"))
        #expect(copy.localizedCaseInsensitiveContains("no cloud fallback"))
        #expect(copy.localizedCaseInsensitiveContains("generative demo"))
        #expect(copy.localizedCaseInsensitiveContains("production accuracy"))
    }

    @Test func buttonPresentationReflectsRunningAndInputAvailability() {
        let ready = SMSClassificationButtonPresentation(isRunning: false, canRun: true, hasSamples: true)
        #expect(ready.runTitle == "Run On-device Model")
        #expect(ready.runButtonEnabled)
        #expect(ready.randomButtonEnabled)

        let running = SMSClassificationButtonPresentation(isRunning: true, canRun: false, hasSamples: true)
        #expect(running.runTitle == "Cancel")
        #expect(!running.runButtonEnabled)
        #expect(!running.randomButtonEnabled)

        let empty = SMSClassificationButtonPresentation(isRunning: false, canRun: false, hasSamples: false)
        #expect(!empty.runButtonEnabled)
        #expect(!empty.randomButtonEnabled)
    }

    @Test func flowLayoutConstrainedMeasurementCapsLongNaturalWidthWithoutExpandingShortText() {
        #expect(SMSAnnotationFlowLayoutMetrics.constrainedWidth(naturalWidth: 1_000, availableWidth: 320) == 320)
        #expect(SMSAnnotationFlowLayoutMetrics.constrainedWidth(naturalWidth: 120, availableWidth: 320) == 120)
        #expect(SMSAnnotationFlowLayoutMetrics.constrainedWidth(naturalWidth: 1_000, availableWidth: 320) < 1_000)
    }
}
