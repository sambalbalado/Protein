import SwiftData
import XCTest
@testable import ProteinCore

@MainActor
final class ProteinPersistenceTests: XCTestCase {
    func testWidgetQuickAddsCreateExactlyOneEntryPerTapAndSynchronizeTotal() throws {
        let container = try PersistenceController.makeInMemory()
        let suite = "ProteinWidgetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-15T12:00:00Z"))
        let repository = SwiftDataProteinRepository(
            context: container.mainContext,
            widgetDefaults: defaults,
            widgetCalendar: calendar,
            widgetNow: { now },
            reloadWidgetTimelines: false
        )

        try repository.addQuickProtein(5, at: now)
        XCTAssertEqual(try repository.entries(from: calendar.startOfDay(for: now), to: now.addingTimeInterval(43_200)).count, 1)
        XCTAssertEqual(ProteinWidgetStateStore.read(defaults: defaults, at: now, calendar: calendar).total, 5)

        try repository.addQuickProtein(10, at: now)
        let entries = try repository.entries(from: calendar.startOfDay(for: now), to: now.addingTimeInterval(43_200))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.grams }, 15)
        XCTAssertEqual(ProteinWidgetStateStore.read(defaults: defaults, at: now, calendar: calendar).total, 15)

        try repository.delete(try XCTUnwrap(entries.first(where: { $0.grams == 10 })))
        XCTAssertEqual(ProteinWidgetStateStore.read(defaults: defaults, at: now, calendar: calendar).total, 5)
    }

    func testWidgetRepeatCreatesOneEntryFromLatestEligibleEntry() throws {
        let container = try PersistenceController.makeInMemory()
        let suite = "ProteinWidgetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-15T12:00:00Z"))
        let repository = SwiftDataProteinRepository(
            context: container.mainContext,
            widgetDefaults: defaults,
            widgetCalendar: calendar,
            widgetNow: { now },
            reloadWidgetTimelines: false
        )
        try repository.add(ProteinEntry(name: "Tofu bowl", grams: 24, loggedAt: now.addingTimeInterval(-60), note: "Lunch"))

        XCTAssertTrue(try repository.repeatLatestEligibleEntry(at: now))

        let entries = try repository.entries(from: calendar.startOfDay(for: now), to: now.addingTimeInterval(1))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.grams), [24, 24])
        XCTAssertEqual(entries.first?.name, "Tofu bowl")
        XCTAssertEqual(ProteinWidgetStateStore.read(defaults: defaults, at: now, calendar: calendar).total, 48)
    }

    func testWidgetStateMigratesLegacyTotalAndRollsOverAtLocalMidnight() throws {
        let suite = "ProteinWidgetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let day = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T19:00:00Z"))
        defaults.set(35, forKey: AppGroup.todayProteinKey)
        defaults.set(110, forKey: AppGroup.todayGoalKey)

        let migrated = ProteinWidgetStateStore.read(defaults: defaults, at: day, calendar: calendar)
        XCTAssertEqual(migrated.total, 35)
        XCTAssertEqual(migrated.goal, 110)

        let current = ProteinWidgetState(
            dayStart: calendar.startOfDay(for: day),
            total: 70,
            goal: 110,
            lastUpdated: day,
            latestEntryName: "Tempeh",
            latestEntryGrams: 22
        )
        try ProteinWidgetStateStore.write(current, defaults: defaults)
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)))
        let rolledOver = ProteinWidgetStateStore.read(defaults: defaults, at: nextDay, calendar: calendar)

        XCTAssertEqual(rolledOver.total, 0)
        XCTAssertEqual(rolledOver.goal, 110)
        XCTAssertEqual(rolledOver.latestEntryName, "Tempeh")
        XCTAssertTrue(rolledOver.canRepeatLatestEntry)
        XCTAssertNil(defaults.object(forKey: AppGroup.todayProteinKey))
    }

    func testWidgetStateFallsBackSafelyWhenDataIsMissingOrUnknown() throws {
        let suite = "ProteinWidgetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(ProteinWidgetStateStore.read(defaults: defaults, at: now).total, 0)
        defaults.set(Data("not-json".utf8), forKey: AppGroup.widgetStateKey)
        XCTAssertEqual(ProteinWidgetStateStore.read(defaults: defaults, at: now).goal, 120)
    }

    func testPreciseEntryDeepLinkAcceptsOnlyTheLoggingDestination() throws {
        XCTAssertEqual(ProteinDeepLink(url: ProteinDeepLink.preciseEntryURL), .preciseEntry)
        XCTAssertNil(ProteinDeepLink(url: try XCTUnwrap(URL(string: "protein://estimate"))))
        XCTAssertNil(ProteinDeepLink(url: try XCTUnwrap(URL(string: "https://example.com/log"))))
    }

    func testInsightsUseDateRangeTotalsAndHistoricalGoals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z"))
        let entries = [
            ProteinEntry(name: "A", grams: 40, loggedAt: start.addingTimeInterval(3_600)),
            ProteinEntry(name: "B", grams: 50, loggedAt: start.addingTimeInterval(86_400 + 3_600)),
            ProteinEntry(name: "Midnight", grams: 10, loggedAt: start.addingTimeInterval(172_800))
        ]
        let goals = [
            ProteinGoalChange(grams: 100, effectiveAt: .distantPast),
            ProteinGoalChange(grams: 80, effectiveAt: start.addingTimeInterval(86_400))
        ]

        let days = ProteinInsights.days(from: start, through: start.addingTimeInterval(172_800), entries: entries, goalChanges: goals, fallbackGoal: 120, calendar: calendar)

        XCTAssertEqual(days.map(\.total), [40, 50, 10])
        XCTAssertEqual(days.map(\.goal), [100, 80, 80])
        XCTAssertEqual(days.map(\.entryCount), [1, 1, 1])
    }

    func testSavedMealCanBeCreatedRenamedRepeatedAndDeleted() throws {
        let container = try PersistenceController.makeInMemory()
        let repository = SwiftDataProteinRepository(context: container.mainContext)
        let meal = SavedMeal(name: "Yogurt", grams: 20)
        try repository.add(meal)
        XCTAssertEqual(try repository.savedMeals().count, 1)

        meal.name = "Greek yogurt"
        try repository.save()
        XCTAssertEqual(try repository.savedMeals().first?.name, "Greek yogurt")

        let repeatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try repository.repeatMeal(meal, at: repeatedAt)
        let repeated = try repository.entries(from: repeatedAt, to: repeatedAt.addingTimeInterval(1))
        XCTAssertEqual(repeated.first?.name, "Greek yogurt")
        XCTAssertEqual(repeated.first?.loggedAt, repeatedAt)
        XCTAssertEqual(meal.lastUsedAt, repeatedAt)

        try repository.delete(meal)
        XCTAssertTrue(try repository.savedMeals().isEmpty)
        XCTAssertEqual(repeated.count, 1)
    }

    func testQuickActionsPersistCustomAmountsAndSavedMeals() throws {
        let container = try PersistenceController.makeInMemory()
        let repository = SwiftDataProteinRepository(context: container.mainContext)
        let meal = SavedMeal(name: "Greek yogurt", grams: 20)
        try repository.add(meal)
        let slots = [
            QuickAddSlotConfiguration(grams: 7),
            QuickAddSlotConfiguration(grams: 10, savedMealID: meal.id),
            QuickAddSlotConfiguration(grams: 30)
        ]

        try repository.updateSettings(dailyProteinGoal: 135, quickAddSlots: slots, at: .now)

        let settings = try repository.settings()
        XCTAssertEqual(settings.dailyProteinGoal, 135)
        XCTAssertEqual(settings.quickAddSlots, slots)
        XCTAssertEqual(settings.quickAddSlots[1].savedMealID, meal.id)
    }

    func testDeletingSavedMealFallsBackToConfiguredProteinAmount() throws {
        let container = try PersistenceController.makeInMemory()
        let repository = SwiftDataProteinRepository(context: container.mainContext)
        let meal = SavedMeal(name: "Tofu bowl", grams: 24)
        try repository.add(meal)
        let slots = [
            QuickAddSlotConfiguration(grams: 5),
            QuickAddSlotConfiguration(grams: 12, savedMealID: meal.id),
            QuickAddSlotConfiguration(grams: 25)
        ]
        try repository.updateSettings(dailyProteinGoal: 120, quickAddSlots: slots, at: .now)

        try repository.delete(meal)

        let fallback = try repository.settings().quickAddSlots[1]
        XCTAssertNil(fallback.savedMealID)
        XCTAssertEqual(fallback.grams, 12)
    }

    func testEntryValidationRejectsInvalidValues() {
        XCTAssertThrowsError(try ProteinEntryValidator.validate(name: " ", grams: 20))
        XCTAssertThrowsError(try ProteinEntryValidator.validate(name: "Eggs", grams: 0))
        XCTAssertThrowsError(try ProteinEntryValidator.validate(name: "Eggs", grams: -1))
        XCTAssertThrowsError(try ProteinEntryValidator.validate(name: "Eggs", grams: 301))
        XCTAssertNoThrow(try ProteinEntryValidator.validate(name: "Eggs", grams: 20))
    }

    func testDailyAggregationSupportsGoalStates() {
        XCTAssertEqual(DailyProteinSummary(entries: [], goal: 100).progress, 0)
        XCTAssertEqual(DailyProteinSummary(entries: [ProteinEntry(name: "A", grams: 40)], goal: 100).remaining, 60)
        XCTAssertEqual(DailyProteinSummary(entries: [ProteinEntry(name: "A", grams: 100)], goal: 100).progress, 1)
        let exceeded = DailyProteinSummary(entries: [ProteinEntry(name: "A", grams: 125)], goal: 100)
        XCTAssertEqual(exceeded.remaining, 0)
        XCTAssertEqual(exceeded.progress, 1.25)
    }

    func testDailyGroupingUsesProvidedTimeZone() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-13T01:00:00Z"))
        let entry = ProteinEntry(name: "Late meal", grams: 20, loggedAt: date)
        XCTAssertEqual(DailyProteinSummary.entries(for: date, in: [entry], calendar: utc).count, 1)
        let nextDay = try XCTUnwrap(utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: date)))
        XCTAssertTrue(DailyProteinSummary.entries(for: nextDay, in: [entry], calendar: utc).isEmpty)
        XCTAssertEqual(losAngeles.component(.day, from: entry.loggedAt), 12)
    }

    func testEditingAndDeletingImmediatelyChangeDerivedTotal() throws {
        let container = try PersistenceController.makeInMemory()
        let repository = SwiftDataProteinRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = ProteinEntry(name: "Tofu", grams: 20, loggedAt: start.addingTimeInterval(60))
        try repository.add(entry)
        entry.grams = 30
        try repository.save()
        var fetched = try repository.entries(from: start, to: start.addingTimeInterval(3_600))
        XCTAssertEqual(DailyProteinSummary(entries: fetched, goal: 120).total, 30)
        try repository.delete(entry)
        fetched = try repository.entries(from: start, to: start.addingTimeInterval(3_600))
        XCTAssertEqual(DailyProteinSummary(entries: fetched, goal: 120).total, 0)
    }

    func testInMemoryStorePersistsAndFetchesAnEntry() throws {
        let container = try PersistenceController.makeInMemory()
        let repository = SwiftDataProteinRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = ProteinEntry(name: "Greek yogurt", grams: 20, loggedAt: start.addingTimeInterval(60))

        try repository.add(entry)
        let entries = try repository.entries(from: start, to: start.addingTimeInterval(3_600))

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "Greek yogurt")
        XCTAssertEqual(entries.first?.grams, 20)
    }

    func testSettingsAreCreatedOnceWithSensibleDefault() throws {
        let container = try PersistenceController.makeInMemory()
        let repository = SwiftDataProteinRepository(context: container.mainContext)

        let first = try repository.settings()
        let second = try repository.settings()

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.dailyProteinGoal, 120)
        XCTAssertEqual(first.quickAddSlots, QuickAddSlotConfiguration.defaults)
    }
}
