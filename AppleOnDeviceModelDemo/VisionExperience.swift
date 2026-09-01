import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import Vision

enum VisionMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case recognizedText
    case barcodes
    case humanBodyPose
    case imageClassification

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recognizedText: "Recognized text"
        case .barcodes: "Barcodes"
        case .humanBodyPose: "Human body pose"
        case .imageClassification: "Image classification"
        }
    }

    var systemImage: String {
        switch self {
        case .recognizedText: "text.viewfinder"
        case .barcodes: "barcode.viewfinder"
        case .humanBodyPose: "figure.stand"
        case .imageClassification: "square.grid.2x2"
        }
    }
}

struct VisionRect: Equatable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct VisionPosePoint: Equatable, Hashable, Sendable {
    let name: String
    let x: Double
    let y: Double
    let confidence: Double

    init(name: String, x: Double, y: Double, confidence: Double) {
        self.name = name
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

enum VisionImageOrientation: CaseIterable, Hashable, Sendable {
    case up, upMirrored, down, downMirrored, left, leftMirrored, right, rightMirrored

    init(_ orientation: CGImagePropertyOrientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }

    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }

    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        }
    }
}

enum VisionDisplayGeometry {
    /// Vision handles image orientation. The app only converts Vision's lower-left origin to top-left.
    static func displayRect(_ rect: VisionRect, orientation: VisionImageOrientation) -> VisionRect {
        _ = orientation
        return VisionRect(x: rect.x, y: 1 - rect.y - rect.height, width: rect.width, height: rect.height)
    }

    static func displayPoint(_ point: VisionPosePoint, orientation: VisionImageOrientation) -> VisionPosePoint {
        _ = orientation
        return .init(name: point.name, x: point.x, y: 1 - point.y, confidence: point.confidence)
    }
}

struct VisionFinding: Equatable, Hashable, Identifiable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case text, barcode, pose, classification
    }

    let kind: Kind
    let label: String
    let box: VisionRect?
    let confidence: Double?
    let payload: String?
    let points: [VisionPosePoint]

    var id: String {
        "\(kind.rawValue):\(label):\(payload ?? ""):\(box.map(String.init(describing:)) ?? "")"
    }

    static func text(_ label: String, box: VisionRect, confidence: Double? = nil) -> Self {
        Self(kind: .text, label: label, box: box, confidence: confidence, payload: nil, points: [])
    }

    static func barcode(payload: String?, symbology: String, box: VisionRect, confidence: Double? = nil) -> Self {
        Self(kind: .barcode, label: symbology, box: box, confidence: confidence, payload: payload, points: [])
    }

    static func pose(_ label: String, points: [VisionPosePoint], minimumConfidence: Double = 0.5, confidence: Double? = nil) -> Self {
        let filtered = points.filter { $0.confidence >= minimumConfidence }
        return Self(kind: .pose, label: label, box: nil, confidence: confidence, payload: nil, points: filtered)
    }

    static func classification(_ label: String, confidence: Double) -> Self {
        Self(kind: .classification, label: label, box: nil, confidence: confidence, payload: nil, points: [])
    }

    static func sortForReadingOrder(_ findings: [Self]) -> [Self] {
        findings.sorted {
            guard let left = $0.box, let right = $1.box else { return $0.box != nil }
            let yDelta = abs(left.y - right.y)
            return yDelta > 0.025 ? left.y > right.y : left.x < right.x
        }
    }
}

/// Sendable input passed to the serial Vision worker.
///
/// UIKit/CoreGraphics image objects intentionally stay inside the worker. This
/// value carries only immutable bytes and metadata across the actor boundary.
struct VisionDecodedImage: Sendable {
    let identifier: String
    let data: Data

    init(identifier: String, data: Data = Data()) {
        self.identifier = identifier
        self.data = data
    }
}

enum VisionAnalysisError: LocalizedError, Equatable {
    case imageDecodeFailed
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed: "The selected image could not be decoded."
        case .requestFailed(let message): message
        }
    }
}

enum VisionRunState: Equatable, Sendable {
    case idle, running, succeeded, failed(String), cancelled
}

struct VisionLoadedImage: Equatable, Sendable {
    let identifier: String
    let data: Data
    let orientation: VisionImageOrientation
}

@MainActor
final class VisionImageLoader: ObservableObject {
    typealias Provider = () async throws -> VisionLoadedImage

    @Published private(set) var selected: VisionLoadedImage?
    @Published private(set) var errorMessage: String?

    private var generation = 0

    /// Starts a selection transaction synchronously on the main actor.
    /// Returning the token before awaiting the provider prevents an older,
    /// cancelled provider from claiming a newer selection's result.
    func beginLoad() -> Int {
        generation += 1
        selected = nil
        errorMessage = nil
        return generation
    }

    func isCurrent(generation token: Int) -> Bool {
        generation == token
    }

    func load(_ provider: @escaping Provider) async {
        do {
            try Task.checkCancellation()
        } catch {
            return
        }
        let loadGeneration = beginLoad()
        await load(generation: loadGeneration, using: provider)
    }

    func load(generation loadGeneration: Int, using provider: @escaping Provider) async {
        do {
            try Task.checkCancellation()
        } catch {
            return
        }
        guard loadGeneration == generation else { return }

        do {
            let image = try await provider()
            try Task.checkCancellation()
            guard loadGeneration == generation else { return }
            selected = image
        } catch is CancellationError {
            guard loadGeneration == generation, !Task.isCancelled else { return }
            errorMessage = "Image loading was cancelled."
        } catch {
            guard loadGeneration == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private actor VisionRequestWorker {
    typealias Request = @Sendable (VisionDecodedImage, VisionMode, VisionImageOrientation) throws -> [VisionFinding]

    private let request: Request

    init(request: @escaping Request) {
        self.request = request
    }

    func run(image: VisionDecodedImage, mode: VisionMode, orientation: VisionImageOrientation) throws -> [VisionFinding] {
        try Task.checkCancellation()
        let findings = try request(image, mode, orientation)
        try Task.checkCancellation()
        return findings
    }
}

@MainActor
final class VisionAnalyzing: ObservableObject {
    typealias Decoder = (Data) throws -> VisionDecodedImage
    typealias Request = @Sendable (VisionDecodedImage, VisionMode, VisionImageOrientation) throws -> [VisionFinding]

    @Published private(set) var findings: [VisionFinding] = []
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var runState: VisionRunState = .idle

    private let clock: () -> TimeInterval
    private let decode: Decoder
    private let worker: VisionRequestWorker
    private var generation = 0

    init(
        clock: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate },
        decode: @escaping Decoder = VisionAnalyzing.decodeImage,
        request: @escaping Request = VisionAnalyzing.performRequest
    ) {
        self.clock = clock
        self.decode = decode
        self.worker = VisionRequestWorker(request: request)
    }

    func reset() {
        generation += 1
        findings = []
        latency = nil
        errorMessage = nil
        isRunning = false
        runState = .idle
    }

    func analyze(data: Data, mode: VisionMode, orientation: VisionImageOrientation = .up) async {
        guard !isRunning else { return }
        findings = []
        latency = nil
        errorMessage = nil
        isRunning = true
        runState = .running
        let start = clock()
        let runGeneration = generation
        defer {
            if runGeneration == generation {
                latency = clock() - start
                isRunning = false
            }
        }

        do {
            let image = try decode(data)
            try Task.checkCancellation()
            let result = try await worker.run(image: image, mode: mode, orientation: orientation)
            try Task.checkCancellation()
            guard runGeneration == generation else { return }
            findings = result
            runState = .succeeded
        } catch is CancellationError {
            guard runGeneration == generation else { return }
            runState = .cancelled
        } catch {
            guard runGeneration == generation else { return }
            let message = error.localizedDescription
            errorMessage = message
            runState = .failed(message)
        }
    }

    nonisolated private static func decodeImage(_ data: Data) throws -> VisionDecodedImage {
        return VisionDecodedImage(identifier: "selected-image", data: data)
    }

    nonisolated private static func performRequest(_ image: VisionDecodedImage, _ mode: VisionMode, _ orientation: VisionImageOrientation) throws -> [VisionFinding] {
        // Decode and create all Vision/UIKit objects inside the serial worker.
        // No CGImage or UIImage crosses the actor boundary.
        guard let decoded = UIImage(data: image.data), let cgImage = decoded.cgImage else {
            throw VisionAnalysisError.imageDecodeFailed
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation.cgImagePropertyOrientation, options: [:])

        switch mode {
        case .recognizedText:
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try handler.perform([request])
            let rawFindings = (request.results ?? []).compactMap { observation -> VisionFinding? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return .text(candidate.string, box: .init(observation.boundingBox), confidence: Double(candidate.confidence))
            }
            return VisionFinding.sortForReadingOrder(rawFindings).compactMap { finding in
                guard let box = finding.box else { return nil }
                return .text(finding.label, box: VisionDisplayGeometry.displayRect(box, orientation: .up), confidence: finding.confidence)
            }
        case .barcodes:
            let request = VNDetectBarcodesRequest()
            try handler.perform([request])
            return (request.results ?? []).map { observation in
                .barcode(payload: observation.payloadStringValue, symbology: observation.symbology.rawValue, box: VisionDisplayGeometry.displayRect(.init(observation.boundingBox), orientation: .up), confidence: Double(observation.confidence))
            }
        case .humanBodyPose:
            let request = VNDetectHumanBodyPoseRequest()
            try handler.perform([request])
            return try (request.results ?? []).enumerated().map { index, observation in
                let points = try observation.recognizedPoints(.all).map { name, point in
                    VisionDisplayGeometry.displayPoint(.init(name: String(describing: name), x: point.location.x, y: point.location.y, confidence: Double(point.confidence)), orientation: .up)
                }
                return .pose("Person \(index + 1)", points: points)
            }
        case .imageClassification:
            let request = VNClassifyImageRequest()
            try handler.perform([request])
            return (request.results ?? []).prefix(10).map { .classification($0.identifier, confidence: Double($0.confidence)) }
        }
    }
}

struct VisionExperienceView: View {
    @StateObject private var analyzer = VisionAnalyzing()
    @StateObject private var imageLoader = VisionImageLoader()
    @State private var selectedItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var selectedMode: VisionMode = .recognizedText
    @State private var orientation: VisionImageOrientation = .up
    @State private var selectionErrorMessage: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var analysisTask: Task<Void, Never>?

    var body: some View {
        let hasPreview = previewImage != nil
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExperienceIntro(experience: ExperienceCatalog[.vision])

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(hasPreview ? "Choose another image" : "Choose image", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent(for: .cameraVision))
                .onChange(of: selectedItem) { _, item in
                    loadTask?.cancel()
                    let loadGeneration = imageLoader.beginLoad()
                    selectionErrorMessage = nil
                    resetAnalysis()
                    imageData = nil
                    previewImage = nil
                    orientation = .up
                    guard let item else { return }
                    loadTask = Task { await load(item, generation: loadGeneration) }
                }

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .overlay { GeometryReader { geometry in overlay(for: geometry.size) } }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Picker("Vision mode", selection: $selectedMode) {
                    ForEach(VisionMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedMode) { _, _ in resetAnalysis() }

                Button {
                    guard let imageData else { return }
                    analysisTask?.cancel()
                    analysisTask = Task { await analyzer.analyze(data: imageData, mode: selectedMode, orientation: orientation) }
                } label: {
                    Label(analyzer.isRunning ? "Analyzing…" : "Analyze", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(imageData == nil || analyzer.isRunning)

                if let latency = analyzer.latency {
                    Text("Observed latency: \(latency, format: .number.precision(.fractionLength(2))) s")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                if let errorMessage = analyzer.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if let selectionErrorMessage {
                    Text(selectionErrorMessage).foregroundStyle(.red)
                }
                ForEach(analyzer.findings) { finding in
                    HStack(alignment: .firstTextBaseline) {
                        Text(finding.label).font(.headline)
                        if let payload = finding.payload { Text(payload).foregroundStyle(AppTheme.secondaryInk) }
                        Spacer()
                        if let confidence = finding.confidence { Text(confidence, format: .number.precision(.fractionLength(2))).font(.caption) }
                    }
                }
                if !analyzer.findings.isEmpty {
                    ShareLink(item: analyzer.findings.map(\.label).joined(separator: "\n")) {
                        Label("Share findings", systemImage: "square.and.arrow.up")
                    }
                }
                UsageInstructions(experience: ExperienceCatalog[.vision])
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Vision")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            loadTask?.cancel()
            analysisTask?.cancel()
        }
    }

    @ViewBuilder
    private func overlay(for size: CGSize) -> some View {
        ForEach(analyzer.findings) { finding in
            if let box = finding.box {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppTheme.accent(for: .cameraVision), lineWidth: 2)
                    .frame(width: box.width * size.width, height: box.height * size.height)
                    .position(x: (box.x + box.width / 2) * size.width, y: (box.y + box.height / 2) * size.height)
            }
            ForEach(finding.points, id: \.self) { point in
                Circle()
                    .fill(AppTheme.accent(for: .cameraVision))
                    .frame(width: 8, height: 8)
                    .position(x: point.x * size.width, y: point.y * size.height)
            }
        }
    }

    private func resetAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        analyzer.reset()
    }

    private func load(_ item: PhotosPickerItem?, generation: Int) async {
        guard let item else { return }
        await imageLoader.load(generation: generation) {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw VisionAnalysisError.imageDecodeFailed
            }
            return VisionLoadedImage(identifier: "selected-image", data: data, orientation: VisionImageOrientation(image.imageOrientation))
        }
        guard !Task.isCancelled else { return }
        guard imageLoader.isCurrent(generation: generation) else { return }
        guard let selected = imageLoader.selected else {
            selectionErrorMessage = imageLoader.errorMessage
            return
        }
        imageData = selected.data
        previewImage = UIImage(data: selected.data)
        orientation = selected.orientation
        selectionErrorMessage = nil
    }
}
