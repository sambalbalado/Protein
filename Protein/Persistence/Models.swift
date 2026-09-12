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
