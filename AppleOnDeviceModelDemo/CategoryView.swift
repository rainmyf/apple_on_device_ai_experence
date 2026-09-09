import SwiftUI

struct CategoryView: View {
    let category: ExperienceCategory

    private var items: [ExperienceDefinition] {
        AppRouteResolver.items(in: category)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: AppTheme.categorySymbol(for: category))
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(AppTheme.accent(for: category), in: Circle())
                        .accessibilityHidden(true)
                    Text(category.rawValue)
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(ExperienceDisplayCopy.categorySummary(for: items.count))
                        .font(.body)
                        .foregroundStyle(AppTheme.secondaryInk)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: ExperienceGridCardPolicy.columnCount), spacing: 12) {
                    ForEach(items) { item in
                        ExperienceGridCard(experience: item)
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}
