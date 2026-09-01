import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                homeHeader

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
