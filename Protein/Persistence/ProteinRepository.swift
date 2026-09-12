import Foundation
import SwiftData

@MainActor
public protocol ProteinRepository: AnyObject {
    func entries(from start: Date, to end: Date) throws -> [ProteinEntry]
    func add(_ entry: ProteinEntry) throws
    func save() throws
    func delete(_ entry: ProteinEntry) throws
    func savedMeals() throws -> [SavedMeal]
    func goalChanges() throws -> [ProteinGoalChange]
    func add(_ meal: SavedMeal) throws
    func delete(_ meal: SavedMeal) throws
    func repeatMeal(_ meal: SavedMeal, at date: Date) throws
    func updateGoal(_ grams: Double, at date: Date) throws
    func settings() throws -> UserSettings
}

@MainActor
public final class SwiftDataProteinRepository: ProteinRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func entries(from start: Date, to end: Date) throws -> [ProteinEntry] {
        let predicate = #Predicate<ProteinEntry> { entry in
            entry.loggedAt >= start && entry.loggedAt < end
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func add(_ entry: ProteinEntry) throws {
        context.insert(entry)
        try context.save()
    }

    public func save() throws {
        try context.save()
    }

    public func delete(_ entry: ProteinEntry) throws {
        context.delete(entry)
        try context.save()
    }

    public func savedMeals() throws -> [SavedMeal] {
        let descriptor = FetchDescriptor<SavedMeal>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func goalChanges() throws -> [ProteinGoalChange] {
        try context.fetch(FetchDescriptor<ProteinGoalChange>(sortBy: [SortDescriptor(\.effectiveAt)]))
    }

    public func add(_ meal: SavedMeal) throws {
        context.insert(meal)
        try context.save()
    }

    public func delete(_ meal: SavedMeal) throws {
        context.delete(meal)
        try context.save()
    }

    public func repeatMeal(_ meal: SavedMeal, at date: Date = .now) throws {
        meal.lastUsedAt = date
        context.insert(ProteinEntry(name: meal.name, grams: meal.grams, loggedAt: date, note: meal.note))
        try context.save()
    }

    public func updateGoal(_ grams: Double, at date: Date = .now) throws {
        let current = try settings()
        current.dailyProteinGoal = grams
        context.insert(ProteinGoalChange(grams: grams, effectiveAt: date))
        try context.save()
    }

    public func settings() throws -> UserSettings {
        var descriptor = FetchDescriptor<UserSettings>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            if try goalChanges().isEmpty {
                context.insert(ProteinGoalChange(grams: existing.dailyProteinGoal, effectiveAt: .distantPast))
                try context.save()
            }
            return existing
        }

        let settings = UserSettings()
        context.insert(settings)
        context.insert(ProteinGoalChange(grams: settings.dailyProteinGoal, effectiveAt: .distantPast))
        try context.save()
        return settings
    }
}
