import Foundation
import SwiftData

@MainActor
public protocol ProteinRepository: AnyObject {
    func entries(from start: Date, to end: Date) throws -> [ProteinEntry]
    func add(_ entry: ProteinEntry) throws
    func delete(_ entry: ProteinEntry) throws
    func savedMeals() throws -> [SavedMeal]
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

    public func settings() throws -> UserSettings {
        var descriptor = FetchDescriptor<UserSettings>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let settings = UserSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}
