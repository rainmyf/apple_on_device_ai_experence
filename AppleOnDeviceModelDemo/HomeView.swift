import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                homeHeader

                directionSection

                ForEach(Array(HomeDirectoryContent.sections.enumerated()), id: \.element.category) { index, section in
                    if index > 0 {
                        Divider()
                            .overlay(AppTheme.ink.opacity(0.12))
                    }
                    categorySection(section)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose an entry point")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: ExperienceGridCardPolicy.columnCount),
                spacing: 12
            ) {
                ForEach(HomeDirectionContent.entries, id: \.title) { entry in
                    HomeDirectionCard(entry: entry)
                }
            }
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.blue)
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .frame(width: 96, height: 96)

            Text("On-device\nExperiences")
                .font(.largeTitle.weight(.bold))
                .tracking(-1.5)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("On-device Experiences")
    }

    @ViewBuilder
    private func categorySection(_ section: HomeCuratedSection) -> some View {
        let items = section.itemIDs.map { ExperienceCatalog[$0] }
        VStack(alignment: .leading, spacing: 14) {
            CategoryHeader(category: section.category)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: ExperienceGridCardPolicy.columnCount), spacing: 12) {
                ForEach(items) { item in
                    ExperienceGridCard(experience: item)
                }
            }
        }
    }
}

private struct HomeDirectionCard: View {
    let entry: HomeDirectionEntry

    var body: some View {
        NavigationLink(value: entry.route) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent(for: category))
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent(for: category).opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)

                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.accent(for: category).opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens entry point")
    }

    private var category: ExperienceCategory {
        switch entry.route {
        case .experience(.appIntents): .createSystem
        default: .languageText
        }
    }

    private var symbolName: String {
        switch entry.route {
        case .experience(.appIntents): "arrow.triangle.2.circlepath"
        default: "sparkles"
        }
    }
}
