import Foundation

struct SMSSample: Codable, Equatable, Sendable {
    let id: String
    let text: String
    let expectedDomain: String?

    init(id: String, text: String, expectedDomain: String? = nil) {
        self.id = id
        self.text = text
        self.expectedDomain = expectedDomain
    }
}

enum SMSJSONLParser {
    private struct RawSample: Decodable {
        let id: String?
        let text: String?
        let expectedDomain: String?
    }

    static func parse(_ data: Data) -> [SMSSample] {
        parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ jsonl: String) -> [SMSSample] {
        let decoder = JSONDecoder()
        return jsonl
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { offset, line in
                let lineNumber = offset + 1
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let data = trimmed.data(using: .utf8),
                      let raw = try? decoder.decode(RawSample.self, from: data),
                      let text = raw.text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }

                let id = raw.id?.trimmingCharacters(in: .whitespacesAndNewlines)
                let expectedDomain = raw.expectedDomain?.trimmingCharacters(in: .whitespacesAndNewlines)
                return SMSSample(
                    id: id.flatMap { $0.isEmpty ? nil : $0 } ?? "line-\(lineNumber)",
                    text: text,
                    expectedDomain: expectedDomain.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
    }
}

enum SMSRandomSamplePicker {
    static func next(
        from samples: [SMSSample],
        excluding previousSample: SMSSample?,
        randomIndex: Int? = nil
    ) -> SMSSample? {
        guard !samples.isEmpty else { return nil }

        var candidates = samples
        if samples.count > 1,
           let previousSample,
           let previousIndex = samples.firstIndex(of: previousSample) {
            candidates.remove(at: previousIndex)
        }

        let index: Int
        if let randomIndex {
            guard candidates.indices.contains(randomIndex) else { return nil }
            index = randomIndex
        } else {
            index = Int.random(in: candidates.indices)
        }
        return candidates[index]
    }
}

struct BundledSMSSampleStore {
    let bundle: Bundle
    let resourceName: String

    init(bundle: Bundle = .main, resourceName: String = "sms_samples") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    func load() -> [SMSSample] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "jsonl"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return SMSJSONLParser.parse(data)
    }

    static func load(bundle: Bundle = .main, resourceName: String = "sms_samples") -> [SMSSample] {
        BundledSMSSampleStore(bundle: bundle, resourceName: resourceName).load()
    }
}
