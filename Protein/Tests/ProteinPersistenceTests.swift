import SwiftData
import XCTest
@testable import ProteinCore

@MainActor
final class ProteinPersistenceTests: XCTestCase {
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
    }
}
