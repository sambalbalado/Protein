import Foundation

public enum AppGroup {
    public static var identifier: String {
        Bundle.main.object(forInfoDictionaryKey: "ProteinAppGroupIdentifier") as? String
            ?? "group.com.example.Protein"
    }
    public static let widgetKind = "ProteinWidget"
    public static let widgetStateKey = "proteinWidgetState.v1"
    public static let todayProteinKey = "todayProteinGrams"
    public static let todayGoalKey = "todayProteinGoal"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

public struct ProteinWidgetState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let dayStart: Date
    public let total: Double
    public let goal: Double
    public let lastUpdated: Date
    public let latestEntryName: String?
    public let latestEntryGrams: Double?

    public var progress: Double {
        guard goal > 0 else { return 0 }
        return total / goal
    }

    public var canRepeatLatestEntry: Bool {
        guard
            let latestEntryName,
            !latestEntryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let latestEntryGrams
        else { return false }
        return latestEntryGrams.isFinite && latestEntryGrams > 0
    }

    public init(
        version: Int = currentVersion,
        dayStart: Date,
        total: Double,
        goal: Double,
        lastUpdated: Date,
        latestEntryName: String? = nil,
        latestEntryGrams: Double? = nil
    ) {
        self.version = version
        self.dayStart = dayStart
        self.total = total
        self.goal = goal
        self.lastUpdated = lastUpdated
        self.latestEntryName = latestEntryName
        self.latestEntryGrams = latestEntryGrams
    }

    public static func empty(
        at date: Date,
        goal: Double = 120,
        calendar: Calendar = .current,
        lastUpdated: Date? = nil,
        latestEntryName: String? = nil,
        latestEntryGrams: Double? = nil
    ) -> Self {
        .init(
            dayStart: calendar.startOfDay(for: date),
            total: 0,
            goal: goal,
            lastUpdated: lastUpdated ?? date,
            latestEntryName: latestEntryName,
            latestEntryGrams: latestEntryGrams
        )
    }
}

public enum ProteinWidgetStateStore {
    public static func read(
        defaults: UserDefaults = AppGroup.defaults,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> ProteinWidgetState {
        if
            let data = defaults.data(forKey: AppGroup.widgetStateKey),
            let stored = try? JSONDecoder().decode(ProteinWidgetState.self, from: data),
            stored.version == ProteinWidgetState.currentVersion
        {
            guard calendar.isDate(stored.dayStart, inSameDayAs: date) else {
                return .empty(
                    at: date,
                    goal: stored.goal,
                    calendar: calendar,
                    lastUpdated: stored.lastUpdated,
                    latestEntryName: stored.latestEntryName,
                    latestEntryGrams: stored.latestEntryGrams
                )
            }
            return stored
        }

        let legacyTotal = defaults.object(forKey: AppGroup.todayProteinKey).map { _ in
            defaults.double(forKey: AppGroup.todayProteinKey)
        } ?? 0
        let legacyGoal = defaults.object(forKey: AppGroup.todayGoalKey).map { _ in
            defaults.double(forKey: AppGroup.todayGoalKey)
        } ?? 120
        return .init(
            dayStart: calendar.startOfDay(for: date),
            total: max(legacyTotal, 0),
            goal: legacyGoal > 0 ? legacyGoal : 120,
            lastUpdated: date
        )
    }

    public static func write(
        _ state: ProteinWidgetState,
        defaults: UserDefaults = AppGroup.defaults
    ) throws {
        defaults.set(try JSONEncoder().encode(state), forKey: AppGroup.widgetStateKey)
        defaults.removeObject(forKey: AppGroup.todayProteinKey)
        defaults.removeObject(forKey: AppGroup.todayGoalKey)
    }
}

public enum ProteinDeepLink: Equatable, Sendable {
    case preciseEntry

    public static let preciseEntryURL = URL(string: "protein://log")!

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "protein", url.host?.lowercased() == "log" else {
            return nil
        }
        self = .preciseEntry
    }
}
