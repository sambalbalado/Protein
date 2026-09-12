import ProteinCore
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProteinEntry.loggedAt, order: .reverse) private var entries: [ProteinEntry]
    @Query private var settings: [UserSettings]
    @State private var editor: EntryEditor?
    @State private var showGoal = false
    @State private var pendingDelete: ProteinEntry?
    @State private var errorMessage: String?

    private var goal: Double { settings.first?.dailyProteinGoal ?? 120 }
    private var today: [ProteinEntry] { DailyProteinSummary.entries(for: .now, in: entries) }
    private var summary: DailyProteinSummary { .init(entries: today, goal: goal) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ProteinTheme.Spacing.large) {
                    progressCard
                    quickAdds
                    entriesCard
                    PrimaryActionButton(title: "Add protein", systemImage: "plus") { editor = .new }
                }
                .padding(ProteinTheme.Spacing.medium)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                Button("Goal", systemImage: "target") { showGoal = true }
                    .accessibilityHint("Change your daily protein goal")
            }
        }
        .tint(ProteinTheme.Color.accent)
        .sheet(item: $editor) { value in
            EntryEditorSheet(entry: value.entry) { save(value, name: $0, grams: $1, time: $2, note: $3) }
        }
        .sheet(isPresented: $showGoal) { GoalEditorSheet(goal: goal, onSave: saveGoal) }
        .confirmationDialog("Delete this entry?", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let pendingDelete { delete(pendingDelete) } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { Text("This immediately removes it from today’s total.") }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Please try again.") }
        .task { ensureSettings() }
    }

    private var progressCard: some View {
        ProteinCard {
            VStack(alignment: .leading, spacing: ProteinTheme.Spacing.medium) {
                HStack {
                    Text("DAILY PROTEIN").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                    Spacer()
                    Text(summary.total >= goal ? "Goal reached" : "\(format(summary.remaining)) g left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(summary.total >= goal ? ProteinTheme.Color.accent : .secondary)
                }
                ViewThatFits {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { total; goalText }
                    VStack(alignment: .leading, spacing: 4) { total; goalText }
                }
                ProgressView(value: min(summary.progress, 1)).tint(ProteinTheme.Color.accent).scaleEffect(x: 1, y: 1.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily protein progress")
        .accessibilityValue("\(format(summary.total)) of \(format(goal)) grams")
    }

    private var total: some View {
        Text(format(summary.total)).font(.system(size: 52, weight: .bold, design: .rounded)).contentTransition(.numericText())
    }

    private var goalText: some View {
        Text("of \(format(goal)) g").font(.title3.weight(.medium)).foregroundStyle(.secondary)
    }

    private var quickAdds: some View {
        VStack(alignment: .leading, spacing: ProteinTheme.Spacing.small) {
            Text("Quick add").font(.headline)
            HStack(spacing: ProteinTheme.Spacing.small) {
                ForEach([5, 10, 25], id: \.self) { grams in
                    Button("+\(grams) g") { quickAdd(Double(grams)) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).frame(maxWidth: .infinity)
                        .accessibilityHint("Adds \(grams) grams to today")
                }
            }
        }
    }

    private var entriesCard: some View {
        ProteinCard {
            VStack(alignment: .leading, spacing: ProteinTheme.Spacing.medium) {
                Text("Today’s entries").font(.headline)
                if today.isEmpty {
                    ContentUnavailableView { Label("Nothing logged yet", systemImage: "fork.knife") }
                    description: { Text("Quick add or log a food to begin.") }
                } else {
                    ForEach(Array(today.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        Button { editor = .edit(entry) } label: {
                            HStack(spacing: ProteinTheme.Spacing.medium) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(entry.loggedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                                    if let note = entry.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                Text("\(format(entry.grams)) g").font(.headline.monospacedDigit()).foregroundStyle(.primary)
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry } }
                        .accessibilityHint("Double tap to edit. Swipe for delete.")
                    }
                }
            }
        }
    }

    private var deleteBinding: Binding<Bool> { .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }) }
    private var errorBinding: Binding<Bool> { .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }) }
    private func repository() -> SwiftDataProteinRepository { .init(context: modelContext) }

    private func ensureSettings() { do { _ = try repository().settings() } catch { errorMessage = error.localizedDescription } }
    private func quickAdd(_ grams: Double) { do { try repository().add(ProteinEntry(name: "Quick add", grams: grams)) } catch { errorMessage = error.localizedDescription } }
    private func delete(_ entry: ProteinEntry) { do { try repository().delete(entry); pendingDelete = nil } catch { errorMessage = error.localizedDescription } }

    private func save(_ value: EntryEditor, name: String, grams: Double, time: Date, note: String?) {
        do {
            try ProteinEntryValidator.validate(name: name, grams: grams)
            if let entry = value.entry {
                entry.name = name.trimmingCharacters(in: .whitespacesAndNewlines); entry.grams = grams
                entry.loggedAt = time; entry.note = note; try repository().save()
            } else {
                try repository().add(ProteinEntry(name: name.trimmingCharacters(in: .whitespacesAndNewlines), grams: grams, loggedAt: time, note: note))
            }
            editor = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveGoal(_ value: Double) {
        guard value.isFinite, (20...400).contains(value) else { errorMessage = "Choose a daily goal between 20 g and 400 g."; return }
        do { let current = try repository().settings(); current.dailyProteinGoal = value; try repository().save(); showGoal = false }
        catch { errorMessage = error.localizedDescription }
    }

    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1))) }
}

@MainActor
private struct EntryEditor: Identifiable {
    let id = UUID(); let entry: ProteinEntry?
    static let new = EntryEditor(entry: nil)
    static func edit(_ entry: ProteinEntry) -> Self { .init(entry: entry) }
}

private struct EntryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String; @State private var grams: String; @State private var time: Date; @State private var note: String
    @State private var message: String?
    let entry: ProteinEntry?; let onSave: (String, Double, Date, String?) -> Void

    init(entry: ProteinEntry?, onSave: @escaping (String, Double, Date, String?) -> Void) {
        self.entry = entry; self.onSave = onSave
        _name = .init(initialValue: entry?.name ?? ""); _grams = .init(initialValue: entry.map { String(format: "%g", $0.grams) } ?? "")
        _time = .init(initialValue: entry?.loggedAt ?? .now); _note = .init(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Protein") {
                    TextField("Food name", text: $name).textInputAutocapitalization(.sentences)
                    TextField("Grams", text: $grams).keyboardType(.decimalPad)
                    if let message { Text(message).font(.footnote).foregroundStyle(.red) }
                }
                Section("Details") {
                    DatePicker("Meal time", selection: $time)
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle(entry == nil ? "Add protein" : "Edit entry").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: validate).fontWeight(.semibold) }
            }
        }
    }

    private func validate() {
        guard let value = Double(grams.replacingOccurrences(of: ",", with: ".")) else { message = "Enter a valid protein amount."; return }
        do {
            try ProteinEntryValidator.validate(name: name, grams: value); message = nil
            let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            onSave(name, value, time, cleanNote.isEmpty ? nil : cleanNote)
        } catch { message = error.localizedDescription }
    }
}

private struct GoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let onSave: (Double) -> Void
    init(goal: Double, onSave: @escaping (Double) -> Void) { _text = .init(initialValue: String(format: "%g", goal)); self.onSave = onSave }
    var body: some View {
        NavigationStack {
            Form { Section("Daily goal") { TextField("Protein grams", text: $text).keyboardType(.decimalPad); Text("Choose between 20 g and 400 g. You can change this anytime.").font(.footnote).foregroundStyle(.secondary) } }
                .navigationTitle("Protein goal").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if let value = Double(text.replacingOccurrences(of: ",", with: ".")) { onSave(value) } }.fontWeight(.semibold) }
                }
        }.presentationDetents([.medium])
    }
}

#Preview("Light") { DashboardView().modelContainer(try! PersistenceController.makeInMemory()) }
#Preview("Dark") { DashboardView().modelContainer(try! PersistenceController.makeInMemory()).preferredColorScheme(.dark) }
#Preview("Large Dynamic Type") { DashboardView().modelContainer(try! PersistenceController.makeInMemory()).environment(\.dynamicTypeSize, .accessibility3) }
