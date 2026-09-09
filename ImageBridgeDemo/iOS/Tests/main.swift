import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
let frame = try BridgeFrame.encode(Data([0xFF, 0xD8, 0xFF]))
check(Array(frame.prefix(4)) == [3,0,0,0], "little endian header")
check(Array(frame.dropFirst(4)) == [0xFF,0xD8,0xFF], "payload unchanged")
for size in [0, 20 * 1024 * 1024 + 1] {
    do { _ = try BridgeFrame.encode(Data(count: size)); fatalError("invalid length accepted") } catch {}
}
let maximumFrame = try BridgeFrame.encode(Data(count: 20 * 1024 * 1024))
check(maximumFrame.count == 20 * 1024 * 1024 + 4, "maximum length")
print("PASS: LE framing, payload preservation, empty/oversized rejection, maximum boundary")
let original = "  中文 📱🙂\n第二行\r\n\n尾部  "
let message = try MessagePayload.encode(original)
let messageFrame = try BridgeFrame.encode(message, maximumBytes: MessagePayload.maximumBytes)
check(String(data: messageFrame.dropFirst(4), encoding: .utf8) == original, "original Unicode whitespace and newlines preserved")
check(messageFrame[0] == UInt8(message.count), "UTF8 byte length header")
for invalid in ["", String(repeating: "a", count: 65537), String(repeating: "🙂", count: 16385)] {
    do { _ = try MessagePayload.encode(invalid); fatalError("invalid message accepted") } catch {}
}
let boundary = try MessagePayload.encode(String(repeating: "🙂", count: 16384))
check(boundary.count == 65536, "UTF8 maximum boundary")
let boundaryFrame = try BridgeFrame.encode(boundary, maximumBytes: MessagePayload.maximumBytes)
check(Array(boundaryFrame.prefix(4)) == [0,0,1,0], "65536 LE header")
let whitespace = try MessagePayload.encode(" ")
check(whitespace.count == 1, "whitespace is valid content")
print("PASS: original UTF8, whitespace/newline preservation, message boundaries and framing")
func rejected(_ body: () throws -> Void) {
    do { try body(); fatalError("invalid operation accepted") } catch {}
}
for count in [0, -1, 21, Int.max] { rejected { _ = try ImageBatchSession(count: count) } }
var batch = try ImageBatchSession(count: 2)
check(Array(batch.header) == [73,66,65,84,2,0,0,0], "IBAT count")
rejected { try batch.acknowledge(0) }
_ = try batch.frame(Data([1]))
rejected { _ = try batch.frame(Data([2])) }
rejected { try batch.acknowledge(2) }
check(batch.savedCount == 0, "early ACK2 cannot count saved")
try batch.acknowledge(0)
_ = try batch.frame(Data([2,3]))
rejected { try batch.acknowledge(2) }
check(batch.savedCount == 2, "final preview failure records all saved")
rejected { _ = try batch.frame(Data([3])) }
var total = try ImageBatchSession(count: 6)
for _ in 0..<5 { _ = try total.frame(Data(count: BridgeFrame.maximumBytes)); try total.acknowledge(0) }
check(total.totalBytes == ImageBatchSession.maximumTotalBytes, "100 MiB accepted")
rejected { _ = try total.frame(Data([1])) }
check(total.savedCount == 5, "total rejection preserves confirmed count")
var invalid = try ImageBatchSession(count: 1)
rejected { _ = try invalid.frame(Data()) }
rejected { _ = try invalid.frame(Data(count: BridgeFrame.maximumBytes + 1)) }
_ = try invalid.frame(Data([1]))
for code: UInt8 in [1,3,255] { rejected { try invalid.acknowledge(code) }; check(invalid.savedCount == 0, "reject cannot confirm") }
try invalid.acknowledge(0)
check(invalid.savedCount == 1, "ACK0 final success")
print("PASS: production batch count, total/image bounds, sequential ACK, premature/final ACK2, partial counts")
