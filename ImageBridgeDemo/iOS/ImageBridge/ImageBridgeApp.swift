import SwiftUI
import Photos
import PhotosUI
import AppIntents
import UniformTypeIdentifiers

@main
struct ImageBridgeApp: App {
    var body: some Scene { WindowGroup { ContentView().task { ImageBridgeShortcuts.updateAppShortcutParameters() } } }
}

struct ContentView: View {
    @State private var path: [String] = []
    @State private var cameraStatus = ""
    var body: some View {
        NavigationStack(path: $path) {
            List {
                NavigationLink("图片分享", value: "image")
                NavigationLink("消息分享", value: "message")
                Button("启用拍照自动发送") {
                    Task {
                        let permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        cameraStatus = permission == .authorized ? "已授权，请绑定相机自动化" : "请在系统设置中允许访问所有照片"
                    }
                }
                if !cameraStatus.isEmpty { Text(cameraStatus).font(.footnote) }
            }
            .navigationTitle("演示")
            .navigationDestination(for: String.self) { route in
                if route == "image" { ImageShareView() }
                else { MessageShareView() }
            }

        }
    }
}

struct ImageShareView: View {
    @StateObject private var status = BridgeStatus.shared
    @State private var photos: [PhotosPickerItem] = []
    @State private var sending = false
    @State private var task: Task<Void, Never>?
    @State private var receiverChoices: [Receiver] = []
    @State private var pendingCount = 0
    @State private var pendingLoad: ((Int) async throws -> Data)?
    @State private var choosingReceiver = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 54)).foregroundStyle(.blue)
            PhotosPicker(selection: $photos, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images) {
                Label("选择图片并发送", systemImage: "photo.on.rectangle")
            }.buttonStyle(.borderedProminent).disabled(sending || choosingReceiver)
            Button("发送测试图片", systemImage: "paperplane") { send(count: 1) { _ in Self.testImage() } }
                .buttonStyle(.bordered).disabled(sending || choosingReceiver)
            if sending {
                ProgressView()
                Button("取消", role: .cancel) { task?.cancel() }
            }
            Text(status.message).font(.callout).accessibilityIdentifier("transferStatus")
            Spacer()
        }
        .padding(24)
        .navigationTitle("图片分享")
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            send(count: items.count) { index in
                guard let data = try await items[index].loadTransferable(type: Data.self) else {
                    throw BridgeFailure.message("无法读取第 \(index + 1) 张图片，请重新选择。")
                }
                return data
            }
        }
        .confirmationDialog("选择接收设备", isPresented: $choosingReceiver, titleVisibility: .visible) {
            ForEach(receiverChoices.indices, id: \.self) { index in
                Button(receiverChoices[index].name) {
                    guard let load = pendingLoad else { return }
                    let count = pendingCount
                    let receiver = receiverChoices[index]
                    pendingLoad = nil
                    sending = true
                    task = Task {
                        do { try await SendImageIntent.send(count: count, to: receiver, load: load) }
                        catch { status.fail(error) }
                        sending = false
                    }
                }
            }
            Button("取消", role: .cancel) { pendingLoad = nil; status.set("已取消") }
        }

    }
    private func send(count: Int, load: @escaping (Int) async throws -> Data) {
        sending = true
        task = Task {
            do {
                    status.set("正在查找设备…")
                    let receivers = try await BridgeNetwork.discover()
                    if receivers.count == 1 {
                        try await SendImageIntent.send(count: count, to: receivers[0], load: load)
                    } else {
                        pendingCount = count
                        pendingLoad = load
                        receiverChoices = receivers
                        choosingReceiver = true
                    }
            } catch { status.fail(error) }
            sending = false
        }
    }
    @MainActor static func testImage(index: Int = 0) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor(red: 0.04, green: 0.13, blue: 0.26, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            UIColor.systemCyan.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 760, y: 80, width: 300, height: 300))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 120, y: 520, width: 940, height: 100))
            ("ImageBridge" as NSString).draw(at: CGPoint(x: 100, y: 150), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 92), .foregroundColor: UIColor.white])
            ("iPhone → HarmonyOS" as NSString).draw(at: CGPoint(x: 100, y: 310), withAttributes: [.font: UIFont.systemFont(ofSize: 54), .foregroundColor: UIColor.white])
            ("TEST \(index + 1) — 1200 × 800" as NSString).draw(at: CGPoint(x: 120, y: 660), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 40, weight: .medium), .foregroundColor: UIColor.white])
        }
    }
}
