import SwiftUI

struct DashboardView: View {
    private let sampleGoal = 120

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ProteinTheme.Spacing.large) {
                    progressCard
                    emptyStateCard
                    PrimaryActionButton(title: "Add protein", systemImage: "plus") {}
                        .accessibilityHint("Manual logging arrives in the next milestone")
                }
                .padding(ProteinTheme.Spacing.medium)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
        }
        .tint(ProteinTheme.Color.accent)
    }

    private var progressCard: some View {
        ProteinCard {
            VStack(alignment: .leading, spacing: ProteinTheme.Spacing.small) {
                Text("Daily protein")
                    .font(.headline)
                    .foregroundStyle(ProteinTheme.Color.subduedText)
                ViewThatFits {
                    HStack(alignment: .firstTextBaseline, spacing: ProteinTheme.Spacing.small) {
                        totalText
                        Spacer(minLength: ProteinTheme.Spacing.small)
                        Text("of \(sampleGoal) g")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(ProteinTheme.Color.subduedText)
                    }
                    VStack(alignment: .leading, spacing: ProteinTheme.Spacing.small) {
                        totalText
                        Text("of \(sampleGoal) g")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(ProteinTheme.Color.subduedText)
                    }
                }
                ProgressView(value: 0, total: Double(sampleGoal))
                    .tint(ProteinTheme.Color.accent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily protein progress")
        .accessibilityValue("0 of \(sampleGoal) grams")
    }

    private var totalText: some View {
        Text("0 g")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(.primary)
            .contentTransition(.numericText())
    }

    private var emptyStateCard: some View {
        ProteinCard {
            ContentUnavailableView {
                Label("Nothing logged yet", systemImage: "fork.knife")
            } description: {
                Text("Your protein entries will appear here.")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") {
    DashboardView()
}

#Preview("Dark") {
    DashboardView()
        .preferredColorScheme(.dark)
}

#Preview("Large Dynamic Type") {
    DashboardView()
        .environment(\.dynamicTypeSize, .accessibility3)
}
