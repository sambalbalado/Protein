import SwiftData
import XCTest
@testable import ProteinCore

@MainActor
final class ProteinPersistenceTests: XCTestCase {
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
