import CoreImage
import CoreVideo
import PhotosUI
import SwiftUI
import UIKit

struct VisionSegmentationView: View {
    @StateObject private var model = VisionSegmentationExperience()
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var image: UIImage?
    @State private var orientation: VisionImageOrientation = .up
    @State private var loadTask: Task<Void, Never>?
    @State private var interaction: Interaction = .point
    @State private var boxStart: VisionSegmentationPoint?

    private enum Interaction: String, CaseIterable, Identifiable {
        case point, box, scribble, include, exclude
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Interactive Vision Segmentation")
                    .font(.title2.bold())
                Text("Select an image, choose a seed, then refine one mask with positive or negative points.")
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(image == nil ? "Choose image" : "Choose another image", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .onChange(of: pickerItem) { _, item in load(item) }

                if let image {
                    imageCanvas(image)
                }

                Picker("Interaction", selection: $interaction) {
                    ForEach(Interaction.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Quality", selection: Binding(get: { model.quality }, set: { model.quality = $0 })) {
                    ForEach(VisionSegmentationQuality.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button(model.assetState == .ready ? "Assets ready" : "Download Vision assets") {
                        model.startDownloadAssets()
                    }
                    .disabled(model.assetState == .downloading)
                    Button("Segment") { runSegmentation() }
                        .buttonStyle(.borderedProminent)
                        .disabled(imageData == nil || model.assetState != .ready || model.phase == .running)
                }
                if model.assetState == .downloading || model.phase == .running {
                    ProgressView(value: model.progress)
                    Button("Cancel") {
                        model.cancel()
                    }
                    .buttonStyle(.bordered)
                }
                if let mask = model.output?.mask, let maskImage = makeMaskImage(mask) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PixelBuffer mask")
                            .font(.headline)
                        Image(uiImage: maskImage)
                            .resizable()
                            .scaledToFit()
                            .opacity(0.72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                if let latency = model.latency {
                    Text("Mask latency: \(latency, format: .number.precision(.fractionLength(2))) s")
                        .font(.footnote)
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                Button("Reset") { model.reset() }
                    .buttonStyle(.bordered)
                UsageInstructions(experience: ExperienceCatalog[.vision])
            }
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Vision Segmentation")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { loadTask?.cancel(); model.cancel() }
    }

    @ViewBuilder
    private func imageCanvas(_ image: UIImage) -> some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { overlayGeometry in
                        ForEach(model.corrections.indices, id: \.self) { index in
                            let correction = model.corrections[index]
                            let point: VisionSegmentationPoint = switch correction {
                            case let .included(point), let .excluded(point): point
                            }
                            Circle()
                                .fill(correctionColor(correction))
                                .frame(width: 12, height: 12)
                                .position(x: point.x * overlayGeometry.size.width, y: point.y * overlayGeometry.size.height)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
                .gesture(drawingGesture(in: geometry.size))
        }
        .aspectRatio(image.size, contentMode: .fit)
        .frame(maxHeight: 420)
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: interaction == .point || interaction == .include || interaction == .exclude ? 0 : 1)
            .onChanged { value in
                let point = normalized(value.location, in: size)
                switch interaction {
                case .point: model.seed = .point(point)
                case .scribble:
                    if case let .scribble(points) = model.seed {
                        if points.last != point { model.seed = .scribble(points + [point]) }
                    } else { model.seed = .scribble([point]) }
                case .box: boxStart = boxStart ?? normalized(value.startLocation, in: size)
                case .include, .exclude: break
                }
            }
            .onEnded { value in
                let point = normalized(value.location, in: size)
                switch interaction {
                case .point: model.seed = .point(point)
                case .include: model.addIncludedPoint(point)
                case .exclude: model.addExcludedPoint(point)
                case .scribble: break
                case .box:
                    let start = boxStart ?? normalized(value.startLocation, in: size)
                    model.seed = .box(.init(
                        x: min(start.x, point.x), y: min(start.y, point.y),
                        width: abs(point.x - start.x), height: abs(point.y - start.y)
                    ))
                    boxStart = nil
                }
            }
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> VisionSegmentationPoint {
        .init(x: min(max(location.x / max(size.width, 1), 0), 1), y: min(max(location.y / max(size.height, 1), 0), 1))
    }

    private func correctionColor(_ correction: VisionSegmentationCorrection) -> Color {
        switch correction { case .included: .green; case .excluded: .red }
    }

    private func makeMaskImage(_ mask: CVReadOnlyPixelBuffer) -> UIImage? {
        mask.withUnsafeBuffer { buffer in
            let context = CIContext(options: nil)
            let image = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }

    private func load(_ item: PhotosPickerItem?) {
        loadTask?.cancel()
        guard let item else { return }
        loadTask = Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
            await MainActor.run {
                self.imageData = data
                self.image = image
                self.orientation = VisionImageOrientation(image.imageOrientation)
                self.model.reset()
            }
        }
    }

    private func runSegmentation() {
        guard let imageData, let image else { return }
        model.startSegment(imageData: imageData, imageSize: image.size, orientation: orientation)
    }
}
