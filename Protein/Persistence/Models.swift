import Foundation
import SwiftData

@Model
public final class ProteinEntry {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var grams: Double
    public var loggedAt: Date
    public var note: String?

    public init(
        id: UUID = UUID(),
        name: String,
        grams: Double,
        loggedAt: Date = .now,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.grams = grams
        self.loggedAt = loggedAt
        self.note = note
    }
}

@Model
public final class SavedMeal {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var grams: Double
    public var note: String?
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        grams: Double,
        note: String? = nil,
        createdAt: Date = .now,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.grams = grams
        self.note = note
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

@Model
public final class UserSettings {
    @Attribute(.unique) public var id: UUID
    public var dailyProteinGoal: Double

    public init(id: UUID = UUID(), dailyProteinGoal: Double = 120) {
        self.id = id
        self.dailyProteinGoal = dailyProteinGoal
    }
}

@Model
public final class ProteinGoalChange {
    @Attribute(.unique) public var id: UUID
    public var grams: Double
    public var effectiveAt: Date

    public init(id: UUID = UUID(), grams: Double, effectiveAt: Date = .now) {
        self.id = id
        self.grams = grams
        self.effectiveAt = effectiveAt
    }
}

public enum ProteinEntryValidationError: LocalizedError, Equatable {
    case missingName, nonFiniteGrams, nonPositiveGrams, implausibleGrams

    public var errorDescription: String? {
        switch self {
        case .missingName: "Add a food name."
        case .nonFiniteGrams: "Enter a valid protein amount."
        case .nonPositiveGrams: "Protein must be greater than 0 g."
        case .implausibleGrams: "That amount looks unusually high. Enter 300 g or less per item."
        }
    }
}

public enum ProteinEntryValidator {
    public static let maximumGrams = 300.0

    public static func validate(name: String, grams: Double) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProteinEntryValidationError.missingName }
        guard grams.isFinite else { throw ProteinEntryValidationError.nonFiniteGrams }
        guard grams > 0 else { throw ProteinEntryValidationError.nonPositiveGrams }
        guard grams <= maximumGrams else { throw ProteinEntryValidationError.implausibleGrams }
    }
}

public struct DailyProteinSummary: Equatable, Sendable {
    public let total: Double
    public let goal: Double
    public var remaining: Double { max(goal - total, 0) }
    public var progress: Double { goal > 0 ? total / goal : 0 }

    public init(entries: [ProteinEntry], goal: Double) {
        total = entries.reduce(0) { $0 + $1.grams }
        self.goal = goal
    }

    public static func entries(for date: Date, in entries: [ProteinEntry], calendar: Calendar = .current) -> [ProteinEntry] {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return [] }
        return entries.filter { interval.contains($0.loggedAt) }
    }
}

public struct ProteinDay: Equatable, Identifiable, Sendable {
    public let date: Date
    public let total: Double
    public let goal: Double
    public let entryCount: Int
    public var id: Date { date }
    public var progress: Double { goal > 0 ? total / goal : 0 }
    public var hasData: Bool { entryCount > 0 }

    public init(date: Date, total: Double, goal: Double, entryCount: Int) {
        self.date = date
        self.total = total
        self.goal = goal
        self.entryCount = entryCount
    }
}

public enum ProteinInsights {
    public static func days(
        from start: Date,
        through end: Date,
        entries: [ProteinEntry],
        goalChanges: [ProteinGoalChange],
        fallbackGoal: Double,
        calendar: Calendar = .current
    ) -> [ProteinDay] {
        var result: [ProteinDay] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        let orderedGoals = goalChanges.sorted { $0.effectiveAt < $1.effectiveAt }
        let entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.loggedAt) }

        while day <= last {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let dayEntries = entriesByDay[day] ?? []
            let goal = orderedGoals.last(where: { $0.effectiveAt < next })?.grams ?? fallbackGoal
            result.append(ProteinDay(date: day, total: dayEntries.reduce(0) { $0 + $1.grams }, goal: goal, entryCount: dayEntries.count))
            day = next
        }
        return result
    }
}
