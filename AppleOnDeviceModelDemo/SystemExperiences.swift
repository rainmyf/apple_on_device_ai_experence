import Foundation
import FoundationModels
import SwiftUI
import UIKit

/// Describes where an integration is executed. A system-owned experience is
/// intentionally never represented as a direct Foundation Models run.
enum SystemExperienceExecutionKind: String, Equatable, Sendable {
    case directModel
    case systemUI
    case systemIntegration
    case deterministicAppAction
    case setupGuide

    static let systemUIOnly = Self.systemUI
}

struct SystemExperiencePageContent: Equatable, Sendable {
    let id: ExperienceID
    let framework: String
    let entryPoint: String
    let executionKind: SystemExperienceExecutionKind
    let instructions: String
    let limitations: String
    let usage: String
    let status: CapabilityAvailability

    var entry: String { entryPoint }
    var limitation: String { limitations }
}

enum SystemExperienceContent {
    static func content(
        for id: ExperienceID,
        adapterSetup: FoundationModelAdapterSetup? = nil
    ) -> SystemExperiencePageContent {
        switch id {
        case .writingTools:
            SystemExperiencePageContent(
                id: id,
                framework: "UIKit",
                entryPoint: "UITextView / SwiftUI TextEditor with UITextInputTraits.writingToolsBehavior",
                executionKind: .systemUI,
                instructions: "Edit the sample text in the field. Writing Tools is supplied by the system for supported editable text views; this page does not call a model directly.",
                limitations: "The system decides availability, language support, and which Writing Tools actions appear. UIWritingToolsCoordinator is only needed for a custom text view; UITextView and TextEditor already provide the public integration.",
                usage: "Tap the editable text and use the system edit menu or Writing Tools affordance when it is offered.",
                status: CapabilityAvailability(requirement: .systemUI)
            )
        case .genmoji:
            SystemExperiencePageContent(
                id: id,
                framework: "UIKit",
                entryPoint: "UITextInput / UITextView with the system emoji and Genmoji keyboard",
                executionKind: .systemUI,
                instructions: "Place the cursor in the editable field and choose the system emoji keyboard. Genmoji insertion is owned by the keyboard and arrives through the text-input system.",
                limitations: "The installed SDK exposes no public Genmoji generation or prompt API. This app cannot manufacture a Genmoji, force the keyboard, or claim that a generated image was produced.",
                usage: "Tap the field, switch to the emoji keyboard if available, and observe inserted text or adaptive image glyph content from the system.",
                status: CapabilityAvailability(requirement: .systemUI)
            )
        case .smartReply:
            SystemExperiencePageContent(
                id: id,
                framework: "UIKit",
                entryPoint: "UIConversationContext + UITextInput.insertInputSuggestion(_:), with UISmartReplySuggestion from the system",
                executionKind: .systemIntegration,
                instructions: "This page provides a conversation-aware UITextView boundary. The keyboard may provide a UISmartReplySuggestion; the app receives it through UITextInput and does not generate the suggestion itself.",
                limitations: "There is no public standalone Smart Reply generator in the installed SDK. Availability and suggestions are controlled by the system keyboard and conversation context.",
                usage: "Edit the conversation-aware field and use the keyboard when it offers a Smart Reply suggestion.",
                status: CapabilityAvailability(requirement: .systemUI)
            )
        case .appIntents:
            SystemExperiencePageContent(
                id: id,
                framework: "AppIntents",
                entryPoint: "AppIntent.perform() → DescribeDemoCapabilityIntent.perform()",
                executionKind: .deterministicAppAction,
                instructions: "The intent returns a fixed, harmless instruction string for the supplied capability name. It demonstrates an App Intent contract, not a model invocation.",
                limitations: "App Intents expose typed app actions to system surfaces; they do not grant this app access to Siri's private models or internal reasoning.",
                usage: "Provide a capability name and invoke the intent from a supported system surface or test harness.",
                status: CapabilityAvailability(requirement: .none)
            )
        case .customAdapter:
            SystemExperiencePageContent(
                id: id,
                framework: "FoundationModels",
                entryPoint: "SystemLanguageModel.Adapter(fileURL:) → compile() → SystemLanguageModel(adapter:)",
                executionKind: .setupGuide,
                instructions: "Add a compatible .fmadapter asset and the required Foundation Models adapter entitlement before attempting compilation. This sample reports setup state and does not load a missing asset.",
                limitations: "An adapter is executable only when the entitlement and a compatible .fmadapter asset are both present. The installed public API does not provide a fallback adapter or a way to bypass either requirement.",
                usage: "Inspect the setup status first. Configure the signed entitlement and asset in the app target before attempting FoundationModelAdapterBoundary.makeModel(fileURL:).",
                status: adapterSetup?.availability ?? FoundationModelAdapterSetup.unconfigured.availability
            )
        default:
            SystemExperiencePageContent(
                id: id,
                framework: "System",
                entryPoint: "No system integration for this route",
                executionKind: .setupGuide,
                instructions: "This route is not a Task 12 system integration.",
                limitations: "No system integration is exposed here.",
                usage: "Return to the capability gallery.",
                status: CapabilityAvailability(requirement: .systemUI)
            )
        }
    }
}

enum FoundationModelAdapterBoundaryError: LocalizedError, Equatable, Sendable {
    case entitlementRequired
    case assetRequired
    case incompatibleAsset
    case externalSetupVerificationRequired

    var errorDescription: String? {
        switch self {
        case .entitlementRequired:
            "The Foundation Models adapter entitlement is required."
        case .assetRequired:
            "Add a compatible .fmadapter asset before loading an adapter."
        case .incompatibleAsset:
            "The selected asset is not a .fmadapter file."
        case .externalSetupVerificationRequired:
            "Adapter setup must be verified by an Xcode-signed build on an eligible device; this app does not claim readiness."
        }
    }
}

protocol FoundationModelAdapterEntitlementChecking: Sendable {
    var isEntitled: Bool { get }
}

/// The iOS 26 SDK exposes no public API for reading this entitlement at
/// runtime. This type is retained as an explicit negative boundary so the app
/// never treats Info.plist, a caller-provided flag, or an unsigned probe as
/// proof of adapter capability. Xcode signing is the source of truth.
struct SignedFoundationModelAdapterEntitlementChecker: FoundationModelAdapterEntitlementChecking, Sendable {
    static let entitlementKey = "com.apple.developer.foundation-model-adapter"

    var isEntitled: Bool { false }
}

struct FoundationModelAdapterSetup: Equatable, Sendable {
    let entitlementDeclared: Bool
    let assetURL: URL?
    let assetExists: Bool

    init(entitlementDeclared: Bool, assetURL: URL?, assetExists: Bool? = nil) {
        self.entitlementDeclared = entitlementDeclared
        self.assetURL = assetURL
        self.assetExists = assetExists ?? assetURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    static let unconfigured = FoundationModelAdapterSetup(entitlementDeclared: false, assetURL: nil)

    /// Always false: readiness requires an Xcode-signed entitlement and a
    /// compatible asset, neither of which the public runtime API can verify.
    var isExecutable: Bool { false }

    var status: CapabilityStatus { .setupRequired }

    var gateDetail: String {
        if !entitlementDeclared {
            return "Setup required: the signed com.apple.developer.foundation-model-adapter entitlement is absent; add a compatible .fmadapter asset to the app bundle."
        }
        guard let assetURL else {
            return "Setup required: add an existing compatible .fmadapter asset to the app bundle."
        }
        guard assetURL.pathExtension.caseInsensitiveCompare("fmadapter") == .orderedSame else {
            return "Setup required: the selected adapter asset must use the .fmadapter extension."
        }
        guard assetExists else {
            return "Setup required: the selected .fmadapter asset does not exist."
        }
        return "External setup inputs may be present, but only an Xcode-signed entitlement and a compatible .fmadapter asset can enable this route. The app cannot verify entitlement or adapter compatibility; verify the public Adapter(fileURL:) and compile() path in a signed eligible-device build."
    }

    var availability: CapabilityAvailability {
        CapabilityAvailability(status: status, detail: gateDetail)
    }
}

enum FoundationModelAdapterBoundary {
    static let defaultEntitlementChecker: any FoundationModelAdapterEntitlementChecking = SignedFoundationModelAdapterEntitlementChecker()

    static func inspect(
        bundle: Bundle = .main,
        entitlementChecker: any FoundationModelAdapterEntitlementChecking = SignedFoundationModelAdapterEntitlementChecker(),
        assetURLs: [URL]? = nil
    ) -> FoundationModelAdapterSetup {
        // Keep this inspection deliberately setup-only. The installed SDK has
        // no public runtime entitlement-reading API, so even an injected probe
        // cannot be treated as signed-task evidence by the app.
        _ = entitlementChecker
        let assets = assetURLs ?? bundle.urls(forResourcesWithExtension: "fmadapter", subdirectory: nil) ?? []
        let asset = assets.first
        return FoundationModelAdapterSetup(
            entitlementDeclared: false,
            assetURL: asset
        )
    }

    static func loadIfReady<Value: Sendable>(
        fileURL: URL,
        entitlementChecker: any FoundationModelAdapterEntitlementChecking = SignedFoundationModelAdapterEntitlementChecker(),
        loader: @escaping @Sendable (URL) async throws -> Value
    ) async throws -> Value {
        guard entitlementChecker.isEntitled else {
            throw FoundationModelAdapterBoundaryError.entitlementRequired
        }
        guard fileURL.pathExtension.caseInsensitiveCompare("fmadapter") == .orderedSame else {
            throw FoundationModelAdapterBoundaryError.incompatibleAsset
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FoundationModelAdapterBoundaryError.assetRequired
        }
        // There is no public runtime entitlement probe on this SDK. Do not
        // run an injected or placeholder loader and accidentally present it as
        // production adapter execution.
        throw FoundationModelAdapterBoundaryError.externalSetupVerificationRequired
    }

    @available(iOS 26.0, *)
    static func makeModel(
        fileURL: URL,
        entitlementChecker: any FoundationModelAdapterEntitlementChecking = SignedFoundationModelAdapterEntitlementChecker()
    ) async throws -> SystemLanguageModel {
        _ = fileURL
        _ = entitlementChecker
        throw FoundationModelAdapterBoundaryError.externalSetupVerificationRequired
    }
}

struct WritingToolsExperienceView: View {
    private let content = SystemExperienceContent.content(for: .writingTools)
    @State private var text = "A short note ready for system writing tools."

    var body: some View {
        systemPage(content) {
            TextEditor(text: $text)
                .writingToolsBehavior(.complete)
                .writingToolsAffordanceVisibility(.visible)
                .frame(minHeight: 170)
                .padding(10)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                }
        }
    }
}

struct GenmojiExperienceView: View {
    private let content = SystemExperienceContent.content(for: .genmoji)
    @State private var text = "Try the system emoji keyboard here."

    var body: some View {
        systemPage(content) {
            TextField("Editable text input", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .padding(14)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                }
        }
    }
}

struct SmartReplyExperienceView: View {
    private let content = SystemExperienceContent.content(for: .smartReply)
    @State private var text = "Conversation context is attached to this editable field."
    @State private var systemSuggestion: String?

    var body: some View {
        systemPage(content) {
            SmartReplyTextView(text: $text, systemSuggestion: $systemSuggestion)
                .frame(minHeight: 150)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                }
            ResultSurface(
                title: "System suggestion",
                text: systemSuggestion ?? "Waiting for the system keyboard to provide a Smart Reply suggestion."
            )
        }
    }
}

enum SmartReplyConversationContextFactory {
    @available(iOS 18.4, *)
    static func make() -> UIConversationContext {
        let context = UIMessageConversationContext()
        context.threadIdentifier = "apple-on-device-demo"
        context.selfIdentifiers = ["me"]
        context.responsePrimaryRecipientIdentifiers = ["other-participant"]
        context.participantNameByIdentifier = [
            "me": PersonNameComponents(givenName: "Demo", familyName: "User"),
            "other-participant": PersonNameComponents(givenName: "Conversation", familyName: "Partner")
        ]

        let incoming = UIMessageConversationContext.MessageEntry()
        incoming.text = "Can you review the system integration demo?"
        incoming.senderIdentifier = "other-participant"
        incoming.sentDate = Date(timeIntervalSince1970: 1_700_000_000)
        incoming.entryIdentifier = "message-1"
        incoming.primaryRecipientIdentifiers = ["me"]
        incoming.dataKind = .text
        incoming.wasSentBySelf = false

        let outgoing = UIMessageConversationContext.MessageEntry()
        outgoing.text = "Yes, I am checking the public API boundary now."
        outgoing.senderIdentifier = "me"
        outgoing.sentDate = Date(timeIntervalSince1970: 1_700_000_060)
        outgoing.entryIdentifier = "message-2"
        outgoing.primaryRecipientIdentifiers = ["other-participant"]
        outgoing.dataKind = .text
        outgoing.wasSentBySelf = true

        context.entries = [incoming, outgoing]
        return context
    }
}

private struct SmartReplyTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var systemSuggestion: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, systemSuggestion: $systemSuggestion)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.text = text
        view.adjustsFontForContentSizeCategory = true
        if #available(iOS 18.4, *) {
            view.conversationContext = SmartReplyConversationContextFactory.make()
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            view.text = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        private let systemSuggestion: Binding<String?>

        init(text: Binding<String>, systemSuggestion: Binding<String?>) {
            self.text = text
            self.systemSuggestion = systemSuggestion
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        @available(iOS 18.4, *)
        func textView(_ textView: UITextView, insertInputSuggestion inputSuggestion: UIInputSuggestion) {
            guard let suggestion = inputSuggestion as? UISmartReplySuggestion else { return }
            systemSuggestion.wrappedValue = suggestion.smartReply
        }
    }
}

struct AppIntentsExperienceView: View {
    private let content = SystemExperienceContent.content(for: .appIntents)
    @State private var capability = "Writing Tools"

    var body: some View {
        systemPage(content) {
            TextField("Capability name", text: $capability)
                .padding(14)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                }
            Text("DescribeDemoCapabilityIntent is available to system invocation surfaces; this sample page does not fabricate an invocation result.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }
}

struct CustomAdapterExperienceView: View {
    private let setup = FoundationModelAdapterBoundary.inspect()

    var body: some View {
        systemPage(SystemExperienceContent.content(for: .customAdapter, adapterSetup: setup)) {
            ResultSurface(
                title: "Setup status",
                text: setup.gateDetail
            )
        }
    }
}

private func systemPage<Content: View>(
    _ content: SystemExperiencePageContent,
    @ViewBuilder integration: () -> Content
) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ExperienceIntro(experience: ExperienceCatalog[content.id])
            integration()
            ResultSurface(title: "Status", text: content.status.detail)
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(content.usage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                Text("Boundary: \(content.entryPoint)")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Text(content.instructions)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
            Text("Limitations: \(content.limitations)")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .padding(20)
    }
    .scrollIndicators(.hidden)
    .background(AppTheme.background.ignoresSafeArea())
    .navigationTitle(content.idTitle)
    .navigationBarTitleDisplayMode(.inline)
}

private extension SystemExperiencePageContent {
    var idTitle: String { ExperienceCatalog[id].title }
}
