import ProteinCore
import SwiftUI

struct ProteinRootView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "circle.fill") { DashboardView() }
            Tab("Insights", systemImage: "chart.bar.xaxis") { InsightsView() }
            Tab("Meals", systemImage: "bookmark") { SavedMealsView() }
            Tab("Estimate", systemImage: "camera.viewfinder") {
                MealAnalysisView(service: MockMealAnalysisService(fixture: .success, delay: .milliseconds(500)))
            }
        }
        .tint(ProteinTheme.Color.accent)
    }
}
