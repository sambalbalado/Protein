import SwiftData
import XCTest
@testable import ProteinCore

@MainActor
final class ProteinPersistenceTests: XCTestCase {
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
