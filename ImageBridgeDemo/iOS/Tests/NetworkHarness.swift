import Foundation
import Network

// macOS diagnostic harness compiles the EXACT production discovery/transfer sources.
// Success here is sender protocol evidence, never iPhone or Shortcuts execution evidence.
@main struct NetworkHarness {
    static func main() async throws {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--batch-local-test") {
            let port = UInt16(args[flag + 1])!
            let expected = args[flag + 2]
            let receiver = Receiver(name: "local test", endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
            var loaded = 0
            let relay = BridgeCancellation()
            let canceller = Task {
                if expected == "已取消" {
                    try await Task.sleep(nanoseconds: 400_000_000)
                    relay.cancel()
                }
            }
            defer { canceller.cancel() }
            do {
                try await BridgeNetwork.sendImages(count: 3, to: receiver, cancellation: relay, load: { index in
                    loaded += 1
                    return Data(repeating: UInt8(index + 1), count: 300_000 + index)
                })
                precondition(expected == "success")
            } catch {
                precondition(error.localizedDescription.contains(expected), error.localizedDescription)
            }
            print("LOADED \(loaded)")
            return
        }
        if args.contains("--cancel-test") {
            let clock = ContinuousClock()
            let start = clock.now
            let task = Task { try await BridgeNetwork.discover() }
            try await Task.sleep(nanoseconds: 100_000_000)
            task.cancel()
            do { _ = try await task.value; fatalError("cancelled discovery returned success") }
            catch is CancellationError {
                precondition(start.duration(to: clock.now) < .seconds(2))
                print("PASS: discovery cancellation closes browser and resumes promptly")
            }
            return
        }
        if args.contains("--relay-cancel-test") {
            for cancelBeforeStart in [false, true] {
                let relay = BridgeCancellation()
                if cancelBeforeStart { relay.cancel() }
                let task = Task { try await BridgeNetwork.discover(cancellation: relay) }
                if !cancelBeforeStart {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    relay.cancel()
                }
                do { _ = try await task.value; fatalError("relay cancellation returned success") }
                catch is CancellationError {}
            }
            print("PASS: system cancellation relay before and during discovery")
            return
        }
        let clock = ContinuousClock()
        let started = clock.now
        let receivers = try await BridgeNetwork.discover()
        print("DISCOVERY_DURATION \(started.duration(to: clock.now))")
        print("DISCOVERED \(receivers.map(\.name))")
        guard receivers.count == 1 else { throw BridgeFailure.message("Harness requires exactly one receiver; no automatic selection from multiple.") }
        if args.count == 2 {
            let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            try await BridgeNetwork.sendImages(count: 1, to: receivers[0], load: { _ in data })
            print("ACK_SUCCESS \(data.count) bytes")
        }
    }
}
