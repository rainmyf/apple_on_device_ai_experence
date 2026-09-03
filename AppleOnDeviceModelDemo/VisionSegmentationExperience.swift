import CoreVideo
import Foundation
import ImageIO
import SwiftUI
import UIKit
import Vision

struct VisionSegmentationPoint: Equatable, Hashable, Sendable {
    let x: CGFloat
    let y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

struct VisionSegmentationRect: Equatable, Hashable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

enum VisionSegmentationSeed: Equatable, Hashable, Sendable {
    case point(VisionSegmentationPoint)
    case box(VisionSegmentationRect)
    case scribble([VisionSegmentationPoint])

    var displayPoints: [VisionSegmentationPoint] {
        switch self {
        case let .point(point): [point]
        case let .box(rect):
            [
                .init(x: rect.x, y: rect.y),
                .init(x: rect.x + rect.width, y: rect.y + rect.height),
            ]
        case let .scribble(points): points
        }
    }
}

enum VisionSegmentationCorrection: Equatable, Hashable, Sendable {
    case included(VisionSegmentationPoint)
    case excluded(VisionSegmentationPoint)
}

enum VisionSegmentationQuality: String, CaseIterable, Identifiable, Sendable {
    case fast, balanced, accurate

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    @available(iOS 27.0, *)
    var visionValue: GenerateIterativeSegmentationRequest.QualityLevel {
        switch self {
        case .fast: .fast
        case .balanced: .balanced
        case .accurate: .accurate
        }
    }
}

enum VisionSegmentationGeometry {
    static func visionPoint(fromDisplayPoint point: VisionSegmentationPoint) -> NormalizedPoint {
        NormalizedPoint(x: clamp(point.x), y: 1 - clamp(point.y))
    }

    static func visionRect(fromDisplayRect rect: VisionSegmentationRect) -> NormalizedRect {
        NormalizedRect(
            x: clamp(rect.x),
            y: clamp(1 - rect.y - rect.height),
            width: clamp(rect.width),
            height: clamp(rect.height)
        )
    }

    static func displayPoint(fromVisionPoint point: NormalizedPoint) -> VisionSegmentationPoint {
        .init(x: point.x, y: 1 - point.y)
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

enum VisionSegmentationAssetState: Equatable, Sendable {
    case unknown, downloading, ready, failed(String)
}

enum VisionSegmentationPhase: Equatable, Sendable {
    case idle, running, succeeded, failed(String), cancelled
}

struct VisionSegmentationOutput: @unchecked Sendable {
    let mask: CVReadOnlyPixelBuffer?
    let confidence: Float
}

enum VisionSegmentationError: LocalizedError, Equatable {
    case assetsUnavailable
    case invalidScribble
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetsUnavailable: "Assets could not be downloaded."
        case .invalidScribble: "Draw at least one scribble point."
        case let .requestFailed(message): message
        }
    }
}

protocol VisionSegmentationEngine: Sendable {
    func downloadAssets(progress: @escaping @Sendable (Double) -> Void) async throws
    func segment(
        imageData: Data,
        seed: VisionSegmentationSeed,
        corrections: [VisionSegmentationCorrection],
        quality: VisionSegmentationQuality,
        orientation: VisionImageOrientation,
        imageSize: CGSize,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> VisionSegmentationOutput
}

struct ClosureVisionSegmentationEngine: VisionSegmentationEngine {
    let download: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void
    let segment: @Sendable (
        VisionSegmentationSeed,
        [VisionSegmentationCorrection],
        VisionSegmentationQuality,
        VisionImageOrientation,
        CGSize
    ) async throws -> VisionSegmentationOutput

    init(
        download: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void,
        segment: @escaping @Sendable (
            VisionSegmentationSeed,
            [VisionSegmentationCorrection],
            VisionSegmentationQuality,
            VisionImageOrientation,
            CGSize
        ) async throws -> VisionSegmentationOutput
    ) {
        self.download = download
        self.segment = segment
    }

    func downloadAssets(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await download(progress)
    }

    func segment(
        imageData: Data,
        seed: VisionSegmentationSeed,
        corrections: [VisionSegmentationCorrection],
        quality: VisionSegmentationQuality,
        orientation: VisionImageOrientation,
        imageSize: CGSize,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> VisionSegmentationOutput {
        _ = imageData
        progress(0)
        let output = try await segment(seed, corrections, quality, orientation, imageSize)
        progress(1)
        return output
    }
}

@available(iOS 27.0, *)
struct SystemVisionSegmentationEngine: VisionSegmentationEngine {
    func downloadAssets(progress: @escaping @Sendable (Double) -> Void) async throws {
        try Task.checkCancellation()
        progress(0)
        let request = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
        if case .ready = await request.assetStatus {
            progress(1)
            return
        }
        let manager = ProgressManager(totalCount: 100)
        let child = manager.subprogress(assigningCount: 100)
        let observer = Task {
            while !Task.isCancelled {
                progress(manager.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { observer.cancel() }
        try await request.downloadAssets(progress: child)
        try Task.checkCancellation()
        progress(manager.fractionCompleted)
        progress(1)
    }

    func segment(
        imageData: Data,
        seed: VisionSegmentationSeed,
        corrections: [VisionSegmentationCorrection],
        quality: VisionSegmentationQuality,
        orientation: VisionImageOrientation,
        imageSize: CGSize,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> VisionSegmentationOutput {
        try Task.checkCancellation()
        progress(0)

        let request: GenerateIterativeSegmentationRequest
        switch seed {
        case let .point(point):
            request = GenerateIterativeSegmentationRequest(seedPoint: VisionSegmentationGeometry.visionPoint(fromDisplayPoint: point))
        case let .box(rect):
            request = GenerateIterativeSegmentationRequest(seedBox: VisionSegmentationGeometry.visionRect(fromDisplayRect: rect))
        case let .scribble(points):
            guard let scribbleBuffer = Self.makeScribbleBuffer(points: points, imageSize: imageSize) else {
                throw VisionSegmentationError.invalidScribble
            }
            request = GenerateIterativeSegmentationRequest(seedScribbleBuffer: CVReadOnlyPixelBuffer(unsafeBuffer: scribbleBuffer))
        }

        request.qualityLevel = quality.visionValue
        do {
            for correction in corrections {
                switch correction {
                case let .included(point):
                    try request.addIncludedPoint(VisionSegmentationGeometry.visionPoint(fromDisplayPoint: point))
                case let .excluded(point):
                    try request.addExcludedPoint(VisionSegmentationGeometry.visionPoint(fromDisplayPoint: point))
                }
            }
            let observation = try await request.perform(on: imageData, orientation: orientation.cgImagePropertyOrientation)
            try Task.checkCancellation()
            progress(1)
            return .init(mask: observation?.pixelBuffer, confidence: observation?.confidence ?? 0)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VisionSegmentationError {
            throw error
        } catch {
            throw VisionSegmentationError.requestFailed(error.localizedDescription)
        }
    }

    private static func makeScribbleBuffer(points: [VisionSegmentationPoint], imageSize: CGSize) -> CVPixelBuffer? {
        guard !points.isEmpty else { return nil }
        let width = max(Int(imageSize.width.rounded()), 1)
        let height = max(Int(imageSize.height.rounded()), 1)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer, let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        memset(baseAddress, 0, bytesPerRow * height)
        let radius = max(min(width, height) / 80, 2)
        for point in points {
            let x = Int(min(max(point.x, 0), 1) * CGFloat(width - 1))
            let y = Int(min(max(point.y, 0), 1) * CGFloat(height - 1))
            for row in max(0, y - radius)...min(height - 1, y + radius) {
                for column in max(0, x - radius)...min(width - 1, x + radius) {
                    let dx = column - x
                    let dy = row - y
                    if dx * dx + dy * dy <= radius * radius {
                        baseAddress.storeBytes(of: UInt8.max, toByteOffset: row * bytesPerRow + column, as: UInt8.self)
                    }
                }
            }
        }
        return pixelBuffer
    }
}

@MainActor
final class VisionSegmentationExperience: ObservableObject {
    @Published private(set) var assetState: VisionSegmentationAssetState = .unknown
    @Published private(set) var phase: VisionSegmentationPhase = .idle
    @Published private(set) var progress = 0.0
    @Published private(set) var output: VisionSegmentationOutput?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var errorMessage: String?

    var seed: VisionSegmentationSeed = .point(.init(x: 0.5, y: 0.5))
    var quality: VisionSegmentationQuality = .balanced
    private(set) var corrections: [VisionSegmentationCorrection] = []

    private let engine: any VisionSegmentationEngine
    private let clock: () -> TimeInterval
    private var generation = 0
    private(set) var operationTask: Task<Void, Never>?

    init(
        engine: any VisionSegmentationEngine = SystemVisionSegmentationEngine(),
        clock: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    ) {
        self.engine = engine
        self.clock = clock
    }

    func startDownloadAssets() {
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            await self?.downloadAssets()
        }
    }

    func startSegment(imageData: Data, imageSize: CGSize, orientation: VisionImageOrientation = .up) {
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            await self?.segment(imageData: imageData, imageSize: imageSize, orientation: orientation)
        }
    }

    func addIncludedPoint(_ point: VisionSegmentationPoint) {
        corrections.append(.included(point))
    }

    func addExcludedPoint(_ point: VisionSegmentationPoint) {
        corrections.append(.excluded(point))
    }

    func downloadAssets() async {
        generation += 1
        let token = generation
        assetState = .downloading
        errorMessage = nil
        progress = 0
        do {
            try await engine.downloadAssets { [weak self] value in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.progress = min(max(value, 0), 1)
                }
            }
            guard generation == token else { return }
            assetState = .ready
            progress = 1
        } catch is CancellationError {
            guard generation == token else { return }
            assetState = .unknown
            errorMessage = nil
        } catch {
            guard generation == token else { return }
            let message = VisionSegmentationError.assetsUnavailable.errorDescription!
            assetState = .failed(message)
            errorMessage = message
        }
        if generation == token { operationTask = nil }
    }

    func segment(
        imageData: Data,
        imageSize: CGSize,
        orientation: VisionImageOrientation = .up
    ) async {
        generation += 1
        let token = generation
        phase = .running
        output = nil
        latency = nil
        errorMessage = nil
        progress = 0
        let start = clock()
        defer {
            if generation == token {
                latency = clock() - start
            }
        }

        do {
            if case let .scribble(points) = seed, points.isEmpty {
                throw VisionSegmentationError.invalidScribble
            }
            let result = try await engine.segment(
                imageData: imageData,
                seed: seed,
                corrections: corrections,
                quality: quality,
                orientation: orientation,
                imageSize: imageSize
            ) { [weak self] value in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.progress = min(max(value, 0), 1)
                }
            }
            try Task.checkCancellation()
            guard generation == token else { return }
            output = result
            progress = 1
            phase = .succeeded
        } catch is CancellationError {
            guard generation == token else { return }
            phase = .cancelled
        } catch {
            guard generation == token else { return }
            let message = error.localizedDescription
            errorMessage = message
            phase = .failed(message)
        }
        if generation == token { operationTask = nil }
    }

    func cancel() {
        operationTask?.cancel()
        operationTask = nil
        generation += 1
        assetState = .unknown
        phase = .cancelled
    }

    func reset() {
        operationTask?.cancel()
        operationTask = nil
        generation += 1
        assetState = .unknown
        phase = .idle
        progress = 0
        output = nil
        latency = nil
        errorMessage = nil
        corrections = []
        seed = .point(.init(x: 0.5, y: 0.5))
    }
}
