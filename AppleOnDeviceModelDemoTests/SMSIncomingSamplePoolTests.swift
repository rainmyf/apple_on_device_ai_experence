import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

struct SMSIncomingSamplePoolTests {
    @Test
    func bundledPoolContainsTheApprovedFiveCategoryCorpus() throws {
        let pool = try SMSIncomingSamplePool.bundled(bundle: Bundle(for: SMSIncomingSamplePoolTestBundle.self))

        #expect(pool.count(for: .delivery) == 20)
        #expect(pool.count(for: .bankRepayment) == 10)
        #expect(pool.count(for: .trainWaitlistSuccess) == 10)
        #expect(pool.count(for: .weatherAlert) == 4)
        #expect(pool.count(for: .ordinary) == 10)
    }

    @Test
    func groupsSamplesByTheFiveLiveActivityCategories() throws {
        let pool = try SMSIncomingSamplePool(samples: [
            SMSIncomingSample(id: "delivery-self", category: .delivery, text: "请凭取件码 A1 取件"),
            SMSIncomingSample(id: "delivery-store", category: .delivery, text: "请到便利店取包裹"),
            SMSIncomingSample(id: "bank", category: .bankRepayment, text: "账单还款提醒"),
            SMSIncomingSample(id: "train", category: .trainWaitlistSuccess, text: "候补订单已兑现成功"),
            SMSIncomingSample(id: "weather", category: .weatherAlert, text: "Сильный дождь"),
            SMSIncomingSample(id: "ordinary", category: .ordinary, text: "欢迎参加活动")
        ])

        #expect(pool.count(for: .delivery) == 2)
        #expect(pool.count(for: .bankRepayment) == 1)
        #expect(pool.count(for: .trainWaitlistSuccess) == 1)
        #expect(pool.count(for: .weatherAlert) == 1)
        #expect(pool.count(for: .ordinary) == 1)
    }

    @Test
    func randomSelectionNeverEscapesTheRequestedCategory() throws {
        let pool = try SMSIncomingSamplePool(samples: [
            SMSIncomingSample(id: "delivery-1", category: .delivery, text: "请凭取件码 A1 取件"),
            SMSIncomingSample(id: "delivery-2", category: .delivery, text: "请到便利店取包裹"),
            SMSIncomingSample(id: "ordinary", category: .ordinary, text: "欢迎参加活动")
        ])

        for _ in 0..<20 {
            let sample = try pool.randomSample(for: .delivery)
            #expect(sample.category == .delivery)
            #expect(!sample.text.isEmpty)
        }
    }

    @Test
    func rejectsAnEmptyPool() {
        #expect(throws: SMSIncomingSamplePoolError.emptyPool) {
            try SMSIncomingSamplePool(samples: [])
        }
    }
}

private final class SMSIncomingSamplePoolTestBundle: NSObject {}
