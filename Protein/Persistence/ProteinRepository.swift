import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
public protocol ProteinRepository: AnyObject {
    func entries(from start: Date, to end: Date) throws -> [ProteinEntry]
    func add(_ entry: ProteinEntry) throws
    func add(_ entries: [ProteinEntry]) throws
    func addQuickProtein(_ grams: Double, at date: Date) throws
    func repeatLatestEligibleEntry(at date: Date) throws -> Bool
    func latestEligibleEntry(before date: Date) throws -> ProteinEntry?
    @discardableResult func synchronizeWidgetState(at date: Date) throws -> ProteinWidgetState
    func save() throws
    func delete(_ entry: ProteinEntry) throws
    func savedMeals() throws -> [SavedMeal]
    func goalChanges() throws -> [ProteinGoalChange]
    func add(_ meal: SavedMeal) throws
    func delete(_ meal: SavedMeal) throws
    func repeatMeal(_ meal: SavedMeal, at date: Date) throws
    func updateGoal(_ grams: Double, at date: Date) throws
    func updateSettings(dailyProteinGoal: Double, quickAddSlots: [QuickAddSlotConfiguration], at date: Date) throws
    func settings() throws -> UserSettings
}

@MainActor
public final class SwiftDataProteinRepository: ProteinRepository {
    private let context: ModelContext
    private let widgetDefaults: UserDefaults
    private let widgetCalendar: Calendar
    private let widgetNow: () -> Date
    private let reloadWidgetTimelines: Bool

    public init(
        context: ModelContext,
        widgetDefaults: UserDefaults = AppGroup.defaults,
        widgetCalendar: Calendar = .current,
        widgetNow: @escaping () -> Date = { .now },
        reloadWidgetTimelines: Bool = true
    ) {
        self.context = context
        self.widgetDefaults = widgetDefaults
        self.widgetCalendar = widgetCalendar
        self.widgetNow = widgetNow
        self.reloadWidgetTimelines = reloadWidgetTimelines
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
        try synchronizeWidgetState(at: widgetNow())
    }

    public func add(_ entries: [ProteinEntry]) throws {
        do {
            entries.forEach(context.insert)
            try context.save()
            try synchronizeWidgetState(at: widgetNow())
        } catch {
            context.rollback()
            throw error
        }
    }

    public func addQuickProtein(_ grams: Double, at date: Date = .now) throws {
        try ProteinEntryValidator.validate(name: "Quick add", grams: grams)
        try add(ProteinEntry(name: "Quick add", grams: grams, loggedAt: date))
    }

    public func repeatLatestEligibleEntry(at date: Date = .now) throws -> Bool {
        guard let latest = try latestEligibleEntry(before: date) else { return false }
        try ProteinEntryValidator.validate(name: latest.name, grams: latest.grams)
        try add(ProteinEntry(name: latest.name, grams: latest.grams, loggedAt: date, note: latest.note))
        return true
    }

    public func latestEligibleEntry(before date: Date = .now) throws -> ProteinEntry? {
        let predicate = #Predicate<ProteinEntry> { entry in
            entry.loggedAt <= date
        }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        return try context.fetch(descriptor).first { entry in
            (try? ProteinEntryValidator.validate(name: entry.name, grams: entry.grams)) != nil
        }
    }

    @discardableResult
    public func synchronizeWidgetState(at date: Date = .now) throws -> ProteinWidgetState {
        guard let interval = widgetCalendar.dateInterval(of: .day, for: date) else {
            let state = ProteinWidgetState.empty(at: date, calendar: widgetCalendar)
            try ProteinWidgetStateStore.write(state, defaults: widgetDefaults)
            reloadWidget()
            return state
        }

        let currentSettings = try settings()
        let todayEntries = try entries(from: interval.start, to: interval.end)
        let latest = try latestEligibleEntry(before: date)
        let state = ProteinWidgetState(
            dayStart: interval.start,
            total: todayEntries.reduce(0) { $0 + $1.grams },
            goal: currentSettings.dailyProteinGoal,
            lastUpdated: date,
            latestEntryName: latest?.name,
            latestEntryGrams: latest?.grams
        )
        try ProteinWidgetStateStore.write(state, defaults: widgetDefaults)
        reloadWidget()
        return state
    }

    public func save() throws {
        try context.save()
        try synchronizeWidgetState(at: widgetNow())
    }

    public func delete(_ entry: ProteinEntry) throws {
        context.delete(entry)
        try context.save()
        try synchronizeWidgetState(at: widgetNow())
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
        var descriptor = FetchDescriptor<UserSettings>()
        descriptor.fetchLimit = 1
        if let currentSettings = try context.fetch(descriptor).first {
            currentSettings.quickAddSlots = currentSettings.quickAddSlots.map { slot in
                guard slot.savedMealID == meal.id else { return slot }
                return QuickAddSlotConfiguration(grams: slot.grams)
            }
        }
        context.delete(meal)
        try context.save()
    }

    public func repeatMeal(_ meal: SavedMeal, at date: Date = .now) throws {
        meal.lastUsedAt = date
        context.insert(ProteinEntry(name: meal.name, grams: meal.grams, loggedAt: date, note: meal.note))
        try context.save()
        try synchronizeWidgetState(at: date)
    }

    public func updateGoal(_ grams: Double, at date: Date = .now) throws {
        let current = try settings()
        try updateSettings(dailyProteinGoal: grams, quickAddSlots: current.quickAddSlots, at: date)
    }

    public func updateSettings(
        dailyProteinGoal: Double,
        quickAddSlots: [QuickAddSlotConfiguration],
        at date: Date = .now
    ) throws {
        guard dailyProteinGoal.isFinite, (20...400).contains(dailyProteinGoal) else {
            throw ProteinSettingsValidationError.invalidGoal
        }
        for slot in quickAddSlots {
            try ProteinEntryValidator.validate(name: "Quick add", grams: slot.grams)
        }

        let current = try settings()
        if current.dailyProteinGoal != dailyProteinGoal {
            current.dailyProteinGoal = dailyProteinGoal
            context.insert(ProteinGoalChange(grams: dailyProteinGoal, effectiveAt: date))
        }
        current.quickAddSlots = quickAddSlots
        try context.save()
        try synchronizeWidgetState(at: date)
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

    private func reloadWidget() {
#if canImport(WidgetKit)
        guard reloadWidgetTimelines else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
#endif
    }
}
