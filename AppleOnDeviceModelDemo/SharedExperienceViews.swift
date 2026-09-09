import SwiftUI
import UIKit

struct FeaturedExperienceCard: View {
    let experience: ExperienceDefinition

    var body: some View {
        NavigationLink(value: AppRouteResolver.homeSelection(for: experience)) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(experience.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: experience.symbolName)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(AppTheme.accent(for: experience.category))
                        .accessibilityHidden(true)
                }

                Spacer(minLength: 0)

                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.accent(for: experience.category).opacity(0.16))
                    Image(systemName: experience.symbolName)
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(AppTheme.accent(for: experience.category))
                        .accessibilityHidden(true)
                }
                .frame(height: 160)

                CapabilityStatusLabel(requirement: experience.requirement)
            }
            .padding(18)
            .frame(width: 245, alignment: .topLeading)
            .frame(minHeight: 300, alignment: .topLeading)
            .background(
                AppTheme.accent(for: experience.category).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.accent(for: experience.category).opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(ExperienceDisplayCopy.openingHint(for: experience.title))
    }
}

enum ExperienceGridCardPolicy {
    static let columnCount = 2
    static let titleLineLimit = 2
    static let statusLineLimit = 3
    static let minimumHeight: CGFloat = 220
}

struct ExperienceGridCardPresentation: Equatable {
    let title: String
    let status: String
    let versionBadge: String
    let accessibilityLabel: String

    init(experience: ExperienceDefinition) {
        title = experience.title
        status = experience.requirement.availabilityDescription
        versionBadge = experience.versionBadge
        accessibilityLabel = "\(title). \(versionBadge). \(status)"
    }
}

struct ExperienceGridCard: View {
    let experience: ExperienceDefinition

    private var presentation: ExperienceGridCardPresentation {
        ExperienceGridCardPresentation(experience: experience)
    }

    var body: some View {
        NavigationLink(value: AppRouteResolver.route(for: experience)) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accent(for: experience.category).opacity(0.16))
                    Image(systemName: experience.symbolName)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(AppTheme.accent(for: experience.category))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 84)

                Text(presentation.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(ExperienceGridCardPolicy.titleLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)

                Text(presentation.versionBadge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent(for: experience.category))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent(for: experience.category).opacity(0.10), in: Capsule())

                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: experience.requirement == .none ? "checkmark.circle" : "info.circle")
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(presentation.status)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .lineLimit(ExperienceGridCardPolicy.statusLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: ExperienceGridCardPolicy.minimumHeight, alignment: .topLeading)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(ExperienceDisplayCopy.openingHint(for: experience.title))
    }
}

struct CategoryHeader: View {
    let category: ExperienceCategory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: AppTheme.categorySymbol(for: category))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent(for: category), in: Circle())
                .accessibilityHidden(true)

            Text(category.rawValue)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.accent(for: category))

            Spacer(minLength: 0)
        }
    }
}

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
    }
}

extension View {
    func dismissibleKeyboard() -> some View {
        modifier(KeyboardDismissModifier())
    }
}

struct CapabilityStatusLabel: View {
    let requirement: ExperienceRequirement

    var body: some View {
        Label(requirement.availabilityDescription, systemImage: requirement == .none ? "checkmark.circle" : "info.circle")
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryInk)
    }
}

struct ExperienceIntro: View {
    let experience: ExperienceDefinition
    var showsDescription = true

    private var metadata: ExperiencePageMetadata {
        ExperienceCatalog.pageMetadata(for: experience.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: experience.symbolName)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(AppTheme.accent(for: experience.category))
                    .frame(width: 54, height: 54)
                    .background(AppTheme.accent(for: experience.category).opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(experience.title)
                        .font(.title.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(experience.framework)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accent(for: experience.category))
                }
            }
            if showsDescription {
                Text(metadata.intro)
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(metadata.status, systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }
}

struct ResultSurface: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryInk)
            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        }
        .padding(16)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        }
    }
}

struct UsageInstructions: View {
    let experience: ExperienceDefinition

    private var metadata: ExperiencePageMetadata {
        ExperienceCatalog.pageMetadata(for: experience.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this experience")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(metadata.usage)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
