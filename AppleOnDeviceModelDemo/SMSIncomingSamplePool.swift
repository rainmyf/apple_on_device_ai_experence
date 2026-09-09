import Foundation

struct SMSIncomingSample: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let category: SMSIncomingCategory
    let text: String
}

enum SMSIncomingSamplePoolError: LocalizedError, Equatable, Sendable {
    case emptyPool
    case emptyCategory(SMSIncomingCategory)
    case resourceMissing
    case malformedResource

    var errorDescription: String? {
        switch self {
        case .emptyPool: "短信样本池为空。"
        case .emptyCategory(let category): "没有 \(category.rawValue) 短信样本。"
        case .resourceMissing: "找不到内置短信样本。"
        case .malformedResource: "内置短信样本格式无效。"
        }
    }
}

struct SMSIncomingSamplePool: Sendable {
    let samples: [SMSIncomingSample]

    init(samples: [SMSIncomingSample]) throws {
        let normalized = samples.filter { !$0.id.isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !normalized.isEmpty else { throw SMSIncomingSamplePoolError.emptyPool }
        self.samples = normalized
    }

    init(jsonl: String) throws {
        let decoder = JSONDecoder()
        let lines = jsonl.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        do {
            try self.init(samples: lines.map { try decoder.decode(SMSIncomingSample.self, from: Data($0.utf8)) })
        } catch is SMSIncomingSamplePoolError {
            throw SMSIncomingSamplePoolError.emptyPool
        } catch {
            throw SMSIncomingSamplePoolError.malformedResource
        }
    }

    static func bundled(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "sms_incoming_samples", withExtension: "jsonl") else {
            throw SMSIncomingSamplePoolError.resourceMissing
        }
        return try Self(jsonl: String(contentsOf: url, encoding: .utf8))
    }

    func count(for category: SMSIncomingCategory) -> Int {
        samples.count { $0.category == category }
    }

    func randomSample(for category: SMSIncomingCategory? = nil) throws -> SMSIncomingSample {
        let candidates = category.map { requested in samples.filter { $0.category == requested } } ?? samples
        guard let sample = candidates.randomElement() else {
            if let category { throw SMSIncomingSamplePoolError.emptyCategory(category) }
            throw SMSIncomingSamplePoolError.emptyPool
        }
        return sample
    }
}
