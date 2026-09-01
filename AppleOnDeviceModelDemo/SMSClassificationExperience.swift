import SwiftUI

enum SMSClassificationExperienceCopy {
    static let title = "SMS Classification"
    static let intro = "Use an on-device language model to classify one SMS and annotate entities in the original text."
    static let randomSample = "Random SMS"
    static let run = "Run On-device Model"
    static let cancel = "Cancel"
    static let sourceResult = "Original SMS annotation"
    static let implementationPrincipleTitle = "Implementation Principle"
    static let implementationPrinciple = "Apple 端侧 LLM uses SystemLanguageModel.default. Rules and samples are local bundled rules/samples; there is no network and no cloud fallback. This generative demo is for capability exploration only and does not represent production accuracy."
}

struct SMSClassificationPresentation: Equatable, Sendable {
    let source: String
    let segments: [SMSHighlightSegment]

    init(source: String, result: SMSAnnotationResult?) {
        self.source = source
        self.segments = SMSHighlightSegmenter.segments(source: source, entities: result?.entities ?? [])
    }

    var accessibilityLabel: String {
        let labels = segments.compactMap { segment -> String? in
            guard let label = segment.label else { return nil }
            return "\(segment.text) (\(label))"
        }
        guard !labels.isEmpty else { return source }
        return "\(source). Annotations: \(labels.joined(separator: "; "))"
    }
}

struct SMSClassificationButtonPresentation: Equatable, Sendable {
    let runTitle: String
    let runButtonEnabled: Bool
    let randomButtonEnabled: Bool

    init(isRunning: Bool, canRun: Bool, hasSamples: Bool) {
        runTitle = isRunning ? SMSClassificationExperienceCopy.cancel : SMSClassificationExperienceCopy.run
        runButtonEnabled = !isRunning && canRun
        randomButtonEnabled = !isRunning && hasSamples
    }
}

struct SMSClassificationExperienceView: View {
    @StateObject private var model: SMSClassificationViewModel

    init(model: SMSClassificationViewModel = SMSClassificationViewModel()) {
        _model = StateObject(wrappedValue: model)
    }

    private var presentation: SMSClassificationPresentation {
        SMSClassificationPresentation(source: model.inputSnapshot ?? model.input, result: model.result)
    }

    private var buttons: SMSClassificationButtonPresentation {
        SMSClassificationButtonPresentation(
            isRunning: model.isRunning,
            canRun: model.canRun,
            hasSamples: !model.samples.isEmpty
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ExperienceIntro(experience: ExperienceCatalog[.smsClassification])
                SMSModelAvailabilitySurface(status: model.availabilityStatus)

                Text("SMS")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                TextEditor(text: $model.input)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 130)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.cardStroke, lineWidth: 1)
                    }
                    .disabled(!model.isInputEditable)
                    .accessibilityLabel("SMS input")

                Button(SMSClassificationExperienceCopy.randomSample) {
                    model.selectRandomSample()
                }
                .buttonStyle(.bordered)
                .disabled(!buttons.randomButtonEnabled)

                if model.isRunning {
                    Button(SMSClassificationExperienceCopy.cancel, action: model.cancel)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                } else {
                    Button {
                        Task { await model.run() }
                    } label: {
                        Label(buttons.runTitle, systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!buttons.runButtonEnabled)
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(errorMessage)")
                }

                if let result = model.result {
                    resultView(result)
                }

                if let latency = model.latency {
                    Text(String(format: "Latency %.3fs", latency))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .accessibilityLabel(String(format: "Latency %.3f seconds", latency))
                }

                implementationPrinciple
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(SMSClassificationExperienceCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.onDisappear() }
    }

    @ViewBuilder
    private func resultView(_ result: SMSAnnotationResult) -> some View {
        let resultPresentation = SMSClassificationPresentation(source: model.inputSnapshot ?? model.input, result: result)
        VStack(alignment: .leading, spacing: 10) {
            Text(SMSClassificationExperienceCopy.sourceResult)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("Domain: \(result.domain)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.secondaryInk)

            SMSAnnotationFlowLayout(spacing: 4) {
                ForEach(Array(resultPresentation.segments.enumerated()), id: \.offset) { index, segment in
                    SMSAnnotationSegmentView(segment: segment, colorIndex: index)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(resultPresentation.accessibilityLabel)

            ResultSurface(title: "Raw Model JSON", text: model.rawJSONOutput ?? "")
            ResultSurface(title: "Validated JSON", text: model.jsonOutput ?? "")
        }
    }

    private var implementationPrinciple: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SMSClassificationExperienceCopy.implementationPrincipleTitle)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(SMSClassificationExperienceCopy.implementationPrinciple)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

private struct SMSModelAvailabilitySurface: View {
    let status: FoundationModelStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MODEL STATUS")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryInk)
            Text(status.rawValue)
                .font(.headline)
                .foregroundStyle(status == .available ? AppTheme.ink : .orange)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var detail: String {
        switch status {
        case .available:
            "SystemLanguageModel.default is available for this device."
        case .deviceNotEligible:
            "This device is not eligible for the on-device model."
        case .modelNotReady:
            "The on-device model assets are not ready yet."
        case .unavailable:
            "Apple Intelligence is unavailable for this model route."
        }
    }
}

private struct SMSAnnotationSegmentView: View {
    let segment: SMSHighlightSegment
    let colorIndex: Int

    var body: some View {
        if let label = segment.label {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(SMSAnnotationPalette.color(at: colorIndex), in: Capsule())
                Text(segment.text)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(SMSAnnotationPalette.color(at: colorIndex).opacity(0.22), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(segment.text), \(label)")
        } else {
            Text(segment.text)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
        }
    }
}

private enum SMSAnnotationPalette {
    static let colors: [Color] = [
        Color(red: 0.14, green: 0.42, blue: 0.78),
        Color(red: 0.67, green: 0.31, blue: 0.18),
        Color(red: 0.20, green: 0.54, blue: 0.34),
        Color(red: 0.57, green: 0.28, blue: 0.68),
    ]

    static func color(at index: Int) -> Color { colors[index % colors.count] }
}

struct SMSAnnotationFlowLayoutMetrics: Equatable, Sendable {
    static func constrainedWidth(naturalWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        min(naturalWidth, availableWidth)
    }
}

private struct SMSAnnotationFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        let items = measurements(for: subviews, width: availableWidth)
        let contentWidth = proposal.width ?? items.map { $0.frame.maxX }.max() ?? 0
        let contentHeight = items.map { $0.frame.maxY }.max() ?? 0
        return CGSize(width: contentWidth, height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for (subview, item) in zip(subviews, measurements(for: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: item.proposalWidth, height: nil)
            )
        }
    }

    private struct Measurement {
        let frame: CGRect
        let proposalWidth: CGFloat
    }

    private func measurements(for subviews: Subviews, width: CGFloat) -> [Measurement] {
        var result: [Measurement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let naturalSize = subview.sizeThatFits(.unspecified)
            let constrainedWidth = SMSAnnotationFlowLayoutMetrics.constrainedWidth(
                naturalWidth: naturalSize.width,
                availableWidth: width
            )
            let proposal = ProposedViewSize(width: constrainedWidth, height: nil)
            let size = subview.sizeThatFits(proposal)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            result.append(
                Measurement(
                    frame: CGRect(origin: CGPoint(x: x, y: y), size: size),
                    proposalWidth: constrainedWidth
                )
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return result
    }
}
