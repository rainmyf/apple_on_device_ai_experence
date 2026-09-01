import Foundation
import Synchronization
import Testing
import UIKit
@testable import AppleOnDeviceModelDemo

@MainActor
struct VisionExperienceTests {
    @Test func textFindingsSortTopToBottom() {
        let findings = VisionFinding.sortForReadingOrder([
            .text("bottom", box: .init(x: 0, y: 0.1, width: 1, height: 0.1), confidence: 0.8),
            .text("top", box: .init(x: 0, y: 0.8, width: 1, height: 0.1), confidence: 0.9)
        ])

        #expect(findings.map(\.label) == ["top", "bottom"])
    }

    @Test func textMappingRetainsGeometryAndConfidence() {
        let finding = VisionFinding.text(
            "Hello",
            box: .init(x: 0.2, y: 0.3, width: 0.4, height: 0.1),
            confidence: 0.73
        )

        #expect(finding.kind == .text)
        #expect(finding.label == "Hello")
        #expect(finding.box == .init(x: 0.2, y: 0.3, width: 0.4, height: 0.1))
        #expect(finding.confidence == 0.73)
    }

    @Test func barcodeMappingRetainsPayloadAndGeometry() {
        let finding = VisionFinding.barcode(
            payload: "https://example.com",
            symbology: "QR",
            box: .init(x: 0.1, y: 0.2, width: 0.3, height: 0.3),
            confidence: 0.99
        )

        #expect(finding.kind == .barcode)
        #expect(finding.label == "QR")
        #expect(finding.payload == "https://example.com")
        #expect(finding.box == .init(x: 0.1, y: 0.2, width: 0.3, height: 0.3))
        #expect(finding.confidence == 0.99)
    }

    @Test func poseMappingFiltersPointsBelowConfidenceThreshold() {
        let finding = VisionFinding.pose(
            "Person 1",
            points: [
                .init(name: "nose", x: 0.5, y: 0.8, confidence: 0.91),
                .init(name: "leftWrist", x: 0.2, y: 0.4, confidence: 0.49),
            ],
            minimumConfidence: 0.5
        )

        #expect(finding.points.map(\.name) == ["nose"])
        #expect(finding.points.first?.confidence == 0.91)
    }

    @Test func classificationMappingRetainsLabelAndConfidenceWithoutGeometry() {
        let finding = VisionFinding.classification("cat", confidence: 0.88)

        #expect(finding.kind == .classification)
        #expect(finding.label == "cat")
        #expect(finding.confidence == 0.88)
        #expect(finding.box == nil)
    }

    @Test func displayGeometryFlipsVisionBottomLeftIntoTopLeftCoordinates() {
        let rect = VisionDisplayGeometry.displayRect(
            .init(x: 0.2, y: 0.3, width: 0.4, height: 0.1),
            orientation: .up
        )

        #expect(rect == .init(x: 0.2, y: 0.6, width: 0.4, height: 0.1))
    }

    @Test(arguments: [VisionImageOrientation.up, .down, .left, .right])
    func displayGeometryOnlyFlipsVisionOriginAfterHandlerOrientation(_ orientation: VisionImageOrientation) {
        let rect = VisionDisplayGeometry.displayRect(
            .init(x: 0.2, y: 0.3, width: 0.4, height: 0.1),
            orientation: orientation
        )

        switch orientation {
        case .up:
            #expect(rect == .init(x: 0.2, y: 0.6, width: 0.4, height: 0.1))
        case .down:
            #expect(rect == .init(x: 0.2, y: 0.6, width: 0.4, height: 0.1))
        case .left:
            #expect(rect == .init(x: 0.2, y: 0.6, width: 0.4, height: 0.1))
        case .right:
            #expect(rect == .init(x: 0.2, y: 0.6, width: 0.4, height: 0.1))
        default:
            Issue.record("This fixture intentionally covers only the four base orientations.")
        }
    }

    @Test func requestAdapterReceivesSelectedModeAndOrientation() async {
        let probe = VisionRequestProbe()
        let analyzer = VisionAnalyzing(
            clock: { 10 },
            decode: { _ in VisionDecodedImage(identifier: "fixture") },
            request: { _, mode, orientation in
                probe.record(mode: mode, orientation: orientation)
                return []
            }
        )

        await analyzer.analyze(data: Data([1]), mode: .barcodes, orientation: .right)

        #expect(probe.mode == .barcodes)
        #expect(probe.orientation == .right)
        #expect(analyzer.errorMessage == nil)
        #expect(analyzer.latency == 0)
    }

    @Test func imageDecodeFailureIsReportedWithoutRunningVision() async {
        let analyzer = VisionAnalyzing(
            clock: { 10 },
            decode: { _ in throw VisionAnalysisError.imageDecodeFailed },
            request: { _, _, _ in [.classification("unexpected", confidence: 1)] }
        )

        await analyzer.analyze(data: Data([1]), mode: .recognizedText)

        #expect(analyzer.findings.isEmpty)
        #expect(analyzer.errorMessage == "The selected image could not be decoded.")
        #expect(analyzer.latency == 0)
    }

    @Test func runnerErrorIsPublishedAsAnAppError() async {
        let analyzer = VisionAnalyzing(
            clock: { 10 },
            decode: { _ in VisionDecodedImage(identifier: "fixture") },
            request: { _, _, _ in throw VisionAnalysisError.requestFailed("Vision failed") }
        )

        await analyzer.analyze(data: Data([1]), mode: .recognizedText)

        #expect(analyzer.errorMessage == "Vision failed")
        #expect(analyzer.findings.isEmpty)
        #expect(!analyzer.isRunning)
    }

    @Test func cancellationIsVisibleWithoutBecomingAnError() async {
        let analyzer = VisionAnalyzing(
            clock: { 10 },
            decode: { _ in VisionDecodedImage(identifier: "fixture") },
            request: { _, _, _ in throw CancellationError() }
        )

        await analyzer.analyze(data: Data([1]), mode: .recognizedText)

        #expect(analyzer.runState == .cancelled)
        #expect(analyzer.errorMessage == nil)
        #expect(!analyzer.isRunning)
    }

    @Test func successfulRunPublishesFindingsAndLatency() async {
        var times = [10.0, 10.25].makeIterator()
        let analyzer = VisionAnalyzing(
            clock: { times.next()! },
            decode: { _ in VisionDecodedImage(identifier: "fixture") },
            request: { _, _, _ in
                [VisionFinding.classification("cat", confidence: 0.88)]
            }
        )

        await analyzer.analyze(data: Data([1]), mode: .imageClassification)

        #expect(analyzer.findings.map(\.label) == ["cat"])
        #expect(analyzer.latency == 0.25)
        #expect(analyzer.runState == .succeeded)
        #expect(analyzer.errorMessage == nil)
    }

    @Test func resetClearsFindingsLatencyErrorAndRunState() async {
        let analyzer = VisionAnalyzing(
            clock: { 10 },
            decode: { _ in VisionDecodedImage(identifier: "fixture") },
            request: { _, _, _ in [.classification("cat", confidence: 0.88)] }
        )

        await analyzer.analyze(data: Data([1]), mode: .imageClassification)
        analyzer.reset()

        #expect(analyzer.findings.isEmpty)
        #expect(analyzer.latency == nil)
        #expect(analyzer.errorMessage == nil)
        #expect(analyzer.runState == .idle)
        #expect(!analyzer.isRunning)
    }

    @Test func delayedOldImageCannotReplaceNewSelection() async {
        let loader = VisionImageLoader()
        let oldProviderStarted = AsyncLatch()
        var releaseOld: (() -> Void)?
        let oldGeneration = loader.beginLoad()
        let oldTask = Task {
            await loader.load(generation: oldGeneration) {
                await oldProviderStarted.signal()
                return await withCheckedContinuation { continuation in
                    releaseOld = { continuation.resume(returning: VisionLoadedImage(identifier: "old", data: Data([1]), orientation: .up)) }
                }
            }
        }
        await oldProviderStarted.wait()

        let newGeneration = loader.beginLoad()
        await loader.load(generation: newGeneration) {
            VisionLoadedImage(identifier: "new", data: Data([2]), orientation: .right)
        }
        releaseOld?()
        await oldTask.value

        #expect(loader.selected?.identifier == "new")
        #expect(loader.selected?.data == Data([2]))
    }

    @Test func asyncLatchPreservesSignalBeforeWait() async {
        let latch = AsyncLatch()

        await latch.signal()
        await latch.wait()
    }

    @Test func failedImageLoadClearsPreviousSelection() async {
        let loader = VisionImageLoader()
        await loader.load {
            VisionLoadedImage(identifier: "old", data: Data([1]), orientation: .up)
        }

        await loader.load { throw VisionAnalysisError.imageDecodeFailed }

        #expect(loader.selected == nil)
        #expect(loader.errorMessage == "The selected image could not be decoded.")
    }

    @Test func cancelledImageLoadIsVisibleAndClearsPreviousSelection() async {
        let loader = VisionImageLoader()
        await loader.load {
            VisionLoadedImage(identifier: "old", data: Data([1]), orientation: .up)
        }

        await loader.load { throw CancellationError() }

        #expect(loader.selected == nil)
        #expect(loader.errorMessage == "Image loading was cancelled.")
    }

    @Test func serialWorkerDoesNotRunNewRequestAlongsideBlockedRequest() async {
        let probe = BlockingVisionProbe()
        let analyzer = VisionAnalyzing(
            clock: { 10 },
            decode: { _ in VisionDecodedImage(identifier: "fixture") },
            request: { _, _, _ in try probe.run() }
        )

        let first = Task { await analyzer.analyze(data: Data([1]), mode: .recognizedText) }
        await probe.waitForFirstStart()
        analyzer.reset()
        let second = Task { await analyzer.analyze(data: Data([2]), mode: .barcodes) }
        probe.releaseFirst()
        await first.value
        await second.value
        #expect(probe.maximumConcurrentCalls == 1)
    }
}

#if !targetEnvironment(simulator)
@MainActor
struct PhysicalDeviceVisionTests {
    @Test
    func exercisesVisionOCRWithRenderedTextOnPhysicalDevice() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 120, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            NSString(string: "HELLO 26").draw(at: CGPoint(x: 80, y: 70), withAttributes: attributes)
        }
        let data = image.pngData()!
        let analyzer = VisionAnalyzing()

        await analyzer.analyze(data: data, mode: .recognizedText)

        let text = analyzer.findings.map(\.label).joined(separator: " ")
        #expect(analyzer.runState == .succeeded)
        #expect(text.localizedCaseInsensitiveContains("HELLO"))
        print("DEVICE_RESULT|VISION-02|PASS|\(text)")
    }
}
#endif

private actor AsyncLatch {
    private var waiter: CheckedContinuation<Void, Never>?
    private var signaled = false

    func wait() async {
        if signaled {
            signaled = false
            return
        }
        await withCheckedContinuation { waiter = $0 }
    }

    func signal() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            signaled = true
        }
    }
}

private final class VisionRequestProbe: Sendable {
    private struct State: Sendable {
        var calls = 0
        var mode: VisionMode?
        var orientation: VisionImageOrientation?
    }

    private let state = Mutex(State())

    var calls: Int { state.withLock { $0.calls } }
    var mode: VisionMode? { state.withLock { $0.mode } }
    var orientation: VisionImageOrientation? { state.withLock { $0.orientation } }

    func incrementCalls() { state.withLock { $0.calls += 1 } }
    func record(mode: VisionMode, orientation: VisionImageOrientation) {
        state.withLock {
            $0.mode = mode
            $0.orientation = orientation
        }
    }
}

private final class BlockingVisionProbe: Sendable {
    private struct State: Sendable {
        var activeCalls = 0
        var maxCalls = 0
        var starts = 0
    }

    private let state = Mutex(State())
    private let release = DispatchSemaphore(value: 0)

    var maximumConcurrentCalls: Int { state.withLock { $0.maxCalls } }

    var hasStarted: Bool { state.withLock { $0.starts > 0 } }

    func waitForFirstStart() async {
        while !hasStarted {
            await Task.yield()
        }
    }

    func run() throws -> [VisionFinding] {
        let callNumber = state.withLock { state -> Int in
            state.activeCalls += 1
            state.starts += 1
            state.maxCalls = max(state.maxCalls, state.activeCalls)
            return state.starts
        }
        if callNumber == 1 {
            release.wait()
        }
        state.withLock { $0.activeCalls -= 1 }
        return []
    }

    func releaseFirst() { release.signal() }
}
