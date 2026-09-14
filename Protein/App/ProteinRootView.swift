import ProteinCore
import SwiftUI

struct ProteinRootView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "circle.fill") { DashboardView() }
            Tab("Insights", systemImage: "chart.bar.xaxis") { InsightsView() }
            Tab("Meals", systemImage: "bookmark") { SavedMealsView() }
            Tab("Estimate", systemImage: "camera.viewfinder") {
                MealAnalysisView(service: Self.mealAnalysisService())
            }
        }
        .tint(ProteinTheme.Color.accent)
    }

    private static func mealAnalysisService() -> any MealAnalysisService {
        guard let configuration = try? MealAnalysisConfiguration.from() else {
            return UnavailableMealAnalysisService()
        }
        return ProxyMealAnalysisService(configuration: configuration)
    }
}
