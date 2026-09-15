import ProteinCore
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProteinEntry.loggedAt, order: .reverse) private var entries: [ProteinEntry]
    @Query(sort: \SavedMeal.name) private var meals: [SavedMeal]
    @Query private var settings: [UserSettings]
    @State private var editor: EntryEditor?
    @State private var showSettings = false
    @State private var pendingDelete: ProteinEntry?
    @State private var errorMessage: String?
    let openEntryRequest: UUID?

    init(openEntryRequest: UUID? = nil) {
        self.openEntryRequest = openEntryRequest
    }

    private var goal: Double { settings.first?.dailyProteinGoal ?? 120 }
    private var quickAddSlots: [QuickAddSlotConfiguration] {
        settings.first?.quickAddSlots ?? QuickAddSlotConfiguration.defaults
    }
    private var today: [ProteinEntry] { DailyProteinSummary.entries(for: .now, in: entries) }
    private var summary: DailyProteinSummary { .init(entries: today, goal: goal) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ProteinTheme.Spacing.large) {
                    progressCard
                    quickAdds
                    if let latest = entries.first { repeatLast(latest) }
                    entriesCard
                    PrimaryActionButton(title: "Add protein", systemImage: "plus") { editor = .new }
                }
                .padding(ProteinTheme.Spacing.medium)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
                    .accessibilityHint("Change your protein goal and quick actions")
            }
        }
        .tint(ProteinTheme.Color.accent)
        .sheet(item: $editor) { value in
            EntryEditorSheet(entry: value.entry) { save(value, name: $0, grams: $1, time: $2, note: $3) }
        }
        .sheet(isPresented: $showSettings) {
            ProteinSettingsSheet(goal: goal, quickAddSlots: quickAddSlots, meals: meals, onSave: saveSettings)
        }
        .confirmationDialog("Delete this entry?", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let pendingDelete { delete(pendingDelete) } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { Text("This immediately removes it from today’s total.") }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Please try again.") }
        .task { ensureSettings() }
        .onChange(of: openEntryRequest) { _, request in
            if request != nil { editor = .new }
        }
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
                ForEach(Array(quickAddSlots.enumerated()), id: \.offset) { _, slot in
                    Button { performQuickAdd(slot) } label: {
                        quickAddLabel(slot)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(quickAddAccessibilityLabel(slot))
                    .accessibilityHint("Adds this quick action to today")
                }
            }
        }
    }

    @ViewBuilder
    private func quickAddLabel(_ slot: QuickAddSlotConfiguration) -> some View {
        if let meal = meal(for: slot) {
            VStack(spacing: 1) {
                Text(meal.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(format(meal.grams)) g").font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            Text("+\(format(slot.grams)) g").lineLimit(1).minimumScaleFactor(0.6)
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
                        HStack(spacing: ProteinTheme.Spacing.small) {
                            Button { editor = .edit(entry) } label: {
                                HStack(spacing: ProteinTheme.Spacing.medium) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                        Text(entry.loggedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                                        if let note = entry.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                    Spacer()
                                    Text("\(format(entry.grams)) g").font(.headline.monospacedDigit()).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .accessibilityHint("Double tap to edit")

                            Menu {
                                Button("Edit entry", systemImage: "pencil") { editor = .edit(entry) }
                                Button("Repeat now", systemImage: "arrow.clockwise") { repeatEntry(entry) }
                                Button("Save as meal", systemImage: "bookmark") { saveAsMeal(entry) }
                                Divider()
                                Button("Delete entry", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 44, height: 44)
                                    .background(Color(.tertiarySystemFill), in: Circle())
                            }
                            .accessibilityLabel("Actions for \(entry.name)")
                            .accessibilityHint("Edit, repeat, save, or delete this entry")
                        }
                    }
                }
            }
        }
    }

    private var deleteBinding: Binding<Bool> { .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }) }
    private var errorBinding: Binding<Bool> { .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }) }
    private func repository() -> SwiftDataProteinRepository { .init(context: modelContext) }

    private func ensureSettings() {
        do { try repository().synchronizeWidgetState(at: .now) }
        catch { errorMessage = error.localizedDescription }
    }
    private func quickAdd(_ grams: Double) { do { try repository().addQuickProtein(grams, at: .now) } catch { errorMessage = error.localizedDescription } }
    private func performQuickAdd(_ slot: QuickAddSlotConfiguration) {
        if let meal = meal(for: slot) {
            repeatMeal(meal)
        } else {
            quickAdd(slot.grams)
        }
    }
    private func meal(for slot: QuickAddSlotConfiguration) -> SavedMeal? {
        guard let id = slot.savedMealID else { return nil }
        return meals.first { $0.id == id }
    }
    private func quickAddAccessibilityLabel(_ slot: QuickAddSlotConfiguration) -> String {
        if let meal = meal(for: slot) { return "Add \(meal.name), \(format(meal.grams)) grams" }
        return "Add \(format(slot.grams)) grams"
    }
    private func repeatMeal(_ meal: SavedMeal) { do { try repository().repeatMeal(meal, at: .now) } catch { errorMessage = error.localizedDescription } }
    private func repeatEntry(_ entry: ProteinEntry) { do { try repository().add(ProteinEntry(name: entry.name, grams: entry.grams, note: entry.note)) } catch { errorMessage = error.localizedDescription } }
    private func saveAsMeal(_ entry: ProteinEntry) { do { try repository().add(SavedMeal(name: entry.name, grams: entry.grams, note: entry.note)) } catch { errorMessage = error.localizedDescription } }
    private func delete(_ entry: ProteinEntry) { do { try repository().delete(entry); pendingDelete = nil } catch { errorMessage = error.localizedDescription } }

    private func repeatLast(_ entry: ProteinEntry) -> some View {
        Button { repeatEntry(entry) } label: {
            Label("Repeat \(entry.name)", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: ProteinTheme.Radius.button))
        .accessibilityHint("Creates a new entry now with \(format(entry.grams)) grams")
    }

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

    private func saveSettings(goal: Double, quickAddSlots: [QuickAddSlotConfiguration]) throws {
        try repository().updateSettings(dailyProteinGoal: goal, quickAddSlots: quickAddSlots, at: .now)
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

private struct ProteinSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var goalText: String
    @State private var gramTexts: [String]
    @State private var selectedMealIDs: [UUID?]
    @State private var message: String?
    @FocusState private var focusedField: SettingsField?
    let meals: [SavedMeal]
    let onSave: (Double, [QuickAddSlotConfiguration]) throws -> Void

    private enum SettingsField: Hashable {
        case goal
        case quickAction(Int)
    }

    private let shortcutNames = ["Left shortcut", "Middle shortcut", "Right shortcut"]

    init(
        goal: Double,
        quickAddSlots: [QuickAddSlotConfiguration],
        meals: [SavedMeal],
        onSave: @escaping (Double, [QuickAddSlotConfiguration]) throws -> Void
    ) {
        let slots = QuickAddSlotConfiguration.normalized(quickAddSlots)
        _goalText = .init(initialValue: String(format: "%g", goal))
        _gramTexts = .init(initialValue: slots.map { String(format: "%g", $0.grams) })
        _selectedMealIDs = .init(initialValue: slots.map(\.savedMealID))
        self.meals = meals
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ProteinTheme.Spacing.large) {
                    ProteinCard {
                        VStack(alignment: .leading, spacing: ProteinTheme.Spacing.medium) {
                            Label("Daily goal", systemImage: "target")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Set the target shown on Today and in your progress history.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: ProteinTheme.Spacing.medium) {
                                adjustmentButton(
                                    systemImage: "minus",
                                    accessibilityLabel: "Decrease daily goal"
                                ) { adjustGoal(by: -5) }

                                Spacer(minLength: 0)

                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    TextField("120", text: $goalText)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .frame(maxWidth: 104)
                                        .focused($focusedField, equals: .goal)
                                        .accessibilityLabel("Daily protein goal in grams")
                                    Text("g")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)

                                adjustmentButton(
                                    systemImage: "plus",
                                    accessibilityLabel: "Increase daily goal"
                                ) { adjustGoal(by: 5) }
                            }

                            Text("20–400 g · Adjust in 5 g steps or type a value")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }

                    VStack(alignment: .leading, spacing: ProteinTheme.Spacing.medium) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quick actions").font(.title3.weight(.bold))
                            Text("Choose what appears across the Today screen, from left to right.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(gramTexts.indices, id: \.self) { index in
                            quickActionEditor(index)
                        }

                        if meals.isEmpty {
                            Label("Save a meal from the Meals tab to use it as a shortcut.", systemImage: "bookmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let message {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                    }
                }
                .padding(ProteinTheme.Spacing.medium)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Save changes", systemImage: "checkmark", action: save)
                    .padding(.horizontal, ProteinTheme.Spacing.medium)
                    .padding(.vertical, ProteinTheme.Spacing.small)
                    .background(.ultraThinMaterial)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private func quickActionEditor(_ index: Int) -> some View {
        ProteinCard {
            VStack(alignment: .leading, spacing: ProteinTheme.Spacing.medium) {
                HStack {
                    Label(shortcutNames[index], systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(shortcutPreview(for: index))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ProteinTheme.Color.accent)
                        .lineLimit(1)
                }

                Picker("Adds", selection: mealSelection(for: index)) {
                    Text("Custom protein amount").tag("")
                    ForEach(meals) { meal in
                        Text("\(meal.name) · \(meal.grams.formatted()) g").tag(meal.id.uuidString)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if selectedMealIDs[index] == nil {
                    HStack(spacing: ProteinTheme.Spacing.medium) {
                        adjustmentButton(
                            systemImage: "minus",
                            accessibilityLabel: "Decrease \(shortcutNames[index].lowercased())"
                        ) { adjustQuickAction(at: index, by: -1) }

                        Spacer(minLength: 0)

                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            TextField("Amount", text: $gramTexts[index])
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.title2.bold().monospacedDigit())
                                .frame(maxWidth: 82)
                                .focused($focusedField, equals: .quickAction(index))
                                .accessibilityLabel("\(shortcutNames[index]) protein amount in grams")
                            Text("g").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        adjustmentButton(
                            systemImage: "plus",
                            accessibilityLabel: "Increase \(shortcutNames[index].lowercased())"
                        ) { adjustQuickAction(at: index, by: 1) }
                    }
                } else if let meal = selectedMeal(for: index) {
                    Label("Adds \(meal.name) to today", systemImage: "bookmark.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func adjustmentButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func mealSelection(for index: Int) -> Binding<String> {
        Binding(
            get: { selectedMealIDs[index]?.uuidString ?? "" },
            set: { selectedMealIDs[index] = UUID(uuidString: $0) }
        )
    }

    private func selectedMeal(for index: Int) -> SavedMeal? {
        guard let id = selectedMealIDs[index] else { return nil }
        return meals.first { $0.id == id }
    }

    private func shortcutPreview(for index: Int) -> String {
        if let meal = selectedMeal(for: index) { return meal.name }
        return "+\(gramTexts[index]) g"
    }

    private func adjustGoal(by amount: Double) {
        let current = decimal(from: goalText) ?? 120
        goalText = formattedInput(min(max(current + amount, 20), 400))
        message = nil
    }

    private func adjustQuickAction(at index: Int, by amount: Double) {
        let fallback = QuickAddSlotConfiguration.defaults[index].grams
        let current = decimal(from: gramTexts[index]) ?? fallback
        gramTexts[index] = formattedInput(min(max(current + amount, 1), ProteinEntryValidator.maximumGrams))
        message = nil
    }

    private func save() {
        guard let goal = decimal(from: goalText), (20...400).contains(goal) else {
            message = "Choose a daily goal between 20 g and 400 g."
            return
        }

        var slots: [QuickAddSlotConfiguration] = []
        for index in gramTexts.indices {
            guard let grams = decimal(from: gramTexts[index]), grams > 0, grams <= ProteinEntryValidator.maximumGrams else {
                message = "Each protein amount must be between 0 and 300 g."
                return
            }
            if let mealID = selectedMealIDs[index], !meals.contains(where: { $0.id == mealID }) {
                message = "One selected meal is no longer available. Choose another meal."
                return
            }
            slots.append(QuickAddSlotConfiguration(grams: grams, savedMealID: selectedMealIDs[index]))
        }

        do {
            try onSave(goal, slots)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func decimal(from text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func formattedInput(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

#Preview("Light") { DashboardView().modelContainer(try! PersistenceController.makeInMemory()) }
#Preview("Dark") { DashboardView().modelContainer(try! PersistenceController.makeInMemory()).preferredColorScheme(.dark) }
#Preview("Large Dynamic Type") { DashboardView().modelContainer(try! PersistenceController.makeInMemory()).environment(\.dynamicTypeSize, .accessibility3) }
