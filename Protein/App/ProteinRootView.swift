import ProteinCore
import SwiftUI

struct ProteinRootView: View {
    @State private var selectedTab = ProteinTab.today
    @State private var preciseEntryRequest: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "circle.fill", value: ProteinTab.today) {
                DashboardView(openEntryRequest: preciseEntryRequest)
            }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: ProteinTab.insights) { InsightsView() }
            Tab("Meals", systemImage: "bookmark", value: ProteinTab.meals) { SavedMealsView() }
            Tab("Estimate", systemImage: "camera.viewfinder", value: ProteinTab.estimate) {
                MealAnalysisView(service: Self.mealAnalysisService())
            }
        }
        .tint(ProteinTheme.Color.accent)
        .onOpenURL { url in
            guard ProteinDeepLink(url: url) == .preciseEntry else { return }
            selectedTab = .today
            preciseEntryRequest = UUID()
        }
    }

    private static func mealAnalysisService() -> any MealAnalysisService {
        guard let configuration = try? MealAnalysisConfiguration.from() else {
            return UnavailableMealAnalysisService()
        }
        return ProxyMealAnalysisService(configuration: configuration)
    }
}

private enum ProteinTab: Hashable {
    case today
    case insights
    case meals
    case estimate
}
