import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

private final class SMSIncomingFakeSession: SMSIncomingModelSessionServing, @unchecked Sendable {
    let categoryResponse: SMSIncomingCategoryResult
    let detailsResponse: SMSIncomingDetailsResult
    var prompts: [String] = []
    init(categoryResponse: SMSIncomingCategoryResult, detailsResponse: SMSIncomingDetailsResult) {
        self.categoryResponse = categoryResponse
        self.detailsResponse = detailsResponse
    }
    func classifyCategory(for prompt: String) async throws -> SMSIncomingCategoryResult {
        prompts.append(prompt)
        return categoryResponse
    }
    func extractDetails(for prompt: String) async throws -> SMSIncomingDetailsResult {
        prompts.append(prompt)
        return detailsResponse
    }
}

struct SMSIncomingClassificationServiceTests {
    @Test
    func categoryPromptMakesWaitlistSuccessWinOverNumbersOrRefundLanguage() {
        let prompt = SMSIncomingClassificationPrompt.category(
            text: "【12306】候补订单已兑现成功，9月30日 G117 次北京南站至上海虹桥站，请查收差价38.0元。"
        )

        #expect(prompt.contains("候补订单已兑现成功"))
        #expect(prompt.contains("train_waitlist_success"))
        #expect(prompt.contains("must not be classified as bank_repayment"))
        #expect(prompt.contains("bank or credit-card repayment context"))
    }

    @Test
    func classifyUsesTwoStageModelAndPreservesDetails() async throws {
        let session = SMSIncomingFakeSession(
            categoryResponse: SMSIncomingCategoryResult(category: SMSIncomingCategory.delivery.rawValue),
            detailsResponse: SMSIncomingDetailsResult(pickupCode: "85692800", pickupLocation: "丰巢柜")
        )
        let service = SMSIncomingClassificationService(availabilityProvider: { _ in .available }, sessionFactory: { _ in session })
        let result = try await service.classify("请凭85692800至丰巢柜取件")
        #expect(result.category == .delivery)
        #expect(result.details.pickupCode == "85692800")
        #expect(session.prompts.count == 2)
        #expect(session.prompts[1].contains("delivery"))
    }

    @Test
    func realOnDeviceModelClassifiesWaitlistSuccess() async throws {
        let result = try await SMSIncomingClassificationService().classify(
            "【12306】候补订单已兑现成功，EH87720208，9月30日G117次10车2C、2F，北京南站（09:20开）至上海虹桥站，检票口9A、9B。请查收差价38.0元。"
        )

        #expect(result.source == .model)
        #expect(result.category == .trainWaitlistSuccess)
        #expect(result.details.departureStation?.contains("北京南") == true)
        #expect(result.details.arrivalStation?.contains("上海虹桥") == true)
    }

    @Test
    func emptyInputIsRejected() async {
        let service = SMSIncomingClassificationService(availabilityProvider: { _ in .available }, sessionFactory: { _ in fatalError("not called") })
        do {
            _ = try await service.classify("   ")
            #expect(Bool(false))
        } catch let error as SMSIncomingClassificationServiceError {
            #expect(error == .emptyInput)
        } catch {
            #expect(Bool(false))
        }
    }
}
