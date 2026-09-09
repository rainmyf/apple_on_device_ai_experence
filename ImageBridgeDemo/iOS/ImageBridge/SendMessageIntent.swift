import AppIntents
import SwiftUI

struct SendMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "分享消息给我的华为手机"
    static let description = IntentDescription("将原始文字发送到华为手机并弹窗显示。")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "消息") var text: String
    @Parameter(title: "接收设备") var receiver: String?
    static var parameterSummary: some ParameterSummary { Summary("分享\(\.$text)给我的华为手机") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let data = try MessagePayload.encode(text)
            await BridgeStatus.shared.set("正在查找设备…")
            let receivers = try await BridgeNetwork.discover(serviceType: "_msgbridge._tcp")
            try await Self.sendToAll(data, receivers: receivers)
            return .result(dialog: "已发送给所有发现的设备")
        } catch {
            await BridgeStatus.shared.fail(error)
            throw error
        }
    }

    static func sendToAll(_ data: Data, receivers: [Receiver]) async throws {
        guard !receivers.isEmpty else { throw BridgeFailure.message("未发现设备") }
        let failures = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            for receiver in receivers {
                group.addTask {
                    do {
                        try await BridgeNetwork.send(data, to: receiver, maximumBytes: MessagePayload.maximumBytes)
                        return nil
                    } catch { return "\(receiver.name)：\(error.localizedDescription)" }
                }
            }
            var failures: [String] = []
            for await failure in group { if let failure { failures.append(failure) } }
            return failures
        }
        try Task.checkCancellation()
        let summary = "已发送 \(receivers.count - failures.count)/\(receivers.count) 台"
        await BridgeStatus.shared.set(summary)
        if !failures.isEmpty { throw BridgeFailure.message(summary + "\n" + failures.joined(separator: "\n")) }
    }

    static func send(_ data: Data, to receiver: Receiver) async throws {
        try Task.checkCancellation()
        await BridgeStatus.shared.set("正在发送…")
        try await BridgeNetwork.send(data, to: receiver, maximumBytes: MessagePayload.maximumBytes)
        await BridgeStatus.shared.set("已发送", detail: "MESSAGEBRIDGE_SUCCESS: receiver acknowledged popup open. \(data.count) UTF-8 bytes → \(receiver.name).")
    }
}

struct MessageShareView: View {
    static let testMessage = "  iPhone 消息测试 📱✨\n第二行：中文、emoji 🙂\n\n保留空行和尾部空格  "
    @State private var text = ""
    @State private var sending = false
    @State private var task: Task<Void, Never>?
    @StateObject private var status = BridgeStatus.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextEditor(text: $text).frame(minHeight: 150, maxHeight: 280)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                .accessibilityLabel("消息内容").disabled(sending)
            Button("发送消息", systemImage: "paperplane") { start() }
                .buttonStyle(.borderedProminent).disabled(sending)
            if sending {
                ProgressView()
                Button("取消", role: .cancel) { task?.cancel() }
            }
            Text(status.message).font(.callout).accessibilityIdentifier("messageTransferStatus")
            Spacer()
        }
        .padding(24).navigationTitle("消息分享")

    }
    private func start() {
        sending = true
        task = Task {
            defer { sending = false }
            do {
                    let data = try MessagePayload.encode(text)
                    status.set("正在查找设备…")
                    let choices = try await BridgeNetwork.discover(serviceType: "_msgbridge._tcp")
                    try await SendMessageIntent.sendToAll(data, receivers: choices)
            } catch { status.fail(error) }
        }
    }
}
