import ProteinCore
import SwiftUI
import WidgetKit

struct ProteinWidgetEntry: TimelineEntry {
    let date: Date
    let grams: Double
}

struct ProteinWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProteinWidgetEntry {
        ProteinWidgetEntry(date: .now, grams: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProteinWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProteinWidgetEntry>) -> Void) {
        let entry = currentEntry()
        let nextMidnight = Calendar.current.startOfDay(for: entry.date).addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func currentEntry() -> ProteinWidgetEntry {
        ProteinWidgetEntry(
            date: .now,
            grams: AppGroup.defaults.double(forKey: AppGroup.todayProteinKey)
        )
    }
}

struct ProteinWidgetView: View {
    let entry: ProteinWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Protein", systemImage: "fork.knife")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(entry.grams, format: .number.precision(.fractionLength(0...1)))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.7)
            Text("grams today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein today")
        .accessibilityValue("\(entry.grams.formatted()) grams")
    }
}

struct ProteinWidget: Widget {
    let kind = "ProteinWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProteinWidgetProvider()) { entry in
            ProteinWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Protein")
        .description("See today's protein total at a glance.")
        .supportedFamilies([.systemSmall])
    }
}
