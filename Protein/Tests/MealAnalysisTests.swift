import Foundation
import XCTest
@testable import ProteinCore

@MainActor
final class MealAnalysisTests: XCTestCase {
    private let request = MealImageRequest(imageData: Data([1, 2, 3]), mimeType: "image/jpeg")

    func testDecodingValidResponseProducesEditableDraft() throws {
        let json = """
        {"foods":[{"id":"0F4A2D7B-54AA-49F2-8EB9-BF07A6C8FD05","name":"Chicken","assumedPortion":"One breast","proteinGrams":38,"confidence":0.88}],"totalProteinGrams":38,"warnings":["Estimated portion"]}
        """.data(using: .utf8)!

        let draft = try MealAnalysisDecoder.decode(json)

        XCTAssertEqual(draft.items.first?.name, "Chicken")
        XCTAssertEqual(draft.totalProteinGrams, 38)
        XCTAssertFalse(draft.hasLowConfidenceItems)
    }

    func testMalformedPartialAndInconsistentResponsesAreRejected() async throws {
        let partial = Data("{\"foods\":[{\"name\":\"Chicken\"}]}".utf8)
        XCTAssertThrowsError(try MealAnalysisDecoder.decode(partial))

        let inconsistent = MealAnalysisResult(
            foods: [.init(name: "Chicken", assumedPortion: "One breast", proteinGrams: 38, confidence: 0.8)],
            totalProteinGrams: 90
        )
        XCTAssertThrowsError(try inconsistent.validated())

        let malformed = try await MockMealAnalysisService(fixture: .malformed).analyze(request)
        XCTAssertThrowsError(try malformed.validated())
    }

    func testLowConfidenceIsFlaggedAndDraftRemainsEditable() async throws {
        let result = try await MockMealAnalysisService(fixture: .lowConfidence).analyze(request)
        var draft = try result.validated()
        XCTAssertTrue(draft.hasLowConfidenceItems)

        draft.items[0].name = "Tofu and vegetables"
        draft.items[0].proteinGrams = 27
        let entries = try draft.entries(loggedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(entries.first?.name, "Tofu and vegetables")
        XCTAssertEqual(entries.first?.grams, 27)
        XCTAssertTrue(entries.first?.note?.contains("estimate") == true)
    }

    func testServiceFixturesReturnStableErrors() async throws {
        await assertFixture(.refusal, equals: .refused("This image could not be analyzed as a meal."))
        await assertFixture(.timeout, equals: .timedOut)
        await assertFixture(.noNetwork, equals: .noNetwork)
    }

    func testCancellationIsMappedWithoutReturningData() async {
        let task = Task {
            try await MockMealAnalysisService(fixture: .success, delay: .seconds(30)).analyze(request)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled analysis returned data") }
        catch { XCTAssertEqual(error as? MealAnalysisError, .cancelled) }
    }

    func testDraftDoesNotPersistUntilExplicitConfirmation() throws {
        let container = try PersistenceController.makeInMemory()
        let repository = SwiftDataProteinRepository(context: container.mainContext)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = try MealAnalysisResult(
            foods: [.init(name: "Eggs", assumedPortion: "Three eggs", proteinGrams: 18, confidence: 0.9)],
            totalProteinGrams: 18
        ).validated()

        XCTAssertTrue(try repository.entries(from: date, to: date.addingTimeInterval(1)).isEmpty)
        try repository.add(draft.entries(loggedAt: date))
        XCTAssertEqual(try repository.entries(from: date, to: date.addingTimeInterval(1)).count, 1)
    }

    func testConfigurationRequiresSecureExternalURL() throws {
        XCTAssertThrowsError(try MealAnalysisConfiguration(baseURL: URL(string: "http://example.com")!))
        XCTAssertNoThrow(try MealAnalysisConfiguration(baseURL: URL(string: "https://proxy.example.com")!))
    }

    func testImageRequestRejectsEmptyOversizedAndUnsupportedData() {
        XCTAssertThrowsError(try MealImageRequest(imageData: Data(), mimeType: "image/jpeg").validated())
        XCTAssertThrowsError(try MealImageRequest(imageData: Data(repeating: 0, count: 4), mimeType: "image/png").validated())
        XCTAssertThrowsError(try MealImageRequest(imageData: Data(repeating: 0, count: 4), mimeType: "image/jpeg").validated(maxByteCount: 3))
        XCTAssertNoThrow(try request.validated())
    }

    private func assertFixture(_ fixture: MockMealAnalysisService.Fixture, equals expected: MealAnalysisError) async {
        do { _ = try await MockMealAnalysisService(fixture: fixture).analyze(request); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? MealAnalysisError, expected) }
    }
}
