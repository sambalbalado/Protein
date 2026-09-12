import SwiftUI

struct ProteinRootView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "circle.fill") { DashboardView() }
            Tab("Insights", systemImage: "chart.bar.xaxis") { InsightsView() }
            Tab("Meals", systemImage: "bookmark") { SavedMealsView() }
        }
        .tint(ProteinTheme.Color.accent)
    }
}
