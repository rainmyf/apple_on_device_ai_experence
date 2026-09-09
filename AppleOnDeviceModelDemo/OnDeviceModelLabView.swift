import SwiftUI
import UniformTypeIdentifiers

struct OnDeviceModelLabView: View {
    @StateObject private var lab: OnDeviceModelLab
    @State private var showingImporter = false

    init(lab: OnDeviceModelLab = OnDeviceModelLab()) {
        _lab = StateObject(wrappedValue: lab)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Open On-device Model Lab")
                    .font(.title2.weight(.semibold))
                Text("Send a prompt when you are ready. The session stays on device and continues across turns.")
                    .foregroundStyle(AppTheme.secondaryInk)

                profilePicker
                capabilityCard

                if lab.selectedProfile == .image {
                    attachmentCard
                }

                TextEditor(text: $lab.text)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.secondaryInk.opacity(0.2)))
                    .disabled(lab.isRunning)

                HStack {
                    Button(lab.isRunning ? "Running…" : "Send") {
                        Task { await lab.send() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!lab.canSend)

                    if lab.isRunning {
                        Button("Cancel") { lab.cancel() }
                            .buttonStyle(.bordered)
                    }

                    Spacer()
                    if let latency = lab.latency {
                        Text(String(format: "%.0f ms", latency * 1000))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }

                if let error = lab.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if lab.wasCancelled {
                    Label("Request cancelled", systemImage: "xmark.circle")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                }

                conversation
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("Model Lab")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                do {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw CocoaError(.fileReadNoPermission)
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let localURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: localURL)
                    lab.imageURL = localURL
                } catch {
                    lab.imageURL = nil
                    lab.setError("Unable to import image: \(error.localizedDescription)")
                }
            }
        }
        .onDisappear { lab.cancel() }
    }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dynamic profile")
                .font(.headline)
            Picker("Profile", selection: $lab.selectedProfile) {
                ForEach(OnDeviceModelProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            .disabled(lab.isRunning)
            Text(lab.selectedProfile.summary)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SystemLanguageModel.default")
                .font(.headline)
            Text("Availability: " + lab.capabilities.availability.rawValue)
            Text("Variant: " + lab.capabilities.variant)
            Text("Capabilities: " + lab.capabilities.capabilityNames.joined(separator: ", ").ifEmpty("none"))
            Text("Context: " + String(lab.capabilities.contextSize) + " tokens · " + String(lab.contextTurnCount) + " turns")
        }
        .font(.footnote)
        .foregroundStyle(AppTheme.secondaryInk)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }

    private var attachmentCard: some View {
        HStack {
            Image(systemName: "photo")
            Text(lab.imageURL?.lastPathComponent ?? "No image attached")
                .lineLimit(1)
            Spacer()
            Button("Choose image") { showingImporter = true }
                .buttonStyle(.bordered)
        }
        .font(.footnote)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context · " + String(lab.contextTurnCount) + " turns")
                .font(.headline)
            ForEach(lab.turns) { turn in
                VStack(alignment: .leading, spacing: 5) {
                    Text(turn.request.text)
                        .font(.subheadline.weight(.semibold))
                    Text(turn.response)
                        .textSelection(.enabled)
                    if !turn.toolNames.isEmpty {
                        Label("Tool calls: " + turn.toolNames.joined(separator: ", "), systemImage: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    Text(String(format: "%.0f ms", turn.latency * 1000))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
