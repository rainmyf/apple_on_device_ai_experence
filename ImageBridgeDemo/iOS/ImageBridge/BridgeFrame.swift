import Foundation

enum BridgeFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

enum BridgeFrame {
    static let maximumBytes = 20 * 1024 * 1024
    static func encode(_ jpeg: Data, maximumBytes: Int = maximumBytes) throws -> Data {
        guard !jpeg.isEmpty, jpeg.count <= maximumBytes else { throw BridgeFailure.message("JPEG must contain 1–20 MiB.") }
        let count = UInt32(jpeg.count)
        var frame = Data([UInt8(count & 255), UInt8((count >> 8) & 255), UInt8((count >> 16) & 255), UInt8((count >> 24) & 255)])
        frame.append(jpeg)
        return frame
    }
}


enum MessagePayload {
    static let maximumBytes = 65_536
    static func encode(_ text: String) throws -> Data {
        let data = Data(text.utf8)
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw BridgeFailure.message("消息需包含 1 至 65536 字节的文字。")
        }
        return data
    }
}

// The same state machine validates the production sender and protocol tests.
struct ImageBatchSession {
    static let maximumCount = 20
    static let maximumTotalBytes = 100 * 1024 * 1024
    let count: Int
    private(set) var savedCount = 0
    private(set) var totalBytes = 0
    private var awaitingACK = false
    init(count: Int) throws {
        guard (1...Self.maximumCount).contains(count) else {
            throw BridgeFailure.message("每次请选择 1 至 20 张图片。")
        }
        self.count = count
    }
    var header: Data { Data([0x49, 0x42, 0x41, 0x54, UInt8(count), 0, 0, 0]) }
    mutating func frame(_ jpeg: Data) throws -> Data {
        guard !awaitingACK, savedCount < count else { throw BridgeFailure.message("图片确认顺序异常。") }
        guard jpeg.count <= Self.maximumTotalBytes - totalBytes else {
            throw BridgeFailure.message("本批图片总大小超过 100 MiB。")
        }
        let frame = try BridgeFrame.encode(jpeg)
        totalBytes += jpeg.count
        awaitingACK = true
        return frame
    }
    mutating func acknowledge(_ code: UInt8) throws {
        guard awaitingACK else { throw BridgeFailure.message("收到意外的图片确认。") }
        if code == 0 { savedCount += 1; awaitingACK = false; return }
        if code == 2 && savedCount == count - 1 {
            savedCount += 1
            awaitingACK = false
            throw BridgeFailure.message("全部图片已保存，但系统预览未打开；请在接收端重新打开。")
        }
        throw BridgeFailure.message(code == 1 ? "接收端无法保存图片。" : "接收端返回无效确认。")
    }
}
