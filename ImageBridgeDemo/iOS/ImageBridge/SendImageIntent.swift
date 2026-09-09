import AppIntents
import UniformTypeIdentifiers
import UIKit
import ImageIO
import OSLog

@MainActor
final class BridgeStatus: ObservableObject {
    static let shared = BridgeStatus()
    @Published var message = ""
    func set(_ text: String, detail: String? = nil) {
        message = text
        let log = detail ?? text
        print("IMAGEBRIDGE_STATUS: \(log)")
        Logger(subsystem: "com.rain.ImageBridge", category: "transfer").notice("\(log, privacy: .public)")
    }
    func fail(_ error: Error) {
        let text = error is CancellationError ? "已取消" :
            ((error as? BridgeFailure)?.localizedDescription ?? "发送失败，请检查连接后重试。")
        set(text, detail: "Failed: \(error.localizedDescription)")
    }
}

struct SendImageIntent: LongRunningIntent, CancellableIntent {
    static let title: LocalizedStringResource = "发送到我的华为手机"
    static let description = IntentDescription("将 1 至 20 张图片发送到我的华为手机并打开最后一张的系统预览。")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "图片", supportedContentTypes: [.image], inputConnectionBehavior: .connectToPreviousIntentResult)
    var image: [IntentFile]

    @Parameter(title: "接收设备")
    var receiver: String?

    static var parameterSummary: some ParameterSummary { Summary("发送\(\.$image)到我的华为手机") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cancellation = BridgeCancellation()
        let taskProgress = progress
        taskProgress.totalUnitCount = 100
        taskProgress.completedUnitCount = 0
        taskProgress.localizedDescription = "发送图片"
        do {
            _ = try ImageBatchSession(count: image.count)
            try Task.checkCancellation()
            taskProgress.localizedAdditionalDescription = "正在查找设备"
            await BridgeStatus.shared.set("正在查找设备…")
            // Bounded discovery and receiver choice precede the long-running transfer.
            let receivers = try await BridgeNetwork.discover(cancellation: cancellation)
            print("IMAGEBRIDGE_DISCOVERY_COMPLETE: \(receivers.count) receivers")
            taskProgress.completedUnitCount = 5
            // Any system-hosted user interaction occurs outside the background work closure.
            let selected: Receiver
            if receivers.count == 1 { selected = receivers[0] }
            else {
                let names = receivers.enumerated().map { "\($0.offset + 1). \($0.element.name)" }
                let choice = try await $receiver.requestDisambiguation(among: names, dialog: "选择接收设备")
                guard let index = names.firstIndex(of: choice) else { throw CancellationError() }
                selected = receivers[index]
            }
            let _: String = try await performBackgroundTask {
                try Task.checkCancellation()
                try cancellation.check()
                try await Self.send(count: image.count, to: selected, cancellation: cancellation, progress: taskProgress) { index in
                    image[index].data
                }
                return "sent"
            } onCancel: { reason in
                print("IMAGEBRIDGE_CANCEL: \(reason.debugDescription)")
                cancellation.cancel()
            }
            return .result(dialog: "已发送")
        } catch {
            await BridgeStatus.shared.fail(error)
            throw error
        }
    }

    // Shared by the system intent and the foreground UI; only perform() requests extended runtime.
    static func send(_ imageData: Data, to selected: Receiver,
                     cancellation: BridgeCancellation? = nil, progress: Progress? = nil) async throws {
        try await send(count: 1, to: selected, cancellation: cancellation, progress: progress) { _ in imageData }
    }

    static func send(count: Int, to selected: Receiver,
                     cancellation: BridgeCancellation? = nil, progress taskProgress: Progress? = nil,
                     load: (Int) async throws -> Data) async throws {
        taskProgress?.totalUnitCount = Int64(count * 1000)
        try await BridgeNetwork.sendImages(count: count, to: selected, cancellation: cancellation, load: { index in
            await BridgeStatus.shared.set("正在准备第 \(index + 1)/\(count) 张…")
            let data = try await load(index)
            try Task.checkCancellation()
            try cancellation?.check()
            return try autoreleasepool { try normalize(data) }
        }) { index, sent, total in
            taskProgress?.completedUnitCount = Int64(index * 1000 + (total > 0 ? sent * 999 / total : 0))
            let text = total == 0 ? "已确认 \(index)/\(count) 张" : "第 \(index + 1)/\(count) 张：\(sent)/\(total) 字节"
            taskProgress?.localizedAdditionalDescription = text
            Task { @MainActor in BridgeStatus.shared.set(text) }
        }
        taskProgress?.completedUnitCount = Int64(count * 1000)
        taskProgress?.localizedAdditionalDescription = "接收端已收到图片"
        await BridgeStatus.shared.set("已发送 \(count) 张", detail: "Success: \(count) images received; gallery save is confirmed on the receiving device.")
    }

    static func normalize(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85),
              jpeg.count <= BridgeFrame.maximumBytes else {
            throw BridgeFailure.message("无法处理图片，请换一张重试。")
        }
        return jpeg
    }
}

struct ImageBridgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SendImageIntent(), phrases: ["用\(.applicationName)发送图片"],
                    shortTitle: "发送到我的华为手机", systemImageName: "photo.on.rectangle")
        AppShortcut(intent: BeginCameraSessionIntent(), phrases: ["用\(.applicationName)记录拍照开始"],
                    shortTitle: "记录本次拍照开始", systemImageName: "camera")
        AppShortcut(intent: SendCameraSessionIntent(), phrases: ["用\(.applicationName)发送本次照片"],
                    shortTitle: "发送本次拍摄照片", systemImageName: "paperplane")
    }
}

// Camera automations share durable state in the app, avoiding iCloud-file timing races.
import Photos

@MainActor
private enum CameraSession {
    static let defaults = UserDefaults.standard
    static var sending = false
    static func begin() {
        defaults.set(Date().timeIntervalSince1970, forKey: "camera.start")
        defaults.removeObject(forKey: "camera.end")
        defaults.set([String](), forKey: "camera.sent")
    }
    static func data(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: BridgeFailure.message("无法读取拍摄照片，请稍后重试。")) }
            }
        }
    }
}

struct BeginCameraSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "记录本次拍照开始"
    static let supportedModes: IntentModes = .background
    static let description = IntentDescription("记录系统相机打开的时间，供结束拍照时查找新照片。")
    static var parameterSummary: some ParameterSummary { Summary("记录本次拍照开始时间") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw BridgeFailure.message("请先打开 ImageBridge，点击启用拍照自动发送，并允许访问所有照片。")
        }
        CameraSession.begin()
        return .result(dialog: "已记录拍照开始时间")
    }
}

struct SendCameraSessionIntent: LongRunningIntent, CancellableIntent {
    static let title: LocalizedStringResource = "发送本次拍摄的照片到华为"
    static let supportedModes: IntentModes = .background
    @Parameter(title: "接收设备") var receiver: String?

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !CameraSession.sending else { return .result(dialog: "正在发送") }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw BridgeFailure.message("请先在 ImageBridge 中启用拍照自动发送，允许访问所有照片。")
        }
        let start = CameraSession.defaults.double(forKey: "camera.start")
        guard start > 0 else { return .result(dialog: "没有拍照记录") }
        let oldEnd = CameraSession.defaults.double(forKey: "camera.end")
        let end = oldEnd > 0 ? oldEnd : Date().timeIntervalSince1970
        CameraSession.defaults.set(end, forKey: "camera.end")
        CameraSession.sending = true
        defer { CameraSession.sending = false }
        // Allow Photos to finish writing after Camera leaves the foreground.
        try await Task.sleep(for: .seconds(2))
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", Date(timeIntervalSince1970: start) as NSDate, Date(timeIntervalSince1970: end) as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        var sent = CameraSession.defaults.stringArray(forKey: "camera.sent") ?? []
        result.enumerateObjects { asset, _, _ in
            if !asset.mediaSubtypes.contains(.photoScreenshot) && !sent.contains(asset.localIdentifier) { assets.append(asset) }
        }
        guard !assets.isEmpty else { return .result(dialog: "没有新增照片") }
        let cancellation = BridgeCancellation()
        let receivers = try await BridgeNetwork.discover(cancellation: cancellation)
        let selected: Receiver
        if receivers.count == 1 { selected = receivers[0] }
        else {
            let names = receivers.enumerated().map { "\($0.offset + 1). \($0.element.name)" }
            let choice = try await $receiver.requestDisambiguation(among: names, dialog: "选择接收设备")
            guard let index = names.firstIndex(of: choice) else { throw CancellationError() }
            selected = receivers[index]
        }
        let files = assets
        let _: String = try await performBackgroundTask {
            for offset in stride(from: 0, to: files.count, by: 20) {
                let batch = Array(files[offset..<min(offset + 20, files.count)])
                try cancellation.check()
                try await SendImageIntent.send(count: batch.count, to: selected, cancellation: cancellation, progress: progress) { index in
                    if index > 0 {
                        let confirmed = batch[index - 1].localIdentifier
                        if !sent.contains(confirmed) { sent.append(confirmed) }
                        if CameraSession.defaults.double(forKey: "camera.start") == start {
                            CameraSession.defaults.set(sent, forKey: "camera.sent")
                        }
                    }
                    return try await CameraSession.data(for: batch[index])
                }
                sent.append(contentsOf: batch.map(\.localIdentifier))
                if CameraSession.defaults.double(forKey: "camera.start") == start {
                    CameraSession.defaults.set(sent, forKey: "camera.sent")
                }
            }
            return "sent"
        } onCancel: { _ in cancellation.cancel() }
        return .result(dialog: "已发送本次拍摄的照片")
    }
}
