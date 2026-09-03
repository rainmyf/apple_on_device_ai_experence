import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

struct SMSEvalFixtureEntity: Codable, Equatable, Sendable {
    let label: String
    let start: Int
    let end: Int
    let text: String
}

struct SMSEvalFixtureRow: Codable, Equatable, Sendable {
    let msgID: Int
    let text: String
    let domain: String
    let entities: [SMSEvalFixtureEntity]

    enum CodingKeys: String, CodingKey {
        case msgID = "msg_id"
        case text
        case domain
        case entities
    }
}

enum SMSEvalFixtureError: Error, Equatable, CustomStringConvertible {
    case malformedRow(line: Int)
    case duplicateMessageID(Int)
    case invalidFilter(String)

    var description: String {
        switch self {
        case .malformedRow(let line): "malformed fixture row at line \(line)"
        case .duplicateMessageID(let id): "duplicate msg_id \(id)"
        case .invalidFilter(let value): "invalid evaluation filter \(value)"
        }
    }
}

enum SMSEvalFixtureLoader {
    static func load(url: URL) throws -> [SMSEvalFixtureRow] {
        try parse(data: Data(contentsOf: url))
    }

    static func parse(data: Data) throws -> [SMSEvalFixtureRow] {
        let content = String(decoding: data, as: UTF8.self)
        var rows: [SMSEvalFixtureRow] = []
        var seenIDs = Set<Int>()
        let decoder = JSONDecoder()

        for (offset, line) in content.split(whereSeparator: \.isNewline).enumerated() {
            let lineNumber = offset + 1
            guard let lineData = line.data(using: .utf8),
                  let row = try? decoder.decode(SMSEvalFixtureRow.self, from: lineData),
                  isValid(row)
            else { throw SMSEvalFixtureError.malformedRow(line: lineNumber) }
            guard seenIDs.insert(row.msgID).inserted else {
                throw SMSEvalFixtureError.duplicateMessageID(row.msgID)
            }
            rows.append(row)
        }

        return rows.sorted {
            if $0.domain != $1.domain { return $0.domain < $1.domain }
            return $0.msgID < $1.msgID
        }
    }

    private static func isValid(_ row: SMSEvalFixtureRow) -> Bool {
        guard row.msgID >= 0, !row.text.isEmpty, !row.domain.isEmpty else { return false }
        let sourceUnits = Array(row.text.utf16)
        return row.entities.allSatisfy { entity in
            guard !entity.label.isEmpty, !entity.text.isEmpty,
                  entity.start >= 0, entity.start < entity.end,
                  entity.end <= sourceUnits.count
            else { return false }
            let expected = Array(sourceUnits[entity.start..<entity.end])
            return expected == Array(entity.text.utf16)
        }
    }
}

struct SMSEvalSelection: Sendable {
    let domain: String?
    let messageIDs: Set<Int>?

    init(environment: [String: String]) throws {
        let domainValue = environment["SMS_EVAL_DOMAIN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        domain = domainValue?.isEmpty == true ? nil : domainValue

        guard let idsValue = environment["SMS_EVAL_IDS"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !idsValue.isEmpty
        else {
            messageIDs = nil
            return
        }

        var ids = Set<Int>()
        for token in idsValue.split(separator: ",") {
            guard let id = Int(token.trimmingCharacters(in: .whitespacesAndNewlines)), id >= 0 else {
                throw SMSEvalFixtureError.invalidFilter(String(idsValue))
            }
            ids.insert(id)
        }
        guard !ids.isEmpty else {
            throw SMSEvalFixtureError.invalidFilter(String(idsValue))
        }
        messageIDs = ids
    }

    func apply(to rows: [SMSEvalFixtureRow]) throws -> [SMSEvalFixtureRow] {
        rows.filter { row in
            (domain == nil || row.domain == domain) &&
                (messageIDs == nil || messageIDs!.contains(row.msgID))
        }.sorted {
            if $0.domain != $1.domain { return $0.domain < $1.domain }
            return $0.msgID < $1.msgID
        }
    }
}

enum SMSEvalPredictionStatus: String, Codable, Sendable {
    case ok
    case error
    case unavailable
}

struct SMSEvalPredictionEntity: Codable, Equatable, Sendable {
    let label: String
    let start: Int
    let end: Int
}

struct SMSEvalPredictionRecord: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let msgID: Int
    let expectedDomain: String
    let status: SMSEvalPredictionStatus
    let predictedDomain: String?
    let entities: [SMSEvalPredictionEntity]
    let latencyMilliseconds: Int
    let errorCategory: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case msgID = "msg_id"
        case expectedDomain = "expected_domain"
        case status
        case predictedDomain = "predicted_domain"
        case entities
        case latencyMilliseconds = "latency_ms"
        case errorCategory = "error_category"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(msgID, forKey: .msgID)
        try container.encode(expectedDomain, forKey: .expectedDomain)
        try container.encode(status, forKey: .status)
        try container.encode(predictedDomain, forKey: .predictedDomain)
        try container.encode(entities, forKey: .entities)
        try container.encode(latencyMilliseconds, forKey: .latencyMilliseconds)
        try container.encode(errorCategory, forKey: .errorCategory)
    }
}

enum SMSEvalPredictionEncoder {
    static func encode(_ record: SMSEvalPredictionRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        return try encoder.encode(record)
    }
}

struct SMSDeviceEvaluationTests {
    @Test func loaderParsesJSONLRowsAndEntityGold() throws {
        let data = Data(#"{"msg_id":2,"text":"短信","domain":"delivery","entities":[{"label":"org","start":0,"end":2,"text":"短信"}]}"#.utf8)

        let rows = try SMSEvalFixtureLoader.parse(data: data)

        #expect(rows == [
            SMSEvalFixtureRow(
                msgID: 2,
                text: "短信",
                domain: "delivery",
                entities: [SMSEvalFixtureEntity(label: "org", start: 0, end: 2, text: "短信")]
            )
        ])
    }

    @Test func loaderRejectsMalformedJSONLRows() {
        #expect(throws: SMSEvalFixtureError.self) {
            try SMSEvalFixtureLoader.parse(data: Data(#"{"msg_id":"bad","text":"短信","domain":"delivery","entities":[]}"#.utf8))
        }
    }

    @Test func loaderRejectsDuplicateMessageIDs() {
        let data = Data([
            #"{"msg_id":1,"text":"甲","domain":"a","entities":[]}"#,
            #"{"msg_id":1,"text":"乙","domain":"b","entities":[]}"#,
        ].joined(separator: "\n").utf8)

        #expect(throws: SMSEvalFixtureError.self) {
            try SMSEvalFixtureLoader.parse(data: data)
        }
    }

    @Test func selectionUsesStableDomainThenMessageIDOrder() throws {
        let rows = [
            SMSEvalFixtureRow(msgID: 9, text: "9", domain: "b", entities: []),
            SMSEvalFixtureRow(msgID: 2, text: "2", domain: "a", entities: []),
            SMSEvalFixtureRow(msgID: 1, text: "1", domain: "a", entities: []),
        ]

        let selected = try SMSEvalSelection(environment: [:]).apply(to: rows)

        #expect(selected.map { "\($0.domain):\($0.msgID)" } == ["a:1", "a:2", "b:9"])
    }

    @Test func selectionAppliesExactDomainFilter() throws {
        let rows = [
            SMSEvalFixtureRow(msgID: 1, text: "1", domain: "a", entities: []),
            SMSEvalFixtureRow(msgID: 2, text: "2", domain: "b", entities: []),
        ]

        let selected = try SMSEvalSelection(environment: ["SMS_EVAL_DOMAIN": "b"]).apply(to: rows)

        #expect(selected.map(\.msgID) == [2])
    }

    @Test func selectionAppliesCommaSeparatedIDResumeFilter() throws {
        let rows = [
            SMSEvalFixtureRow(msgID: 1, text: "1", domain: "a", entities: []),
            SMSEvalFixtureRow(msgID: 2, text: "2", domain: "a", entities: []),
            SMSEvalFixtureRow(msgID: 3, text: "3", domain: "b", entities: []),
        ]

        let selected = try SMSEvalSelection(environment: ["SMS_EVAL_IDS": "3, 1"]).apply(to: rows)

        #expect(selected.map { "\($0.domain):\($0.msgID)" } == ["a:1", "b:3"])
    }

    @Test func predictionEncodingIsCompactAndContainsRequiredFields() throws {
        let record = SMSEvalPredictionRecord(
            schemaVersion: 1,
            msgID: 17,
            expectedDomain: "delivery",
            status: .ok,
            predictedDomain: "delivery",
            entities: [SMSEvalPredictionEntity(label: "org", start: 1, end: 3)],
            latencyMilliseconds: 12,
            errorCategory: nil
        )

        let data = try SMSEvalPredictionEncoder.encode(record)
        let json = String(decoding: data, as: UTF8.self)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(!json.contains("\n"))
        #expect(object.keys.sorted() == ["entities", "error_category", "expected_domain", "latency_ms", "msg_id", "predicted_domain", "schema_version", "status"])
        #expect(json.contains("\"error_category\":null"))
    }

    @Test func predictionJSONNeverContainsSourceOrEntityTextFields() throws {
        let record = SMSEvalPredictionRecord(
            schemaVersion: 1,
            msgID: 17,
            expectedDomain: "delivery",
            status: .ok,
            predictedDomain: "delivery",
            entities: [SMSEvalPredictionEntity(label: "org", start: 1, end: 3)],
            latencyMilliseconds: 12,
            errorCategory: nil
        )

        let json = String(decoding: try SMSEvalPredictionEncoder.encode(record), as: UTF8.self)

        #expect(!json.contains("text"))
        #expect(!json.contains("短信"))
        #expect(!json.contains("entity_text"))
    }
}

#if !targetEnvironment(simulator)
struct SMSDevicePhysicalEvaluationTests {
    @Test @MainActor
    func evaluateSelectedSMSRowsSeriallyOnPhysicalDevice() async throws {
        let bundle = Bundle(for: SMSEvalBundleMarker.self)
        let fixtureURL = try #require(bundle.url(forResource: "sms_device_eval_30", withExtension: "jsonl"))
        let rows = try SMSEvalFixtureLoader.load(url: fixtureURL)
        let selected = try SMSEvalSelection(environment: ProcessInfo.processInfo.environment).apply(to: rows)
        try await SMSDeviceEvaluator().evaluate(selected)
    }
}
#endif

private final class SMSEvalBundleMarker: NSObject {}

#if !targetEnvironment(simulator)
@MainActor
struct SMSDeviceEvaluator {
    func evaluate(_ rows: [SMSEvalFixtureRow]) async throws {
        let domains = Set(rows.map(\.domain)).sorted().joined(separator: ",")
        print("SMS_EVAL_START|rows=\(rows.count)|domains=\(domains)")
        let service = SMSClassificationService()
        let unavailable = service.availabilityStatus != .available

        for row in rows {
            let started = Date()
            if unavailable {
                try printRecord(SMSEvalPredictionRecord(
                    schemaVersion: 1,
                    msgID: row.msgID,
                    expectedDomain: row.domain,
                    status: .unavailable,
                    predictedDomain: nil,
                    entities: [],
                    latencyMilliseconds: elapsedMilliseconds(since: started),
                    errorCategory: "model_unavailable"
                ))
                continue
            }

            do {
                let generated = try await service.classify(row.text)
                let validated = SMSAnnotationValidator.validate(generated, source: row.text)
                try printRecord(SMSEvalPredictionRecord(
                    schemaVersion: 1,
                    msgID: row.msgID,
                    expectedDomain: row.domain,
                    status: .ok,
                    predictedDomain: validated.domain,
                    entities: validated.entities.map {
                        SMSEvalPredictionEntity(label: $0.label, start: $0.start, end: $0.end)
                    },
                    latencyMilliseconds: elapsedMilliseconds(since: started),
                    errorCategory: nil
                ))
            } catch {
                let category = errorCategory(for: error)
                let status: SMSEvalPredictionStatus = category == "model_unavailable" ? .unavailable : .error
                try printRecord(SMSEvalPredictionRecord(
                    schemaVersion: 1,
                    msgID: row.msgID,
                    expectedDomain: row.domain,
                    status: status,
                    predictedDomain: nil,
                    entities: [],
                    latencyMilliseconds: elapsedMilliseconds(since: started),
                    errorCategory: category
                ))
            }
        }
        print("SMS_EVAL_END|rows=\(rows.count)")
    }

    private func printRecord(_ record: SMSEvalPredictionRecord) throws {
        let json = String(decoding: try SMSEvalPredictionEncoder.encode(record), as: UTF8.self)
        print("SMS_EVAL_RESULT|\(json)")
    }

    private func elapsedMilliseconds(since started: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(started) * 1_000))
    }

    private func errorCategory(for error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        if case SMSClassificationServiceError.unavailable = error { return "model_unavailable" }
        return "classification_error"
    }
}
#endif
