import Charts
import ProteinCore
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var entries: [ProteinEntry] = []
    @State private var goalChanges: [ProteinGoalChange] = []
    @State private var fallbackGoal = 120.0
    @State private var errorMessage: String?
    @State private var month = Date.now
    @State private var selectedDate = Date.now
    private let calendar = Calendar.current

    private var week: [ProteinDay] {
        let end = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        return ProteinInsights.days(from: start, through: end, entries: entries, goalChanges: goalChanges, fallbackGoal: fallbackGoal, calendar: calendar)
    }

    private var monthDays: [ProteinDay] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let end = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return [] }
        return ProteinInsights.days(from: interval.start, through: end, entries: entries, goalChanges: goalChanges, fallbackGoal: fallbackGoal, calendar: calendar)
    }

    private var selected: ProteinDay? { monthDays.first { calendar.isDate($0.date, inSameDayAs: selectedDate) } }
    private var selectedEntries: [ProteinEntry] { DailyProteinSummary.entries(for: selectedDate, in: entries, calendar: calendar) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ProteinTheme.Spacing.large) {
                    weeklyCard
                    calendarCard
                    selectedCard
                }.padding(ProteinTheme.Spacing.medium)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
        }
        .tint(ProteinTheme.Color.accent)
        .task(id: month) { loadVisibleRange() }
        .alert("Couldn’t load insights", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private var weeklyCard: some View {
        ProteinCard {
            VStack(alignment: .leading, spacing: ProteinTheme.Spacing.medium) {
                Text("Last seven days").font(.title3.bold())
                if week.allSatisfy({ !$0.hasData }) {
                    ContentUnavailableView("No history yet", systemImage: "chart.bar", description: Text("Your weekly pattern will appear as you log protein."))
                } else {
                    Chart(week) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Protein", day.total))
                            .foregroundStyle(day.total >= day.goal ? ProteinTheme.Color.accent : ProteinTheme.Color.accent.opacity(0.45))
                            .cornerRadius(5)
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("Goal", day.goal))
                            .foregroundStyle(.secondary.opacity(0.55)).lineStyle(.init(lineWidth: 1.5, dash: [4, 4]))
                    }
                    .frame(height: 180)
                    .chartXAxis { AxisMarks(values: week.map(\.date)) { value in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                    .accessibilityLabel("Seven day protein chart")
                    .accessibilityValue(weeklySummary)
                }
            }
        }
    }

    private var calendarCard: some View {
        ProteinCard {
            VStack(spacing: ProteinTheme.Spacing.medium) {
                HStack {
                    Button("Previous month", systemImage: "chevron.left") { changeMonth(-1) }.labelStyle(.iconOnly)
                    Spacer(); Text(month, format: .dateTime.month(.wide).year()).font(.headline); Spacer()
                    Button("Next month", systemImage: "chevron.right") { changeMonth(1) }.labelStyle(.iconOnly)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(weekdaySymbols, id: \.self) { Text($0.prefix(1)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                    ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 42) }
                    ForEach(monthDays) { day in dayCell(day) }
                }
            }
        }
    }

    private func dayCell(_ day: ProteinDay) -> some View {
        let reached = day.hasData && day.progress >= 1
        return Button { selectedDate = day.date } label: {
            VStack(spacing: 2) {
                Text(day.date, format: .dateTime.day()).font(.caption.weight(.semibold))
                Image(systemName: !day.hasData ? "minus" : reached ? (day.progress > 1 ? "plus" : "checkmark") : "circle.fill")
                    .font(.system(size: 8, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(cellColor(day), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(calendar.isDate(day.date, inSameDayAs: selectedDate) ? Color.primary : Color.secondary.opacity(day.hasData ? 0 : 0.25), lineWidth: calendar.isDate(day.date, inSameDayAs: selectedDate) ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(day.hasData ? "\(format(day.total)) of \(format(day.goal)) grams, \(status(day))" : "No entries")
    }

    private var selectedCard: some View {
        ProteinCard {
            VStack(alignment: .leading, spacing: ProteinTheme.Spacing.small) {
                Text(selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.headline)
                Text(selected.map { "\(format($0.total)) of \(format($0.goal)) g" } ?? "No data").font(.title2.bold())
                if selectedEntries.isEmpty { Text("No entries on this day.").foregroundStyle(.secondary) }
                else { ForEach(selectedEntries) { entry in HStack { Text(entry.name); Spacer(); Text("\(format(entry.grams)) g").monospacedDigit() } } }
            }
        }
    }

    private var leadingBlanks: Int {
        guard let first = monthDays.first?.date else { return 0 }
        return (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    }
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let offset = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[offset...] + symbols[..<offset])
    }
    private var weeklySummary: String { week.map { "\($0.date.formatted(.dateTime.weekday(.wide))): \(format($0.total)) grams of \(format($0.goal))" }.joined(separator: ", ") }
    private func cellColor(_ day: ProteinDay) -> Color { day.hasData ? ProteinTheme.Color.accent.opacity(0.18 + min(day.progress, 1) * 0.72) : Color.secondary.opacity(0.06) }
    private func status(_ day: ProteinDay) -> String { day.progress > 1 ? "over goal" : day.progress == 1 ? "goal reached" : "partial progress" }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1))) }
    private func changeMonth(_ value: Int) { if let newMonth = calendar.date(byAdding: .month, value: value, to: month) { month = newMonth; selectedDate = calendar.dateInterval(of: .month, for: newMonth)?.start ?? newMonth } }
    private func loadVisibleRange() {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return }
        let today = calendar.startOfDay(for: .now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let start = min(weekStart, monthInterval.start)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? .now
        let end = max(tomorrow, monthInterval.end)
        do {
            let repository = SwiftDataProteinRepository(context: modelContext)
            fallbackGoal = try repository.settings().dailyProteinGoal
            goalChanges = try repository.goalChanges()
            entries = try repository.entries(from: start, to: end)
        } catch { errorMessage = error.localizedDescription }
    }
}
