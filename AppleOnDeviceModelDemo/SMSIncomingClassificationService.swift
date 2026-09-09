import Foundation
import FoundationModels

protocol SMSIncomingClassifying: Sendable {
    func classify(_ text: String) async throws -> SMSIncomingClassification
}

protocol SMSIncomingModelSessionServing: Sendable {
    func classifyCategory(for prompt: String) async throws -> SMSIncomingCategoryResult
    func extractDetails(for prompt: String) async throws -> SMSIncomingDetailsResult
}

typealias SMSIncomingSessionFactory = @Sendable (SystemLanguageModel) -> any SMSIncomingModelSessionServing

@available(iOS 26.0, *)
@Generable
struct SMSIncomingCategoryResult: Sendable {
    @Guide(description: "Exactly one stable category ID", .anyOf(SMSIncomingCategory.allCases.map(\.rawValue)))
    var category: String
}

@available(iOS 26.0, *)
@Generable
struct SMSIncomingDetailsResult: Sendable {
    var pickupCode: String?
    var pickupLocation: String?
    var bankName: String?
    var amountDue: String?
    var dueDate: String?
    var departureStation: String?
    var arrivalStation: String?
    var departureDateTime: String?
    var seatInfo: String?
    var weatherSummary: String?
    var ordinarySummary: String?
}

private final class SMSIncomingLanguageModelSessionAdapter: SMSIncomingModelSessionServing {
    private let session: LanguageModelSession

    init(model: SystemLanguageModel) { session = LanguageModelSession(model: model) }

    func classifyCategory(for prompt: String) async throws -> SMSIncomingCategoryResult {
        try await session.respond(to: prompt, generating: SMSIncomingCategoryResult.self).content
    }

    func extractDetails(for prompt: String) async throws -> SMSIncomingDetailsResult {
        try await session.respond(to: prompt, generating: SMSIncomingDetailsResult.self).content
    }
}

enum SMSIncomingClassificationServiceError: LocalizedError, Equatable, Sendable {
    case emptyInput
    case inputTooLong
    case unavailable(FoundationModelStatus)

    var errorDescription: String? {
        switch self {
        case .emptyInput: "请输入短信内容。"
        case .inputTooLong: "短信内容过长。"
        case .unavailable(let status): "端侧模型不可用：\(status.rawValue)。"
        }
    }
}

final class SMSIncomingClassificationService: SMSIncomingClassifying, Sendable {
    private let model: SystemLanguageModel
    private let availabilityProvider: @Sendable (SystemLanguageModel.Availability) -> FoundationModelStatus
    private let sessionFactory: SMSIncomingSessionFactory

    init(
        model: SystemLanguageModel = .default,
        availabilityProvider: @escaping @Sendable (SystemLanguageModel.Availability) -> FoundationModelStatus = { FoundationModelService.status(for: $0) },
        sessionFactory: @escaping SMSIncomingSessionFactory = { SMSIncomingLanguageModelSessionAdapter(model: $0) }
    ) {
        self.model = model
        self.availabilityProvider = availabilityProvider
        self.sessionFactory = sessionFactory
    }

    func classify(_ text: String) async throws -> SMSIncomingClassification {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw SMSIncomingClassificationServiceError.emptyInput }
        guard input.utf16.count <= 1_000 else { throw SMSIncomingClassificationServiceError.inputTooLong }

        let status = availabilityProvider(model.availability)
        guard status == .available else { throw SMSIncomingClassificationServiceError.unavailable(status) }

        let session = sessionFactory(model)
        let categoryResponse = try await session.classifyCategory(for: SMSIncomingClassificationPrompt.category(text: input))
        let category = SMSIncomingCategory(rawValue: categoryResponse.category.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .ordinary
        let detailsResponse = try await session.extractDetails(for: SMSIncomingClassificationPrompt.details(text: input, category: category))
        let details = SMSIncomingDetails(
            pickupCode: detailsResponse.pickupCode,
            pickupLocation: detailsResponse.pickupLocation,
            bankName: detailsResponse.bankName,
            amountDue: detailsResponse.amountDue,
            dueDate: detailsResponse.dueDate,
            departureStation: detailsResponse.departureStation,
            arrivalStation: detailsResponse.arrivalStation,
            departureDateTime: detailsResponse.departureDateTime,
            seatInfo: detailsResponse.seatInfo,
            weatherSummary: detailsResponse.weatherSummary,
            ordinarySummary: detailsResponse.ordinarySummary
        )
        return SMSIncomingPresentation.from(rawCategory: category.rawValue, details: details, source: .model)
    }
}

enum SMSIncomingClassificationPrompt {
    static func category(text: String) -> String {
        """
        Classify the following SMS, written in any language, into exactly one category ID. Classify by its semantic intent, never just because it contains dates, numbers, prices, refunds, or links. Return only structured data.

        Category definitions:
        - delivery: a parcel pickup or delivery notice, including a pickup code, parcel, courier locker, station, store, or pickup location.
        - bank_repayment: a bank or credit-card repayment/billing notice that asks for payment or states an amount due, repayment deadline, bill, or overdue risk. A number or a refund alone is not enough.
        - train_waitlist_success: a railway waitlist order has succeeded, fulfilled, or been issued, with a train, route, station, departure time, coach, or seat. Chinese phrases such as “候补订单已兑现成功”, “候补成功”, and “候补兑现” must be this category.
        - weather_alert: an official or safety-relevant extreme-weather warning, such as strong wind, heavy rain, storm, flood, snow, heat, or emergency weather instructions.
        - ordinary: every other SMS.

        Hard negative: a train waitlist-success SMS must be train_waitlist_success and must not be classified as bank_repayment merely because it mentions a fare difference, refund, price, date, or amount. bank_repayment requires an actual bank or credit-card repayment context.

        Categories: delivery, bank_repayment, train_waitlist_success, weather_alert, ordinary.\nSMS:\n\(text)
        """
    }

    static func details(text: String, category: SMSIncomingCategory) -> String {
        let fields: String
        switch category {
        case .delivery: fields = "pickupCode, pickupLocation"
        case .bankRepayment: fields = "bankName, amountDue, dueDate"
        case .trainWaitlistSuccess: fields = "departureStation, arrivalStation, departureDateTime, seatInfo"
        case .weatherAlert: fields = "weatherSummary"
        case .ordinary: fields = "ordinarySummary"
        }
        return """
        Extract only the fields \(fields) from this SMS. Preserve the source wording for factual values, use null for absent fields, and do not invent values. The category is already fixed to \(category.rawValue). For weatherSummary or ordinarySummary, write one concise Chinese sentence that conveys the key message; do not include URLs or promotional filler.\nSMS:\n\(text)
        """
    }
}
