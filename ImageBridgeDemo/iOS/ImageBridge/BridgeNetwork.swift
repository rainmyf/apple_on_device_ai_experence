import Foundation
import Network

struct Receiver: Sendable {
    let name: String
    let endpoint: NWEndpoint
}

// System intent cancellation can arrive outside the Swift task's cancellation path.
final class BridgeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var action: (@Sendable () -> Void)?
    func register(_ action: @escaping @Sendable () -> Void) {
        lock.lock(); self.action = action; let cancelNow = cancelled; lock.unlock()
        if cancelNow { action() }
    }
    func clear() { lock.lock(); action = nil; lock.unlock() }
    func cancel() {
        lock.lock(); cancelled = true; let action = action; lock.unlock(); action?()
    }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}

// Every callback and completion is serialized; cancellation also closes the native resource.
private final class NetworkOperation<Value>: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.rain.ImageBridge.operation")
    private var continuation: CheckedContinuation<Value, Error>?
    private var completed = false
    private var cancelled = false
    private var cancellation: BridgeCancellation?
    var cleanup: (() -> Void)?
    func run(seconds: Double, cancellation: BridgeCancellation? = nil, start: @escaping (NetworkOperation<Value>) -> Void) async throws -> Value {
        self.cancellation = cancellation
        cancellation?.register { self.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if self.cancelled { self.cancellation?.clear(); continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    self.queue.asyncAfter(deadline: .now() + seconds) {
                        self.finish(.failure(BridgeFailure.message("连接超时，请检查接收设备后重试。")))
                    }
                    start(self)
                }
            }
        } onCancel: { self.cancel() }
    }
    private func cancel() {
        queue.async { self.cancelled = true; self.finish(.failure(CancellationError())) }
    }
    func finish(_ result: Result<Value, Error>) {
        guard !completed, let continuation else { return }
        completed = true
        self.continuation = nil
        cleanup?()
        cleanup = nil
        cancellation?.clear()
        continuation.resume(with: result)
    }
}

// Accessed exclusively on the operation queue.
private final class BrowseResults: @unchecked Sendable {
    var values: Set<NWBrowser.Result> = []
    var settle: DispatchWorkItem?
    var receivers: [Receiver] {
        values.compactMap { result in
            guard case .service(let name, _, let domain, _) = result.endpoint else { return nil }
            return Receiver(name: "\(name) (\(domain))", endpoint: result.endpoint)
        }.sorted { $0.name < $1.name }
    }
}

enum BridgeNetwork {
    static func discover(serviceType: String = "_imgbridge._tcp", cancellation: BridgeCancellation? = nil) async throws -> [Receiver] {
        let operation = NetworkOperation<[Receiver]>()
        return try await operation.run(seconds: 6, cancellation: cancellation) { op in
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
            let results = BrowseResults()
            op.cleanup = { results.settle?.cancel(); browser.cancel() }
            browser.browseResultsChangedHandler = { current, _ in
                results.values = current
                results.settle?.cancel()
                guard !current.isEmpty else { return }
                let settle = DispatchWorkItem {
                    let receivers = results.receivers
                    if !receivers.isEmpty { op.finish(.success(receivers)) }
                }
                results.settle = settle
                op.queue.asyncAfter(deadline: .now() + .milliseconds(350), execute: settle)
            }
            browser.stateUpdateHandler = { state in
                if case .failed(let error) = state { op.finish(.failure(error)) }
                if case .waiting(let error) = state { op.finish(.failure(error)) }
            }
            browser.start(queue: op.queue)
            // Event-driven stabilization; no packet polling. Overall browse deadline is five seconds.
            op.queue.asyncAfter(deadline: .now() + 5) {
                let receivers = results.receivers
                if receivers.isEmpty {
                    op.finish(.failure(BridgeFailure.message("未找到设备，请打开接收端并检查局域网权限。")))
                } else { op.finish(.success(receivers)) }
            }
        }
    }

    // Load only after the preceding ACK. There is no whole-batch deadline.
    static func sendImages(count: Int, to receiver: Receiver,
                           cancellation: BridgeCancellation? = nil,
                           load: (Int) async throws -> Data,
                           onProgress: @escaping @Sendable (Int, Int, Int) -> Void = { _, _, _ in }) async throws {
        var session = try ImageBatchSession(count: count)
        let connection = NWConnection(to: receiver.endpoint, using: .tcp)
        defer { connection.cancel() }
        do {
            let connect = NetworkOperation<Void>()
            try await connect.run(seconds: 30, cancellation: cancellation) { op in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: op.finish(.success(()))
                    case .failed(let error): op.finish(.failure(error))
                    default: break
                    }
                }
                connection.start(queue: op.queue)
            }
            try await write(session.header, connection: connection, cancellation: cancellation)
            for index in 0..<count {
                try Task.checkCancellation()
                try cancellation?.check()
                cancellation?.register { connection.cancel() }
                let jpeg = try await withTaskCancellationHandler {
                    try await load(index)
                } onCancel: { connection.cancel() }
                try Task.checkCancellation()
                try cancellation?.check()
                let frame = try session.frame(jpeg)
                let imageOperation = NetworkOperation<UInt8>()
                // Reserve 15 seconds on the final frame for the receiver's bounded preview launch.
                let code = try await imageOperation.run(seconds: index == count - 1 ? 45 : 30, cancellation: cancellation) { op in
                    @Sendable func chunk(_ offset: Int) {
                        let end = min(offset + 256 * 1024, frame.count)
                        connection.send(content: frame.subdata(in: offset..<end), completion: .contentProcessed { error in
                            op.queue.async {
                                if let error { op.finish(.failure(error)); return }
                                onProgress(index, max(0, end - 4), jpeg.count)
                                if end < frame.count { chunk(end); return }
                                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, error in
                                    op.queue.async {
                                        if let error { op.finish(.failure(error)); return }
                                        guard let code = data?.first else {
                                            op.finish(.failure(BridgeFailure.message("接收端已断开。"))); return
                                        }
                                        op.finish(.success(code))
                                    }
                                }
                            }
                        })
                    }
                    chunk(0)
                }
                try session.acknowledge(code)
                onProgress(index + 1, 0, 0)
            }
        } catch {
            let cause = error is CancellationError ? "已取消" : error.localizedDescription
            throw BridgeFailure.message("接收端已确认保存 \(session.savedCount)/\(count) 张。\(cause)")
        }
    }

    private static func write(_ data: Data, connection: NWConnection, cancellation: BridgeCancellation?) async throws {
        let operation = NetworkOperation<Void>()
        try await operation.run(seconds: 30, cancellation: cancellation) { op in
            connection.send(content: data, completion: .contentProcessed { error in
                op.queue.async {
                    if let error { op.finish(.failure(error)) }
                    else { op.finish(.success(())) }
                }
            })
        }
    }

    static func send(_ jpeg: Data, to receiver: Receiver, maximumBytes: Int = BridgeFrame.maximumBytes, cancellation: BridgeCancellation? = nil,
                     onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws {
        let frame = try BridgeFrame.encode(jpeg, maximumBytes: maximumBytes)
        let operation = NetworkOperation<Void>()
        try await operation.run(seconds: 30, cancellation: cancellation) { op in
            let connection = NWConnection(to: receiver.endpoint, using: .tcp)
            op.cleanup = { connection.cancel() }
            @Sendable func sendChunk(_ offset: Int) {
                let end = min(offset + 256 * 1024, frame.count)
                connection.send(content: frame.subdata(in: offset..<end), completion: .contentProcessed { error in
                    if let error { op.finish(.failure(error)); return }
                    onProgress(max(0, end - 4), jpeg.count)
                    if end < frame.count { sendChunk(end); return }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, error in
                        if let error { op.finish(.failure(error)); return }
                        guard let code = data?.first else {
                            op.finish(.failure(BridgeFailure.message("接收端已断开，请重试。"))); return
                        }
                        if code == 0 { op.finish(.success(())) }
                        else { op.finish(.failure(BridgeFailure.message("接收失败，请重试。"))) }
                    }
                })
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: sendChunk(0)
                case .failed(let error): op.finish(.failure(error))
                default: break
                }
            }
            connection.start(queue: op.queue)
        }
    }
}
