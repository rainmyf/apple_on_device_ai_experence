import Foundation

enum SMSIncomingSource: String, Codable, Hashable, Sendable {
    case model
    case fallback
}

/// The stable, language-neutral categories used by the SMS App Intent.
enum SMSIncomingCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case delivery
    case bankRepayment = "bank_repayment"
    case trainWaitlistSuccess = "train_waitlist_success"
    case weatherAlert = "weather_alert"
    case ordinary
}

struct SMSIncomingDetails: Codable, Equatable, Hashable, Sendable {
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

    init(
        pickupCode: String? = nil,
        pickupLocation: String? = nil,
        bankName: String? = nil,
        amountDue: String? = nil,
        dueDate: String? = nil,
        departureStation: String? = nil,
        arrivalStation: String? = nil,
        departureDateTime: String? = nil,
        seatInfo: String? = nil,
        weatherSummary: String? = nil,
        ordinarySummary: String? = nil
    ) {
        self.pickupCode = pickupCode
        self.pickupLocation = pickupLocation
        self.bankName = bankName
        self.amountDue = amountDue
        self.dueDate = dueDate
        self.departureStation = departureStation
        self.arrivalStation = arrivalStation
        self.departureDateTime = departureDateTime
        self.seatInfo = seatInfo
        self.weatherSummary = weatherSummary
        self.ordinarySummary = ordinarySummary
    }
}

struct SMSIncomingClassification: Codable, Equatable, Sendable {
    let category: SMSIncomingCategory
    let details: SMSIncomingDetails
    let source: SMSIncomingSource
    let fallbackReason: String?

    init(
        category: SMSIncomingCategory,
        details: SMSIncomingDetails = SMSIncomingDetails(),
        source: SMSIncomingSource,
        fallbackReason: String? = nil
    ) {
        self.category = category
        self.details = details
        self.source = source
        self.fallbackReason = fallbackReason
    }

    var summary: String {
        switch category {
        case .delivery:
            return [details.pickupCode.map { "取件码：\($0)" }, details.pickupLocation.map { "取件地点：\($0)" }]
                .compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "收到一条短信"
        case .bankRepayment:
            return [details.bankName, details.amountDue.map { "应还：\($0)" }, details.dueDate.map { "最后还款：\($0)" }]
                .compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "收到一条短信"
        case .trainWaitlistSuccess:
            let route: String? = if let departure = details.departureStation, let arrival = details.arrivalStation { "\(departure)→\(arrival)" } else { nil }
            return [route, details.departureDateTime, details.seatInfo.map { "座位：\($0)" }]
                .compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "收到一条短信"
        case .weatherAlert:
            return details.weatherSummary?.nonEmpty ?? "收到一条短信"
        case .ordinary:
            return details.ordinarySummary?.nonEmpty ?? "收到一条短信"
        }
    }
}

enum SMSIncomingPresentation {
    static let safeFallbackSummary = "收到一条短信"

    static func from(
        rawCategory: String?,
        details: SMSIncomingDetails = SMSIncomingDetails(),
        source: SMSIncomingSource,
        fallbackReason: String? = nil
    ) -> SMSIncomingClassification {
        let trimmed = rawCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let category = SMSIncomingCategory(rawValue: trimmed) else {
            return SMSIncomingClassification(
                category: .ordinary,
                details: SMSIncomingDetails(ordinarySummary: safeFallbackSummary),
                source: .fallback,
                fallbackReason: fallbackReason ?? "invalidCategory"
            )
        }
        return normalized(SMSIncomingClassification(category: category, details: details, source: source, fallbackReason: fallbackReason))
    }

    static func normalized(_ value: SMSIncomingClassification) -> SMSIncomingClassification {
        SMSIncomingClassification(category: value.category, details: normalizedDetails(value.details, for: value.category), source: value.source, fallbackReason: value.fallbackReason)
    }

    private static func normalizedDetails(_ details: SMSIncomingDetails, for category: SMSIncomingCategory) -> SMSIncomingDetails {
        switch category {
        case .delivery:
            return SMSIncomingDetails(pickupCode: clean(details.pickupCode), pickupLocation: clean(details.pickupLocation))
        case .bankRepayment:
            return SMSIncomingDetails(bankName: clean(details.bankName), amountDue: clean(details.amountDue), dueDate: clean(details.dueDate))
        case .trainWaitlistSuccess:
            return SMSIncomingDetails(departureStation: clean(details.departureStation), arrivalStation: clean(details.arrivalStation), departureDateTime: clean(details.departureDateTime), seatInfo: clean(details.seatInfo))
        case .weatherAlert:
            return SMSIncomingDetails(weatherSummary: clean(details.weatherSummary))
        case .ordinary:
            return SMSIncomingDetails(ordinarySummary: clean(details.ordinarySummary))
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
