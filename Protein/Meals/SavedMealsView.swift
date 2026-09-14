import ProteinCore
import SwiftData
import SwiftUI

struct SavedMealsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedMeal.name) private var meals: [SavedMeal]
    @State private var editor: SavedMealEditor?
    @State private var pendingDelete: SavedMeal?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if meals.isEmpty { ContentUnavailableView("No saved meals", systemImage: "bookmark", description: Text("Save a common meal to log it again in one tap.")) }
                else {
                    List(meals) { meal in row(meal) }
                        .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Saved meals")
            .toolbar { Button("New meal", systemImage: "plus") { editor = .new } }
        }
        .sheet(item: $editor) { value in SavedMealEditorSheet(meal: value.meal) { save(value, name: $0, grams: $1) } }
        .confirmationDialog("Delete saved meal?", isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) { if let pendingDelete { delete(pendingDelete) } }
        } message: { Text("Existing protein entries will not be changed.") }
        .alert("Saved meals", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
    }

    private func row(_ meal: SavedMeal) -> some View {
        VStack(alignment: .leading, spacing: ProteinTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.name).font(.headline)
                    Text("\(meal.grams.formatted()) g protein").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit", systemImage: "pencil") { editor = .edit(meal) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit \(meal.name)")
            }
            Button { repeatMeal(meal) } label: {
                Label("Add to today", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: ProteinTheme.Radius.button))
            .accessibilityLabel("Add \(meal.name), \(meal.grams.formatted()) grams to today")
        }
            .padding(.vertical, ProteinTheme.Spacing.small)
            .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = meal } }
    }
    private func repository() -> SwiftDataProteinRepository { .init(context: modelContext) }
    private func repeatMeal(_ meal: SavedMeal) { do { try repository().repeatMeal(meal, at: .now); message = "\(meal.name) added to today." } catch { message = error.localizedDescription } }
    private func delete(_ meal: SavedMeal) { do { try repository().delete(meal); pendingDelete = nil } catch { message = error.localizedDescription } }
    private func save(_ editor: SavedMealEditor, name: String, grams: Double) { do { try ProteinEntryValidator.validate(name: name, grams: grams); if let meal = editor.meal { meal.name = name; meal.grams = grams; try repository().save() } else { try repository().add(SavedMeal(name: name, grams: grams)) }; self.editor = nil } catch { message = error.localizedDescription } }
}

@MainActor private struct SavedMealEditor: Identifiable { let id = UUID(); let meal: SavedMeal?; static let new = Self(meal: nil); static func edit(_ meal: SavedMeal) -> Self { .init(meal: meal) } }
private struct SavedMealEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String; @State private var grams: String; @State private var validation: String?
    let meal: SavedMeal?; let onSave: (String, Double) -> Void
    init(meal: SavedMeal?, onSave: @escaping (String, Double) -> Void) { self.meal = meal; self.onSave = onSave; _name = .init(initialValue: meal?.name ?? ""); _grams = .init(initialValue: meal.map { String(format: "%g", $0.grams) } ?? "") }
    var body: some View { NavigationStack { Form { TextField("Meal name", text: $name); TextField("Protein grams", text: $grams).keyboardType(.decimalPad); if let validation { Text(validation).foregroundStyle(.red) } }.navigationTitle(meal == nil ? "New meal" : "Rename meal").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) } } } }
    private func save() { guard let value = Double(grams.replacingOccurrences(of: ",", with: ".")) else { validation = "Enter a valid protein amount."; return }; do { try ProteinEntryValidator.validate(name: name, grams: value); onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), value) } catch { validation = error.localizedDescription } }
}
