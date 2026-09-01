import Foundation

struct SMSGeneratedResult: Codable, Equatable, Sendable {
    let domain: String
    let entities: [SMSGeneratedEntity]
}

struct SMSGeneratedEntity: Codable, Equatable, Sendable {
    let text: String?
    let label: String
    let occurrence: Int?

    init(text: String?, label: String, occurrence: Int? = 0) {
        self.text = text
        self.label = label
        self.occurrence = occurrence
    }
}

struct SMSAnnotationResult: Codable, Equatable, Sendable {
    let domain: String
    let entities: [SMSAnnotationEntity]

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    func jsonString() throws -> String {
        try String(decoding: jsonData(), as: UTF8.self)
    }
}

struct SMSAnnotationEntity: Codable, Equatable, Sendable {
    let text: String
    let label: String
    let start: Int
    let end: Int
}

struct SMSHighlightSegment: Equatable, Sendable {
    let text: String
    let label: String?

    var isHighlighted: Bool { label != nil }
}

enum SMSClassificationVocabulary {
    static let domains: Set<String> = [
        "electric_vehicle_charging",
        "electric_vehicle_charging/charging_complete_move",
        "traffic_police_attention",
        "traffic_police_attention/parking_violation_reminder",
        "traffic_police_attention/other_violation",
        "train_ticket",
        "train_ticket/standby_success",
        "train_ticket/train_delay",
        "train_ticket/train_cancel",
        "delivery",
        "delivery/pickup_self_code",
        "delivery/pickup_special_place",
        "delivery/instant_delivery",
        "plane_ticket",
        "plane_ticket/plane_cancel",
        "assessment_arrangement_notice",
        "assessment_arrangement_notice/assessment_attendance_confirmation",
        "assessment_arrangement_notice/assessment_invitation",
        "electricity_balance",
        "electricity_balance/electricity_low_balance",
        "electricity_balance/electricity_overdue",
        "electricity_balance/electricity_recharge_success",
        "mobile_account_balance",
        "mobile_account_balance/mobile_account_balance_low",
        "mobile_account_balance/mobile_account_balance_overdue",
        "mobile_account_balance/mobile_account_balance_suspended",
        "mobile_account_balance/mobile_account_balance_recharge_success",
        "repayment_information",
        "repayment_information/repayment_reminder",
        "repayment_information/overdue_reminder",
        "repayment_information/repayment_success",
        "repayment_information/repayment_failure",
        "ignored",
    ]

    // v7.24 common and domain-specific labels. A label's presence here means
    // it may be emitted when the SMS context supports it; mandatory lists are
    // intentionally not used as a parser constraint.
    static let entityLabels: Set<String> = [
        "money", "date", "time", "url", "loc", "org", "phone_number", "person_name",
        "overtime_duration", "overtime_fee", "car_moving_action", "charging_station",
        "police_org", "vehicle_number", "violation_reason", "parking_location",
        "verify_code", "business_type", "violation_date", "violation_time",
        "standby_order_id", "train_number", "departure_station", "arrival_station",
        "departure_date", "arrival_date", "departure_time", "arrival_time", "seat_info",
        "delay_info", "cancel_info", "order_id", "flight_number", "pickup_code",
        "pickup_location", "sponsoring_org", "assessment_type", "assessment_round",
        "position", "assessment_time", "reply_time", "reply_requirement", "account_number",
        "balance", "loan_account", "due_amount", "minimum_payment", "remaining_amount",
        "due_date", "payment_account",
    ]

    static let commonEntityLabels: Set<String> = [
        "money", "date", "time", "url", "loc", "org", "phone_number", "person_name",
    ]

    // Parent labels are the shared family base. Exact child entries add only
    // labels whose definitions are specific to that child.
    static let domainSpecificEntityLabels: [String: Set<String>] = [
        "electric_vehicle_charging": ["overtime_duration", "overtime_fee", "car_moving_action", "charging_station"],
        "traffic_police_attention": ["police_org", "vehicle_number", "violation_reason", "parking_location", "car_moving_action", "violation_date", "violation_time", "verify_code", "business_type"],
        "train_ticket": ["standby_order_id", "train_number", "departure_station", "arrival_station", "seat_info", "delay_info", "cancel_info"],
        "train_ticket/standby_success": ["departure_date", "arrival_date", "departure_time", "arrival_time"],
        "delivery": ["pickup_code", "pickup_location"],
        "plane_ticket": ["order_id", "flight_number", "departure_station", "arrival_station", "seat_info"],
        "plane_ticket/plane_cancel": ["cancel_info"],
        "assessment_arrangement_notice": ["sponsoring_org", "assessment_type", "assessment_round", "position", "assessment_time", "reply_time", "reply_requirement"],
        "electricity_balance": ["account_number", "balance"],
        "mobile_account_balance": ["account_number", "balance"],
        "repayment_information": ["loan_account", "due_amount", "minimum_payment", "remaining_amount", "due_date", "payment_account"],
    ]

    static func allowedEntityLabels(for domain: String) -> Set<String> {
        guard domain != "ignored" else { return commonEntityLabels }
        let parent = domain.split(separator: "/", maxSplits: 1).first.map(String.init) ?? domain
        return commonEntityLabels
            .union(domainSpecificEntityLabels[parent] ?? [])
            .union(domainSpecificEntityLabels[domain] ?? [])
    }

    static func isValidEntityText(_ text: String, label: String) -> Bool {
        let pattern: String?
        switch label {
        case "train_number":
            pattern = "^[GCDZTSPKLX1-9]\\d{1,4}$"
        case "flight_number":
            pattern = "^[A-Za-z]{2,3}\\s?\\d{1,4}[A-Za-z]?$"
        case "loan_account", "payment_account", "account_number":
            pattern = "^\\d+$"
        case "balance":
            pattern = "^-?(?:\\d+|\\d{1,3}(?:,\\d{3})+)(?:\\.\\d+)?$"
        default:
            pattern = nil
        }
        guard let pattern else { return true }
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func canonicalEntityText(_ text: String, label: String) -> String {
        if text.range(of: "^[A-Za-z0-9 ]+$", options: .regularExpression) != nil {
            return text
        }
        let embeddedPattern: String?
        switch label {
        case "train_number": embeddedPattern = "[GCDZTSPKLX1-9]\\d{1,4}"
        case "flight_number": embeddedPattern = "[A-Za-z]{2,3}\\s?\\d{1,4}[A-Za-z]?"
        default: embeddedPattern = nil
        }
        guard let embeddedPattern,
              let range = text.range(of: embeddedPattern, options: .regularExpression)
        else { return text }
        return String(text[range])
    }
}

enum SMSAnnotationValidator {
    private struct Candidate {
        let entity: SMSAnnotationEntity
        let occurrence: Int
        let inputOrder: Int
    }

    static func validate(_ generated: SMSGeneratedResult, source: String) -> SMSAnnotationResult {
        let domain = SMSClassificationVocabulary.domains.contains(generated.domain)
            ? generated.domain
            : "ignored"

        var candidates: [Candidate] = []
        for (inputOrder, generatedEntity) in generated.entities.enumerated() {
            let labelIsAllowed = SMSClassificationVocabulary.allowedEntityLabels(for: domain)
                .contains(generatedEntity.label)
            guard labelIsAllowed,
                  let rawText = generatedEntity.text,
                  !rawText.isEmpty,
                  let occurrence = generatedEntity.occurrence,
                  occurrence >= 0
            else { continue }
            let text = SMSClassificationVocabulary.canonicalEntityText(rawText, label: generatedEntity.label)
            guard !text.isEmpty,
                  SMSClassificationVocabulary.isValidEntityText(text, label: generatedEntity.label),
                  let range = UTF16Resolver.resolve(text: text, occurrence: occurrence, in: source)
            else { continue }

            candidates.append(
                Candidate(
                    entity: SMSAnnotationEntity(
                        text: text,
                        label: generatedEntity.label,
                        start: range.start,
                        end: range.end
                    ),
                    occurrence: occurrence,
                    inputOrder: inputOrder
                )
            )
        }

        // Prefer the most informative span at the same start, then use stable
        // lexical tie breakers so model output order cannot change the result.
        let ordered = candidates.sorted {
            if $0.entity.start != $1.entity.start { return $0.entity.start < $1.entity.start }
            let firstLength = $0.entity.end - $0.entity.start
            let secondLength = $1.entity.end - $1.entity.start
            if firstLength != secondLength { return firstLength > secondLength }
            if $0.entity.end != $1.entity.end { return $0.entity.end > $1.entity.end }
            if $0.entity.label != $1.entity.label { return $0.entity.label < $1.entity.label }
            if $0.entity.text != $1.entity.text { return $0.entity.text < $1.entity.text }
            if $0.occurrence != $1.occurrence { return $0.occurrence < $1.occurrence }
            return $0.inputOrder < $1.inputOrder
        }

        var accepted: [SMSAnnotationEntity] = []
        for candidate in ordered where accepted.allSatisfy({
            candidate.entity.end <= $0.start || candidate.entity.start >= $0.end
        }) {
            accepted.append(candidate.entity)
        }

        accepted.sort { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        return SMSAnnotationResult(domain: domain, entities: accepted)
    }
}

private enum UTF16Resolver {
    struct Range {
        let start: Int
        let end: Int
    }

    static func resolve(text: String, occurrence: Int, in source: String) -> Range? {
        let sourceUnits = Array(source.utf16)
        let needle = Array(text.utf16)
        guard !needle.isEmpty, needle.count <= sourceUnits.count else { return nil }

        var matches: [Range] = []
        let lastStart = sourceUnits.count - needle.count
        for start in 0...lastStart {
            guard Array(sourceUnits[start..<(start + needle.count)]) == needle else { continue }
            guard isStringBoundary(start, in: source),
                  isStringBoundary(start + needle.count, in: source)
            else { continue }
            matches.append(Range(start: start, end: start + needle.count))
        }
        if matches.indices.contains(occurrence) { return matches[occurrence] }
        // The on-device model may occasionally count the first occurrence as
        // 1 even though the prompt requests zero-based indexing. Correct only
        // the unambiguous unique-text case; repeated text remains strict.
        if occurrence == 1, matches.count == 1 { return matches[0] }
        return nil
    }

    private static func isStringBoundary(_ offset: Int, in source: String) -> Bool {
        let index = String.Index(utf16Offset: offset, in: source)
        return index.utf16Offset(in: source) == offset
    }
}

enum SMSHighlightSegmenter {
    static func segments(source: String, entities: [SMSAnnotationEntity]) -> [SMSHighlightSegment] {
        let valid = entities
            .filter { $0.start >= 0 && $0.start < $0.end && $0.end <= source.utf16.count }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end > $1.end }
                return $0.label < $1.label
            }

        var nonOverlapping: [SMSAnnotationEntity] = []
        for entity in valid where isStringBoundary(entity.start, in: source) &&
                                  isStringBoundary(entity.end, in: source) &&
                                  nonOverlapping.allSatisfy({
            entity.end <= $0.start || entity.start >= $0.end
        }) {
            nonOverlapping.append(entity)
        }

        var result: [SMSHighlightSegment] = []
        var cursor = 0
        for entity in nonOverlapping {
            if cursor < entity.start {
                result.append(SMSHighlightSegment(text: substring(source, start: cursor, end: entity.start), label: nil))
            }
            // Render the source slice, not model-provided text, so the UI can
            // never replace or normalize the original SMS while annotating it.
            result.append(
                SMSHighlightSegment(
                    text: substring(source, start: entity.start, end: entity.end),
                    label: entity.label
                )
            )
            cursor = entity.end
        }
        if cursor < source.utf16.count {
            result.append(SMSHighlightSegment(text: substring(source, start: cursor, end: source.utf16.count), label: nil))
        }
        return result
    }

    private static func substring(_ source: String, start: Int, end: Int) -> String {
        let lower = String.Index(utf16Offset: start, in: source)
        let upper = String.Index(utf16Offset: end, in: source)
        return String(source[lower..<upper])
    }

    private static func isStringBoundary(_ offset: Int, in source: String) -> Bool {
        let index = String.Index(utf16Offset: offset, in: source)
        return index.utf16Offset(in: source) == offset
    }
}
