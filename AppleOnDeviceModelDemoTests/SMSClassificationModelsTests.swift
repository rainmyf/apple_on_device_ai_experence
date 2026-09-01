import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

struct SMSClassificationModelsTests {
    @Test func acceptsEveryV724ParentAndSubdomainValue() {
        let domains = [
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

        for domain in domains {
            #expect(SMSAnnotationValidator.validate(
                SMSGeneratedResult(domain: domain, entities: []),
                source: ""
            ).domain == domain)
        }
    }

    @Test func rejectsRetiredPartialRepaymentSuccessDomain() {
        let result = SMSAnnotationValidator.validate(
            SMSGeneratedResult(domain: "repayment_information/partial_repayment_success", entities: []),
            source: ""
        )

        #expect(result.domain == "ignored")
    }

    @Test func acceptsV724DomainsAndEntityLabels() {
        let generated = SMSGeneratedResult(
            domain: "repayment_information",
            entities: [
                SMSGeneratedEntity(text: "建设银行", label: "org", occurrence: 0),
                SMSGeneratedEntity(text: "2750元", label: "due_amount", occurrence: 0),
                SMSGeneratedEntity(text: "3月28日", label: "due_date", occurrence: 0),
            ]
        )

        let result = SMSAnnotationValidator.validate(
            generated,
            source: "建设银行本期应还2750元，请于3月28日前还款。"
        )

        #expect(result.domain == "repayment_information")
        #expect(result.entities.map(\.label) == ["org", "due_amount", "due_date"])
    }

    @Test func nonIgnoredDomainsAllowCommonAndOnlyTheirParentSpecificLabels() {
        let cases: [(String, String, String)] = [
            ("delivery/pickup_self_code", "pickup_code", "123"),
            ("train_ticket", "train_number", "G123"),
            ("plane_ticket", "flight_number", "MU123"),
            ("traffic_police_attention", "police_org", "交管"),
            ("electric_vehicle_charging", "charging_station", "A站"),
            ("assessment_arrangement_notice", "sponsoring_org", "考试院"),
            ("electricity_balance", "account_number", "123456"),
            ("mobile_account_balance", "balance", "12.5"),
            ("repayment_information", "loan_account", "123456"),
        ]

        for (domain, legalLabel, text) in cases {
            let generated = SMSGeneratedResult(
                domain: domain,
                entities: [
                    SMSGeneratedEntity(text: text, label: legalLabel),
                    SMSGeneratedEntity(text: text, label: "loan_account"),
                ]
            )
            let result = SMSAnnotationValidator.validate(generated, source: text)

            #expect(result.entities.map(\.label) == [legalLabel])
        }
    }

    @Test func dropsDomainSpecificLabelsFromUnrelatedDomains() {
        let generated = SMSGeneratedResult(
            domain: "train_ticket",
            entities: [
                SMSGeneratedEntity(text: "100", label: "balance"),
                SMSGeneratedEntity(text: "123456", label: "loan_account"),
                SMSGeneratedEntity(text: "G123", label: "train_number"),
            ]
        )

        let result = SMSAnnotationValidator.validate(generated, source: "100 123456 G123")

        #expect(result.entities.map(\.label) == ["train_number"])
    }

    @Test func enforcesRound4ParentAndTrainChildLabelScopes() {
        let cases: [(domain: String, label: String, text: String, allowed: Bool)] = [
            ("traffic_police_attention", "verify_code", "123", true),
            ("traffic_police_attention", "business_type", "违停", true),
            ("delivery", "pickup_code", "123", true),
            ("delivery", "order_id", "123", false),
            ("train_ticket", "train_number", "G123", true),
            ("train_ticket", "order_id", "123", false),
            ("repayment_information", "loan_account", "123456", true),
            ("repayment_information", "account_number", "123456", false),
            ("plane_ticket", "order_id", "123", true),
            ("train_ticket", "departure_date", "3月28日", false),
            ("train_ticket", "arrival_date", "3月28日", false),
            ("train_ticket", "departure_time", "09时16分", false),
            ("train_ticket", "arrival_time", "10时20分", false),
            ("train_ticket/train_delay", "departure_date", "3月28日", false),
            ("train_ticket/train_cancel", "arrival_time", "10时20分", false),
            ("train_ticket/standby_success", "departure_date", "3月28日", true),
            ("train_ticket/standby_success", "arrival_date", "3月28日", true),
            ("train_ticket/standby_success", "departure_time", "09时16分", true),
            ("train_ticket/standby_success", "arrival_time", "10时20分", true),
        ]

        for item in cases {
            let result = SMSAnnotationValidator.validate(
                SMSGeneratedResult(
                    domain: item.domain,
                    entities: [SMSGeneratedEntity(text: item.text, label: item.label)]
                ),
                source: item.text
            )

            #expect(result.entities.isEmpty == !item.allowed, "unexpected \(item.domain)/\(item.label)")
        }
    }

    @Test func enforcesRound5PlaneBaseAndCancelLabelScopes() {
        let cases: [(domain: String, label: String, text: String, allowed: Bool)] = [
            ("plane_ticket", "order_id", "123", true),
            ("plane_ticket", "flight_number", "MU123", true),
            ("plane_ticket", "departure_station", "上海", true),
            ("plane_ticket", "arrival_station", "北京", true),
            ("plane_ticket", "seat_info", "12A", true),
            ("plane_ticket", "cancel_info", "取消", false),
            ("plane_ticket", "departure_date", "3月28日", false),
            ("plane_ticket", "arrival_date", "3月28日", false),
            ("plane_ticket", "departure_time", "09时16分", false),
            ("plane_ticket", "arrival_time", "10时20分", false),
            ("plane_ticket/plane_cancel", "cancel_info", "取消", true),
            ("plane_ticket/plane_cancel", "departure_date", "3月28日", false),
        ]

        for item in cases {
            let result = SMSAnnotationValidator.validate(
                SMSGeneratedResult(
                    domain: item.domain,
                    entities: [SMSGeneratedEntity(text: item.text, label: item.label)]
                ),
                source: item.text
            )

            #expect(result.entities.isEmpty == !item.allowed, "unexpected \(item.domain)/\(item.label)")
        }
    }

    @Test func enforcesTrainFlightAccountAndBalanceFormats() {
        let generated = SMSGeneratedResult(
            domain: "train_ticket",
            entities: [
                SMSGeneratedEntity(text: "G123", label: "train_number"),
                SMSGeneratedEntity(text: "A123", label: "train_number"),
                SMSGeneratedEntity(text: "G12345", label: "train_number"),
            ]
        )
        let train = SMSAnnotationValidator.validate(generated, source: "G123 A123 G12345")
        #expect(train.entities.map(\.text) == ["G123"])

        let flightGenerated = SMSGeneratedResult(
            domain: "plane_ticket",
            entities: [
                SMSGeneratedEntity(text: "MU123", label: "flight_number"),
                SMSGeneratedEntity(text: "CA 987A", label: "flight_number"),
                SMSGeneratedEntity(text: "M123", label: "flight_number"),
                SMSGeneratedEntity(text: "MU12345", label: "flight_number"),
            ]
        )
        let flight = SMSAnnotationValidator.validate(flightGenerated, source: "MU123 CA 987A M123 MU12345")
        #expect(flight.entities.map(\.text) == ["MU123", "CA 987A"])

        let accounts = SMSGeneratedResult(
            domain: "repayment_information",
            entities: [
                SMSGeneratedEntity(text: "001234", label: "loan_account"),
                SMSGeneratedEntity(text: "12A34", label: "loan_account"),
                SMSGeneratedEntity(text: "123456", label: "payment_account"),
                SMSGeneratedEntity(text: "+123", label: "account_number"),
            ]
        )
        let accountResult = SMSAnnotationValidator.validate(
            accounts,
            source: "001234 12A34 123456 +123"
        )
        #expect(accountResult.entities.map(\.text) == ["001234", "123456"])

        let balances = SMSGeneratedResult(
            domain: "mobile_account_balance",
            entities: [
                SMSGeneratedEntity(text: "12.5", label: "balance"),
                SMSGeneratedEntity(text: "-1,234.50", label: "balance"),
                SMSGeneratedEntity(text: "￥12", label: "balance"),
                SMSGeneratedEntity(text: "12元", label: "balance"),
                SMSGeneratedEntity(text: "1,23", label: "balance"),
            ]
        )
        let balanceResult = SMSAnnotationValidator.validate(
            balances,
            source: "12.5 -1,234.50 ￥12 12元 1,23"
        )
        #expect(balanceResult.entities.map(\.text) == ["12.5", "-1,234.50"])
    }

    @Test func normalizesInvalidDomainAndDropsInvalidLabels() {
        let generated = SMSGeneratedResult(
            domain: "not-a-v724-domain",
            entities: [
                SMSGeneratedEntity(text: "建设银行", label: "org", occurrence: 0),
                SMSGeneratedEntity(text: "建设银行", label: "made_up_label", occurrence: 0),
            ]
        )

        let result = SMSAnnotationValidator.validate(generated, source: "建设银行提醒")

        #expect(result.domain == "ignored")
        #expect(result.entities.map(\.label) == ["org"])
    }

    @Test func acceptsIgnoredOnlyWithCommonEntityLabels() {
        let generated = SMSGeneratedResult(
            domain: "ignored",
            entities: [
                SMSGeneratedEntity(text: "今天", label: "date", occurrence: 0),
                SMSGeneratedEntity(text: "建设银行", label: "org", occurrence: 0),
                SMSGeneratedEntity(text: "123", label: "pickup_code", occurrence: 0),
            ]
        )

        let result = SMSAnnotationValidator.validate(generated, source: "今天建设银行取件码123")

        #expect(result.domain == "ignored")
        #expect(result.entities.map(\.label) == ["date", "org"])
    }

    @Test func rejectsRetiredDomainValues() {
        for retired in ["NULL", "null", "auto_debit_reminder", "parking_violation_notification"] {
            let result = SMSAnnotationValidator.validate(
                SMSGeneratedResult(domain: retired, entities: []),
                source: ""
            )
            #expect(result.domain == "ignored")
        }
    }

    @Test func resolvesOffsetsUsingUTF16ForEmojiAndChineseText() {
        let source = "😀建设银行账户"
        let generated = SMSGeneratedResult(
            domain: "repayment_information",
            entities: [SMSGeneratedEntity(text: "建设银行", label: "org", occurrence: 0)]
        )

        let result = SMSAnnotationValidator.validate(generated, source: source)
        let entity = try! #require(result.entities.first)

        #expect(entity.start == 2)
        #expect(entity.end == 6)
        #expect(entity.text == "建设银行")
    }

    @Test func resolvesRepeatedOccurrencesAndDropsTheOutOfBoundsOccurrence() {
        let source = "取件码123，取件码123"
        let generated = SMSGeneratedResult(
            domain: "delivery/pickup_self_code",
            entities: [
                SMSGeneratedEntity(text: "123", label: "pickup_code", occurrence: 0),
                SMSGeneratedEntity(text: "123", label: "pickup_code", occurrence: 1),
                SMSGeneratedEntity(text: "123", label: "pickup_code", occurrence: 2),
            ]
        )

        let result = SMSAnnotationValidator.validate(generated, source: source)

        #expect(result.entities.map(\.start) == [3, 10])
        #expect(result.entities.map(\.end) == [6, 13])
        #expect(result.entities.allSatisfy { entity in
            let lower = String.Index(utf16Offset: entity.start, in: source)
            let upper = String.Index(utf16Offset: entity.end, in: source)
            return String(source[lower..<upper]) == entity.text
        })
    }

    @Test func dropsMissingOrEmptyEntityText() {
        let generated = SMSGeneratedResult(
            domain: "delivery",
            entities: [
                SMSGeneratedEntity(text: nil, label: "pickup_code", occurrence: 0),
                SMSGeneratedEntity(text: "", label: "pickup_location", occurrence: 0),
                SMSGeneratedEntity(text: "123", label: "pickup_code", occurrence: 0),
            ]
        )

        let result = SMSAnnotationValidator.validate(generated, source: "您的取件码123已送达")

        #expect(result.entities.count == 1)
        #expect(result.entities[0].text == "123")
    }

    @Test func dropsEntitiesWithoutAnExplicitOccurrence() {
        let generated = SMSGeneratedResult(
            domain: "delivery/pickup_self_code",
            entities: [
                SMSGeneratedEntity(text: "123", label: "pickup_code", occurrence: nil),
                SMSGeneratedEntity(text: "123", label: "pickup_code", occurrence: 0),
            ]
        )

        let result = SMSAnnotationValidator.validate(generated, source: "您的取件码123已送达")

        #expect(result.entities.map(\.text) == ["123"])
        #expect(result.entities.first?.start == 5)
    }

    @Test func dropsOutOfBoundsAndAbsentOccurrences() {
        let generated = SMSGeneratedResult(
            domain: "delivery",
            entities: [
                SMSGeneratedEntity(text: "123", label: "pickup_code", occurrence: 4),
                SMSGeneratedEntity(text: "不存在", label: "pickup_location", occurrence: 0),
            ]
        )

        let result = SMSAnnotationValidator.validate(generated, source: "您的取件码123已送达")

        #expect(result.entities.isEmpty)
    }

    @Test func uniqueEntityTextSurvivesAModelSuppliedOneBasedOccurrence() {
        let source = "【云端航空】航班ZX123将于9月10日14:35起飞"
        let generated = SMSGeneratedResult(
            domain: "plane_ticket",
            entities: [SMSGeneratedEntity(text: "ZX123", label: "flight_number", occurrence: 1)]
        )

        let result = SMSAnnotationValidator.validate(generated, source: source)

        #expect(result.entities.map(\.text) == ["ZX123"])
        #expect(result.entities.map(\.label) == ["flight_number"])
    }

    @Test func canonicalizesAFlightNumberWrappedInModelContext() {
        let source = "【云端航空】航班ZX123将于9月10日14:35起飞"
        let generated = SMSGeneratedResult(
            domain: "plane_ticket",
            entities: [SMSGeneratedEntity(text: "航班ZX123", label: "flight_number", occurrence: 1)]
        )

        let result = SMSAnnotationValidator.validate(generated, source: source)

        #expect(result.entities.map(\.text) == ["ZX123"])
        #expect(result.entities.map(\.label) == ["flight_number"])
    }

    @Test func selectsNonOverlappingEntitiesDeterministically() {
        let source = "建设银行"
        let generated = SMSGeneratedResult(
            domain: "repayment_information",
            entities: [
                SMSGeneratedEntity(text: "银行", label: "org", occurrence: 0),
                SMSGeneratedEntity(text: "建设银行", label: "org", occurrence: 0),
                SMSGeneratedEntity(text: "建设", label: "org", occurrence: 0),
            ]
        )

        let result = SMSAnnotationValidator.validate(generated, source: source)

        #expect(result.entities.map(\.text) == ["建设银行"])
        #expect(result.entities.map(\.start) == [0])
        #expect(result.entities.map(\.end) == [4])
    }

    @Test func producesUIIndependentSourceOrderHighlightSegments() {
        let source = "😀建设银行本期应还2750元"
        let entities = [
            SMSAnnotationEntity(text: "2750元", label: "due_amount", start: 10, end: 15),
            SMSAnnotationEntity(text: "建设银行", label: "org", start: 2, end: 6),
        ]

        let segments = SMSHighlightSegmenter.segments(source: source, entities: entities)

        #expect(segments.map(\.text) == ["😀", "建设银行", "本期应还", "2750元"])
        #expect(segments.map(\.label) == [nil, "org", nil, "due_amount"])
    }

    @Test func segmenterPrefersLongestOverlapKeepsAdjacentSpansAndPreservesEmoji() {
        let source = "😀建设银行账户"
        let entities = [
            SMSAnnotationEntity(text: "建设", label: "short", start: 2, end: 4),
            SMSAnnotationEntity(text: "建设银行", label: "org", start: 2, end: 6),
            SMSAnnotationEntity(text: "账户", label: "account", start: 6, end: 8),
        ]

        let segments = SMSHighlightSegmenter.segments(source: source, entities: entities)

        #expect(segments.map(\.text) == ["😀", "建设银行", "账户"])
        #expect(segments.map(\.label) == [nil, "org", "account"])
        #expect(segments.map(\.text).joined() == source)
    }

    @Test func highlightSegmentsAlwaysRenderTheOriginalSourceSlice() {
        let segments = SMSHighlightSegmenter.segments(
            source: "建设银行",
            entities: [SMSAnnotationEntity(text: "模型改写", label: "org", start: 0, end: 4)]
        )

        #expect(segments.map(\.text) == ["建设银行"])
        #expect(segments.first?.label == "org")
    }

    @Test func encodesAnnotationJSONWithJavaScriptOffsets() throws {
        let result = SMSAnnotationResult(
            domain: "repayment_information",
            entities: [SMSAnnotationEntity(text: "建设银行", label: "org", start: 2, end: 6)]
        )

        let json = try result.jsonString()
        #expect(json.contains("\"domain\":\"repayment_information\""))
        #expect(json.contains("\"text\":\"建设银行\""))
        #expect(json.contains("\"label\":\"org\""))
        #expect(json.contains("\"start\":2"))
        #expect(json.contains("\"end\":6"))
        #expect(!json.contains("occurrence"))
    }

    @Test func decodesEncodedAnnotationJSONBackToTheSameResult() throws {
        let result = SMSAnnotationResult(
            domain: "delivery/pickup_self_code",
            entities: [SMSAnnotationEntity(text: "取件码123", label: "pickup_code", start: 0, end: 6)]
        )

        let decoded = try JSONDecoder().decode(SMSAnnotationResult.self, from: result.jsonData())

        #expect(decoded == result)
    }
}
