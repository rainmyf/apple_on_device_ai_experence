@preconcurrency import ImagePlayground
import Combine
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

enum ImageCreatorBoundaryError: LocalizedError, Equatable, Sendable {
    case unavailable
    case noStyles
    case invalidStyle
    case creationFailed
    case noImage

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The image creator is unavailable on this device."
        case .noStyles:
            "No image styles are available on this device."
        case .invalidStyle:
            "Choose one of the styles reported by ImageCreator."
        case .creationFailed:
            "The image could not be created."
        case .noImage:
            "The image creator returned no image."
        }
    }
}

enum ImageCreatorAvailability: Equatable, Sendable {
    case checking
    case available
    case unavailable(String)
}

enum ImageCreatorRunState: Equatable, Sendable {
    case idle
    case running
    case succeeded
    case failed(String)
    case cancelled
}

struct ImageCreatorStyleOption: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    static let animation = Self(id: "animation", title: "Animation")
    static let illustration = Self(id: "illustration", title: "Illustration")
    static let sketch = Self(id: "sketch", title: "Sketch")
}

enum ImageCreatorCreationVariety: String, Equatable, Sendable {
    case automatic
    case high
    case low
}

enum ImageCreatorPersonalization: String, Equatable, Sendable {
    case automatic
    case enabled
    case disabled
}

struct ImageCreatorConfiguration: Equatable, Sendable {
    let creationVariety: ImageCreatorCreationVariety
    let personalization: ImageCreatorPersonalization

    static let `default` = Self(creationVariety: .automatic, personalization: .automatic)

    init(
        creationVariety: ImageCreatorCreationVariety = .automatic,
        personalization: ImageCreatorPersonalization = .automatic
    ) {
        self.creationVariety = creationVariety
        self.personalization = personalization
    }
}

struct ImageCreatorRequest: Equatable, Sendable {
    let prompt: String
    let styleID: String
    let limit: Int
    let configuration: ImageCreatorConfiguration
}

struct ImagePlaygroundPresentationState: Equatable {
    var prompt = ""
    var isPresented = false
    var completedURL: URL?
    var errorMessage: String?

    mutating func beginPresentation() {
        completedURL = nil
        errorMessage = nil
        isPresented = true
    }

    mutating func recordCompletion(_ url: URL) {
        completedURL = url
        isPresented = false
    }

    mutating func recordCancellation() {
        completedURL = nil
        errorMessage = "Image Playground was cancelled."
        isPresented = false
    }

    mutating func recordFailure(_ message: String) {
        completedURL = nil
        errorMessage = message
        isPresented = false
    }
}

private struct SendableImagePlaygroundConcepts: @unchecked Sendable {
    let values: [ImagePlaygroundConcept]
}

/// A framework-boundary value. Core Graphics stays out of the view model's
/// decision logic, while the actual image remains available for rendering.
struct GeneratedImage: Identifiable, @unchecked Sendable {
    let identifier: String
    let cgImage: CGImage

    var id: String { identifier }

    init(identifier: String = UUID().uuidString, cgImage: CGImage) {
        self.identifier = identifier
        self.cgImage = cgImage
    }
}

protocol ImageCreatorServing: AnyObject, Sendable {
    var availableStyles: [ImageCreatorStyleOption] { get }
    func images(for request: ImageCreatorRequest) -> AsyncThrowingStream<GeneratedImage, Error>
}

typealias ImageCreatorFactory = @Sendable () async throws -> any ImageCreatorServing

@MainActor
final class ImageCreatorViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var availability: ImageCreatorAvailability = .checking
    @Published private(set) var styles: [ImageCreatorStyleOption] = []
    @Published var selectedStyleID: String?
    @Published private(set) var output: GeneratedImage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var latency: TimeInterval?
    @Published private(set) var isRunning = false
    @Published private(set) var runState: ImageCreatorRunState = .idle

    private let creatorFactory: ImageCreatorFactory
    private let clock: () -> TimeInterval
    private var creator: (any ImageCreatorServing)?
    private var activeTask: Task<Void, Never>?
    private var activeRunToken: UUID?
    private var activeStartedAt: TimeInterval?

    init(
        creatorFactory: @escaping ImageCreatorFactory = ImageCreatorViewModel.makeSystemCreator,
        clock: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    ) {
        self.creatorFactory = creatorFactory
        self.clock = clock
    }

    var availabilityDetail: String {
        switch availability {
        case .checking:
            "Checking ImageCreator availability…"
        case .available:
            "ImageCreator is available and reports \(styles.count) style\(styles.count == 1 ? "" : "s")."
        case .unavailable(let message):
            message
        }
    }

    func load() async {
        guard availability == .checking else { return }

        do {
            let creator = try await creatorFactory()
            guard !Task.isCancelled else { return }
            let styles = creator.availableStyles
            guard !Task.isCancelled else { return }
            guard !styles.isEmpty else { throw ImageCreatorBoundaryError.noStyles }
            self.creator = creator
            self.styles = styles
            selectedStyleID = styles[0].id
            availability = .available
        } catch {
            if Task.isCancelled || error is CancellationError {
                return
            }
            availability = .unavailable(Self.message(for: error))
        }
    }

    func generate() async {
        guard !isRunning else {
            errorMessage = "An image generation run is already in progress."
            return
        }
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            publishValidationError("Enter a prompt before generating an image.")
            return
        }
        guard availability == .available, let creator else {
            publishValidationError(availabilityDetail)
            return
        }
        guard let selectedStyleID,
              styles.contains(where: { $0.id == selectedStyleID }) else {
            publishValidationError(ImageCreatorBoundaryError.invalidStyle.localizedDescription)
            return
        }

        output = nil
        errorMessage = nil
        latency = nil
        isRunning = true
        runState = .running
        let token = UUID()
        let startedAt = clock()
        activeRunToken = token
        activeStartedAt = startedAt
        let request = ImageCreatorRequest(
            prompt: prompt,
            styleID: selectedStyleID,
            limit: 1,
            configuration: .default
        )
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performGeneration(
                request,
                creator: creator,
                token: token,
                startedAt: startedAt
            )
        }
        activeTask = task
        await task.value
        if activeRunToken == token {
            activeTask = nil
        }
    }

    func cancel() {
        guard isRunning else { return }
        activeTask?.cancel()
        if let startedAt = activeStartedAt {
            latency = clock() - startedAt
        }
        isRunning = false
        errorMessage = nil
        runState = .cancelled
        activeRunToken = nil
        activeStartedAt = nil
        activeTask = nil
    }

    private func performGeneration(
        _ request: ImageCreatorRequest,
        creator: any ImageCreatorServing,
        token: UUID,
        startedAt: TimeInterval
    ) async {
        defer {
            if activeRunToken == token {
                latency = clock() - startedAt
                isRunning = false
                activeRunToken = nil
                activeStartedAt = nil
                activeTask = nil
            }
        }

        do {
            var firstImage: GeneratedImage?
            for try await image in creator.images(for: request) {
                try Task.checkCancellation()
                firstImage = image
                break
            }
            try Task.checkCancellation()
            guard let firstImage else { throw ImageCreatorBoundaryError.noImage }
            guard activeRunToken == token else { throw CancellationError() }
            output = firstImage
            runState = .succeeded
        } catch {
            if error is CancellationError || Self.isFrameworkCancellation(error) {
                if activeRunToken == token {
                    runState = .cancelled
                    errorMessage = nil
                }
                return
            }
            guard activeRunToken == token else { return }
            let message = Self.message(for: error)
            errorMessage = message
            runState = .failed(message)
        }
    }

    private func publishValidationError(_ message: String) {
        output = nil
        errorMessage = message
        latency = nil
        runState = .failed(message)
    }

    private static func message(for error: Error) -> String {
        if let boundaryError = error as? ImageCreatorBoundaryError {
            return boundaryError.localizedDescription
        }
        return error.localizedDescription
    }

    private static func isFrameworkCancellation(_ error: Error) -> Bool {
        guard let error = error as? ImageCreator.Error else { return false }
        return error == .creationCancelled
    }

    private static func makeSystemCreator() async throws -> any ImageCreatorServing {
        guard #available(iOS 18.4, *) else {
            throw ImageCreatorBoundaryError.unavailable
        }
        return try await SystemImageCreatorAdapter()
    }
}

@available(iOS 18.4, *)
private final class SystemImageCreatorAdapter: ImageCreatorServing, @unchecked Sendable {
    private let creator: ImageCreator
    private let stylesByID: [String: ImagePlaygroundStyle]

    init() async throws {
        let creator = try await ImageCreator()
        self.creator = creator
        self.stylesByID = Dictionary(uniqueKeysWithValues: creator.availableStyles.map { ($0.id, $0) })
    }

    var availableStyles: [ImageCreatorStyleOption] {
        creator.availableStyles.map { ImageCreatorStyleOption(id: $0.id, title: Self.title(for: $0.id)) }
    }

    func images(for request: ImageCreatorRequest) -> AsyncThrowingStream<GeneratedImage, Error> {
        guard let style = stylesByID[request.styleID] else {
            return AsyncThrowingStream { $0.finish(throwing: ImageCreatorBoundaryError.invalidStyle) }
        }
        let concepts = SendableImagePlaygroundConcepts(values: [ImagePlaygroundConcept.text(request.prompt)])
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if #available(iOS 26.4, *) {
                        var options = ImagePlaygroundOptions()
                        options.creationVariety = Self.creationVariety(from: request.configuration.creationVariety)
                        options.personalization = Self.personalization(from: request.configuration.personalization)
                        for try await created in creator.images(
                            for: concepts.values,
                            style: style,
                            options: options,
                            limit: request.limit
                        ) {
                            continuation.yield(GeneratedImage(cgImage: created.cgImage))
                        }
                    } else {
                        for try await created in creator.images(
                            for: concepts.values,
                            style: style,
                            limit: request.limit
                        ) {
                            continuation.yield(GeneratedImage(cgImage: created.cgImage))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func title(for id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    @available(iOS 26.4, *)
    private static func creationVariety(
        from variety: ImageCreatorCreationVariety
    ) -> ImagePlaygroundOptions.CreationVariety {
        switch variety {
        case .automatic: .automatic
        case .high: .high
        case .low: .low
        }
    }

    @available(iOS 26.4, *)
    private static func personalization(
        from personalization: ImageCreatorPersonalization
    ) -> ImagePlaygroundOptions.Personalization {
        switch personalization {
        case .automatic: .automatic
        case .enabled: .enabled
        case .disabled: .disabled
        }
    }
}

struct ImageCreatorExperienceView: View {
    @StateObject private var viewModel: ImageCreatorViewModel

    init(viewModel: ImageCreatorViewModel = ImageCreatorViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ExperienceIntro(experience: ExperienceCatalog[.imageCreator])

                VStack(alignment: .leading, spacing: 8) {
                    Text("Availability")
                        .font(.headline)
                    Text(viewModel.availabilityDetail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text(viewModel.availability == .available ? "Ready" : "Unavailable or checking")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.availability == .available ? .green : .orange)
                }

                TextField("Describe what you want to create", text: $viewModel.input, axis: .vertical)
                    .lineLimit(4...8)
                    .padding(14)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if !viewModel.styles.isEmpty {
                    Picker("Style", selection: $viewModel.selectedStyleID) {
                        ForEach(viewModel.styles) { style in
                            Text(style.title).tag(Optional(style.id))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Button("Generate") {
                        Task { await viewModel.generate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.availability != .available || viewModel.isRunning)
                    if viewModel.isRunning {
                        Button("Cancel", action: viewModel.cancel)
                            .buttonStyle(.bordered)
                    }
                }

                if let image = viewModel.output {
                    Image(uiImage: UIImage(cgImage: image.cgImage))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    ResultSurface(
                        title: "Result",
                        text: viewModel.errorMessage ?? "No image has been returned by ImageCreator."
                    )
                }

                if let latency = viewModel.latency {
                    Text("Last run: \(latency, specifier: "%.3f") s · \(viewModel.runState.displayName)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                UsageInstructions(experience: ExperienceCatalog[.imageCreator])
                Text("The app renders only images returned by ImageCreator; it does not fabricate a preview or own a generation model.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Image Creator")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onDisappear { viewModel.cancel() }
    }
}

struct ImagePlaygroundExperienceView: View {
    @State private var presentation = ImagePlaygroundPresentationState()

    private var concepts: [ImagePlaygroundConcept] {
        let prompt = presentation.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? [] : [.text(prompt)]
    }

    private var isAvailable: Bool {
        if #available(iOS 18.1, *) {
            return ImagePlaygroundViewController.isAvailable
        }
        return false
    }

    private var availabilityDetail: String {
        isAvailable
            ? "Image Playground is available. The next screen is provided and owned by the system."
            : "Image Playground is unavailable on this device. This page remains readable, but the system experience cannot be opened."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ExperienceIntro(experience: ExperienceCatalog[.imagePlayground])
                VStack(alignment: .leading, spacing: 8) {
                    Text("Availability")
                        .font(.headline)
                    Text(availabilityDetail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text(isAvailable ? "Ready to present system UI" : "Unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isAvailable ? .green : .orange)
                }

                TextField("Describe an image for Image Playground", text: $presentation.prompt, axis: .vertical)
                    .lineLimit(4...8)
                    .padding(14)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button("Open Image Playground") {
                    guard !concepts.isEmpty else {
                        presentation.recordFailure("Enter a prompt before opening Image Playground.")
                        return
                    }
                    guard isAvailable else {
                        presentation.recordFailure("Image Playground is unavailable on this device.")
                        return
                    }
                    presentation.beginPresentation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isAvailable)

                if let completedURL = presentation.completedURL {
                    ResultSurface(title: "System result", text: "Image Playground returned: \(completedURL.lastPathComponent)")
                } else {
                    ResultSurface(
                        title: "System-owned experience",
                        text: presentation.errorMessage ?? "No result has been returned. The generated image UI belongs to Image Playground."
                    )
                }
                UsageInstructions(experience: ExperienceCatalog[.imagePlayground])
            }
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Image Playground")
        .navigationBarTitleDisplayMode(.inline)
        .imagePlaygroundSheet(
            isPresented: $presentation.isPresented,
            concepts: concepts,
            onCompletion: { url in presentation.recordCompletion(url) },
            onCancellation: { presentation.recordCancellation() }
        )
    }
}

private extension ImageCreatorRunState {
    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}
