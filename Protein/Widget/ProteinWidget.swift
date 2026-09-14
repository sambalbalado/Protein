import AppIntents
import ProteinCore
import SwiftData
import SwiftUI
import WidgetKit

struct ProteinWidgetEntry: TimelineEntry {
    let date: Date
    let state: ProteinWidgetState
}

struct ProteinWidgetProvider: TimelineProvider {
    private var calendar: Calendar { .current }

    func placeholder(in context: Context) -> ProteinWidgetEntry {
        let now = Date.now
        return ProteinWidgetEntry(
            date: now,
            state: ProteinWidgetState(
                dayStart: calendar.startOfDay(for: now),
                total: 72,
                goal: 120,
                lastUpdated: now,
                latestEntryName: "Greek yogurt",
                latestEntryGrams: 20
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ProteinWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProteinWidgetEntry>) -> Void) {
        let now = Date.now
        let current = currentEntry(at: now)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        let rollover = ProteinWidgetEntry(
            date: nextMidnight,
            state: .empty(
                at: nextMidnight,
                goal: current.state.goal,
                calendar: calendar,
                lastUpdated: current.state.lastUpdated,
                latestEntryName: current.state.latestEntryName,
                latestEntryGrams: current.state.latestEntryGrams
            )
        )
        completion(Timeline(entries: [current, rollover], policy: .after(nextMidnight.addingTimeInterval(60))))
    }

    private func currentEntry(at date: Date) -> ProteinWidgetEntry {
        ProteinWidgetEntry(
            date: date,
            state: ProteinWidgetStateStore.read(at: date, calendar: calendar)
        )
    }
}

struct ProteinWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProteinWidgetEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .containerBackground(for: .widget) {
            Color(red: 0.055, green: 0.075, blue: 0.065)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Spacer(minLength: 0)
            total
            ProgressView(value: min(entry.state.progress, 1))
                .tint(accent)
                .widgetAccentable()
                .accessibilityHidden(true)
            quickAddRow
        }
        .widgetURL(ProteinDeepLink.preciseEntryURL)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary)
    }

    private var mediumLayout: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Spacer(minLength: 0)
                total
                ProgressView(value: min(entry.state.progress, 1))
                    .tint(accent)
                    .widgetAccentable()
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 9) {
                quickAction("+5 g", systemImage: "plus", intent: AddFiveProteinIntent())
                quickAction("+10 g", systemImage: "plus", intent: AddTenProteinIntent())
                Button(intent: RepeatLatestProteinIntent()) {
                    Label(repeatLabel, systemImage: "arrow.clockwise")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .disabled(!entry.state.canRepeatLatestEntry)
                .buttonStyle(WidgetActionButtonStyle())

                Link(destination: ProteinDeepLink.preciseEntryURL) {
                    Label("Log exact", systemImage: "slider.horizontal.3")
                        .lineLimit(1)
                }
                .buttonStyle(WidgetActionButtonStyle(emphasized: true))
            }
            .frame(width: 124)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(accent)
                .widgetAccentable()
            Text("PROTEIN")
                .font(.caption.weight(.bold))
                .tracking(1.1)
            Spacer(minLength: 4)
            Text(entry.state.lastUpdated, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.state.total, format: .number.precision(.fractionLength(0...1)))
                .font(.system(size: family == .systemMedium ? 42 : 38, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.65)
            Text("of \(formatted(entry.state.goal)) g")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var quickAddRow: some View {
        HStack(spacing: 8) {
            Button(intent: AddFiveProteinIntent()) { Text("+5") }
                .buttonStyle(WidgetCompactButtonStyle())
                .accessibilityLabel("Add 5 grams")
            Button(intent: AddTenProteinIntent()) { Text("+10") }
                .buttonStyle(WidgetCompactButtonStyle())
                .accessibilityLabel("Add 10 grams")
        }
    }

    private func quickAction<I: AppIntent>(_ title: String, systemImage: String, intent: I) -> some View {
        Button(intent: intent) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .buttonStyle(WidgetActionButtonStyle())
    }

    private var repeatLabel: String {
        guard let name = entry.state.latestEntryName else { return "Repeat last" }
        return "Repeat \(name)"
    }

    private var summary: String {
        "Protein today, \(formatted(entry.state.total)) of \(formatted(entry.state.goal)) grams. Updated \(entry.state.lastUpdated.formatted(date: .omitted, time: .shortened))."
    }

    private var accent: Color { Color(red: 0.42, green: 0.88, blue: 0.62) }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }
}

private struct WidgetCompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.white.opacity(configuration.isPressed ? 0.22 : 0.12), in: Capsule())
    }
}

private struct WidgetActionButtonStyle: ButtonStyle {
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                emphasized ? Color.white.opacity(0.2) : Color.white.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct AddFiveProteinIntent: AppIntent {
    static var title: LocalizedStringResource { "Add 5 g protein" }
    static var description: IntentDescription { "Adds one 5 gram protein entry for today." }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        try await ProteinWidgetMutation.add(grams: 5)
        return .result()
    }
}

struct AddTenProteinIntent: AppIntent {
    static var title: LocalizedStringResource { "Add 10 g protein" }
    static var description: IntentDescription { "Adds one 10 gram protein entry for today." }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        try await ProteinWidgetMutation.add(grams: 10)
        return .result()
    }
}

struct RepeatLatestProteinIntent: AppIntent {
    static var title: LocalizedStringResource { "Repeat latest protein" }
    static var description: IntentDescription { "Repeats the latest valid protein entry once." }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        try await ProteinWidgetMutation.repeatLatest()
        return .result()
    }
}

private enum ProteinWidgetActionError: LocalizedError {
    case nothingToRepeat
    case dataUnavailable

    var errorDescription: String? {
        switch self {
        case .nothingToRepeat:
            "Log protein in the app before using Repeat."
        case .dataUnavailable:
            "Unlock your iPhone and open Protein, then try again."
        }
    }
}

private enum ProteinWidgetMutation {
    @MainActor
    static func add(grams: Double) throws {
        do {
            let container = try PersistenceController.makeShared()
            let repository = SwiftDataProteinRepository(context: container.mainContext)
            try repository.addQuickProtein(grams, at: .now)
        } catch {
            throw ProteinWidgetActionError.dataUnavailable
        }
    }

    @MainActor
    static func repeatLatest() throws {
        do {
            let container = try PersistenceController.makeShared()
            let repository = SwiftDataProteinRepository(context: container.mainContext)
            guard try repository.repeatLatestEligibleEntry(at: .now) else {
                throw ProteinWidgetActionError.nothingToRepeat
            }
        } catch let error as ProteinWidgetActionError {
            throw error
        } catch {
            throw ProteinWidgetActionError.dataUnavailable
        }
    }
}

struct ProteinWidget: Widget {
    let kind = AppGroup.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProteinWidgetProvider()) { entry in
            ProteinWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Protein")
        .description("See today’s progress and add protein without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
