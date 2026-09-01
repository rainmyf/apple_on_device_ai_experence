import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

struct SMSRandomSamplesTests {
    @Test func parsesBlankMalformedAndEmptyRowsWhilePreservingUnicode() {
        let jsonl = """

        {"id":"delivery-1","text":"【速达】您的包裹已到达云杉街驿站，取件码：云😀42","expectedDomain":"delivery"}
        {not-json}
        {"id":"empty","text":""}
        {"id":"spaces","text":"   "}
        {"text":"缺少 id 但仍是有效短信"}
        """

        let samples = SMSJSONLParser.parse(jsonl)

        #expect(samples.map(\.text) == [
            "【速达】您的包裹已到达云杉街驿站，取件码：云😀42",
            "缺少 id 但仍是有效短信",
        ])
        #expect(samples[0].expectedDomain == "delivery")
        #expect(samples[1].id == "line-6")
    }

    @Test func parserAcceptsUTF8DataAndOptionalExpectedDomain() throws {
        let data = try #require("{\"id\":\"unicode\",\"text\":\"会议提醒：明天 09:30 在竹影路\"}".data(using: .utf8))

        let samples = SMSJSONLParser.parse(data)

        #expect(samples.count == 1)
        #expect(samples[0].text == "会议提醒：明天 09:30 在竹影路")
        #expect(samples[0].expectedDomain == nil)
    }

    @Test func pickerUsesInjectedIndexAndRejectsOutOfBounds() {
        let samples = [
            SMSSample(id: "a", text: "短信 A", expectedDomain: "delivery"),
            SMSSample(id: "b", text: "短信 B", expectedDomain: "train_ticket"),
            SMSSample(id: "c", text: "短信 C", expectedDomain: "ignored"),
        ]

        #expect(SMSRandomSamplePicker.next(from: samples, excluding: nil, randomIndex: 1)?.id == "b")
        #expect(SMSRandomSamplePicker.next(from: samples, excluding: nil, randomIndex: -1) == nil)
        #expect(SMSRandomSamplePicker.next(from: samples, excluding: nil, randomIndex: 3) == nil)
    }

    @Test func pickerAvoidsImmediateRepeatWhenMoreThanOneSampleExists() {
        let samples = [
            SMSSample(id: "a", text: "短信 A"),
            SMSSample(id: "b", text: "短信 B"),
        ]

        let next = SMSRandomSamplePicker.next(from: samples, excluding: samples[0], randomIndex: 0)

        #expect(next?.id == "b")
    }

    @Test func pickerExcludesThePreviouslySelectedSampleWhenIDsRepeat() {
        let samples = [
            SMSSample(id: "duplicate", text: "第一条不同短信"),
            SMSSample(id: "duplicate", text: "第二条不同短信"),
        ]

        let next = SMSRandomSamplePicker.next(from: samples, excluding: samples[0], randomIndex: 0)

        #expect(next?.text == "第二条不同短信")
    }

    @Test func pickerKeepsSingleSampleAvailableAndHandlesEmptyInput() {
        let one = [SMSSample(id: "only", text: "唯一短信")]

        #expect(SMSRandomSamplePicker.next(from: one, excluding: one[0], randomIndex: 0)?.id == "only")
        #expect(SMSRandomSamplePicker.next(from: [], excluding: nil, randomIndex: 0) == nil)
    }

    @Test func bundledStoreReturnsEmptyWhenResourceIsMissing() {
        let store = BundledSMSSampleStore(bundle: Bundle.main, resourceName: "resource-that-does-not-exist")

        #expect(store.load().isEmpty)
    }
}
