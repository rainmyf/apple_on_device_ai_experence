import CoreVideo
import Foundation
import Testing
@testable import AppleOnDeviceModelDemo

@MainActor
struct VisionSegmentationExperienceTests {
    @Test func displaySeedCoordinatesConvertToVisionLowerLeftCoordinates() {
        let point = VisionSegmentationGeometry.visionPoint(
            fromDisplayPoint: .init(x: 0.25, y: 0.2)
        )
        let box = VisionSegmentationGeometry.visionRect(
            fromDisplayRect: .init(x: 0.1, y: 0.2, width: 0.4, height: 0.3)
        )

        #expect(point == .init(x: 0.25, y: 0.8))
        #expect(box == .init(x: 0.1, y: 0.5, width: 0.4, height: 0.3))
    }

    @Test func scribbleSeedPreservesTheOrderedDisplayPath() {
        let scribble = VisionSegmentationSeed.scribble([
            .init(x: 0.2, y: 0.3),
            .init(x: 0.4, y: 0.5),
        ])

        #expect(scribble.displayPoints == [
            .init(x: 0.2, y: 0.3),
            .init(x: 0.4, y: 0.5),
        ])
    }

    @Test @available(iOS 27.0, *) func qualityLevelsExposeAllPublicVisionQualityValues() {
        #expect(VisionSegmentationQuality.allCases.map(\.visionValue) == [.fast, .balanced, .accurate])
    }

    @Test func positiveAndNegativeCorrectionsArePassedToTheNextIteration() async {
        let probe = SegmentationEngineProbe()
        let model = VisionSegmentationExperience(engine: probe.engine, clock: { 10 })
        model.seed = .point(.init(x: 0.4, y: 0.3))
        model.addIncludedPoint(.init(x: 0.2, y: 0.1))
        model.addExcludedPoint(.init(x: 0.8, y: 0.9))

        await model.segment(imageData: Data([1]), imageSize: .init(width: 100, height: 100))

        #expect(probe.lastSeed == .point(.init(x: 0.4, y: 0.3)))
        #expect(probe.lastCorrections == [
            .included(.init(x: 0.2, y: 0.1)),
            .excluded(.init(x: 0.8, y: 0.9)),
        ])
    }

    @Test func selectedImageOrientationIsPassedToTheVisionRequest() async {
        let probe = SegmentationEngineProbe()
        let model = VisionSegmentationExperience(engine: probe.engine)

        await model.segment(
            imageData: Data([1]),
            imageSize: .init(width: 40, height: 30),
            orientation: .right
        )

        #expect(probe.lastOrientation == .right)
    }

    @Test func downloadProgressForwardsIntermediateAndFinalValues() async {
        let probe = SegmentationEngineProbe()
        let model = VisionSegmentationExperience(engine: probe.engine)

        await model.downloadAssets()

        #expect(probe.downloadProgressValues.contains(0.25))
        #expect(probe.downloadProgressValues.last == 1)
        #expect(model.progress == 1)
    }

    @Test func boxAndScribbleSeedsAreAcceptedByTheIterationModel() async {
        let probe = SegmentationEngineProbe()
        let model = VisionSegmentationExperience(engine: probe.engine)

        model.seed = .box(.init(x: 0.1, y: 0.2, width: 0.5, height: 0.4))
        await model.segment(imageData: Data([1]), imageSize: .init(width: 20, height: 20))
        #expect(probe.lastSeed == .box(.init(x: 0.1, y: 0.2, width: 0.5, height: 0.4)))

        model.seed = .scribble([.init(x: 0.1, y: 0.1), .init(x: 0.3, y: 0.3)])
        await model.segment(imageData: Data([1]), imageSize: .init(width: 20, height: 20))
        #expect(probe.lastSeed == .scribble([.init(x: 0.1, y: 0.1), .init(x: 0.3, y: 0.3)]))
    }

    @Test func successfulIterationPublishesPixelBufferMaskQualityAndLatency() async {
        let probe = SegmentationEngineProbe(output: .init(mask: nil, confidence: 0.82))
        let model = VisionSegmentationExperience(engine: probe.engine, clock: { 10.25 })
        model.quality = .accurate

        await model.segment(imageData: Data([1]), imageSize: .init(width: 10, height: 10))

        #expect(model.phase == .succeeded)
        #expect(model.output?.confidence == 0.82)
        #expect(model.latency == 0)
        #expect(probe.lastQuality == .accurate)
    }

    @Test func assetFailureIsPublishedAndDoesNotRunSegmentation() async {
        let probe = SegmentationEngineProbe(assetError: TestSegmentationError.assetUnavailable)
        let model = VisionSegmentationExperience(engine: probe.engine)

        await model.downloadAssets()

        #expect(model.assetState == .failed("Assets could not be downloaded."))
        #expect(model.errorMessage == "Assets could not be downloaded.")
        #expect(probe.segmentCallCount == 0)
    }

    @Test func cancelledAssetDownloadReturnsToUnknownWithoutAnError() async {
        let probe = SegmentationEngineProbe(downloadCancelled: true)
        let model = VisionSegmentationExperience(engine: probe.engine)

        await model.downloadAssets()

        #expect(model.assetState == .unknown)
        #expect(model.errorMessage == nil)
    }

    @Test func cancellationPublishesCancelledWithoutAnError() async {
        let probe = SegmentationEngineProbe(segmentCancelled: true)
        let model = VisionSegmentationExperience(engine: probe.engine)

        await model.segment(imageData: Data([1]), imageSize: .init(width: 10, height: 10))

        #expect(model.phase == .cancelled)
        #expect(model.errorMessage == nil)
    }

    @Test func cancelInterruptsAnInFlightSegmentTask() async {
        let engine = ClosureVisionSegmentationEngine(
            download: { _ in },
            segment: { _, _, _, _, _ in
                try await Task.sleep(for: .seconds(60))
                return .init(mask: nil, confidence: 1)
            }
        )
        let model = VisionSegmentationExperience(engine: engine)
        model.startSegment(imageData: Data([1]), imageSize: .init(width: 10, height: 10))
        while model.phase != .running { await Task.yield() }
        model.cancel()
        while model.phase != .cancelled { await Task.yield() }
        #expect(model.errorMessage == nil)
    }

    @Test func resetClearsMaskCorrectionsProgressLatencyAndErrors() async {
        let probe = SegmentationEngineProbe(output: .init(mask: nil, confidence: 0.5))
        let model = VisionSegmentationExperience(engine: probe.engine, clock: { 10 })
        model.addIncludedPoint(.init(x: 0.2, y: 0.2))
        await model.segment(imageData: Data([1]), imageSize: .init(width: 10, height: 10))
        model.reset()

        #expect(model.phase == .idle)
        #expect(model.output == nil)
        #expect(model.progress == 0)
        #expect(model.latency == nil)
        #expect(model.corrections.isEmpty)
        #expect(model.errorMessage == nil)
    }
}

private enum TestSegmentationError: Error {
    case assetUnavailable
}

private struct SegmentationEngineProbe: Sendable {
    private let state: State
    let engine: any VisionSegmentationEngine

    init(
        output: VisionSegmentationOutput = .init(mask: nil, confidence: 1),
        assetError: TestSegmentationError? = nil,
        downloadCancelled: Bool = false,
        segmentCancelled: Bool = false
    ) {
        let state = State()
        self.state = state
        self.engine = ClosureVisionSegmentationEngine(
            download: { progress in
                progress(0.25)
                state.downloadProgressValues.append(0.25)
                if downloadCancelled { throw CancellationError() }
                if let assetError { throw assetError }
                progress(1)
                state.downloadProgressValues.append(1)
            },
            segment: { seed, corrections, quality, orientation, _ in
                state.lastSeed = seed
                state.lastCorrections = corrections
                state.lastQuality = quality
                state.lastOrientation = orientation
                state.segmentCallCount += 1
                if segmentCancelled { throw CancellationError() }
                return output
            }
        )
    }

    var lastSeed: VisionSegmentationSeed? { state.lastSeed }
    var lastCorrections: [VisionSegmentationCorrection] { state.lastCorrections }
    var lastQuality: VisionSegmentationQuality? { state.lastQuality }
    var lastOrientation: VisionImageOrientation? { state.lastOrientation }
    var downloadProgressValues: [Double] { state.downloadProgressValues }
    var segmentCallCount: Int { state.segmentCallCount }

    private final class State: @unchecked Sendable {
        var lastSeed: VisionSegmentationSeed?
        var lastCorrections: [VisionSegmentationCorrection] = []
        var lastQuality: VisionSegmentationQuality?
        var lastOrientation: VisionImageOrientation?
        var downloadProgressValues: [Double] = []
        var segmentCallCount = 0
    }
}
