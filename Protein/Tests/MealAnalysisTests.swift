import Foundation
import ImageIO
import UIKit
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
        XCTAssertThrowsError(try MealAnalysisConfiguration(baseURL: URL(string: "https://example.invalid")!))
        XCTAssertNoThrow(try MealAnalysisConfiguration(baseURL: URL(string: "https://proxy.example.com")!))
    }

    func testImageRequestRejectsEmptyOversizedAndUnsupportedData() {
        XCTAssertThrowsError(try MealImageRequest(imageData: Data(), mimeType: "image/jpeg").validated())
        XCTAssertThrowsError(try MealImageRequest(imageData: Data(repeating: 0, count: 4), mimeType: "image/png").validated())
        XCTAssertThrowsError(try MealImageRequest(imageData: Data(repeating: 0, count: 4), mimeType: "image/jpeg").validated(maxByteCount: 3))
        XCTAssertNoThrow(try request.validated())
    }

    func testImagePreprocessingBoundsDimensionsBytesAndMetadata() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3_200, height: 2_000), format: format).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3_200, height: 2_000))
        }

        let prepared = try MealImagePreprocessor.prepare(image)
        let source = CGImageSourceCreateWithData(prepared.imageData as CFData, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        let width = properties?[kCGImagePropertyPixelWidth] as? CGFloat
        let height = properties?[kCGImagePropertyPixelHeight] as? CGFloat

        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertLessThanOrEqual(prepared.imageData.count, MealImagePreprocessor.maximumByteCount)
        XCTAssertLessThanOrEqual(max(width ?? .infinity, height ?? .infinity), MealImagePreprocessor.maximumDimension)
        XCTAssertNil(properties?[kCGImagePropertyGPSDictionary])
    }

    func testProxyBuildsBoundedMultipartRequestAndDecodesValidatedResult() async throws {
        let response = """
        {"foods":[{"id":"0F4A2D7B-54AA-49F2-8EB9-BF07A6C8FD05","name":"Chicken","assumedPortion":"One breast","proteinGrams":38,"confidence":0.88}],"totalProteinGrams":38,"warnings":["Estimated portion"]}
        """.data(using: .utf8)!
        let transport = StubTransport(data: response, statusCode: 200)
        let service = ProxyMealAnalysisService(
            configuration: try MealAnalysisConfiguration(baseURL: URL(string: "https://proxy.example.com")!),
            transport: transport
        )

        let result = try await service.analyze(request)
        let sentRequest = await transport.receivedRequest
        let body = String(decoding: sentRequest?.httpBody ?? Data(), as: UTF8.self)

        XCTAssertEqual(result.totalProteinGrams, 38)
        XCTAssertEqual(sentRequest?.url?.absoluteString, "https://proxy.example.com/v1/meal-analysis")
        XCTAssertEqual(sentRequest?.httpMethod, "POST")
        XCTAssertEqual(sentRequest?.timeoutInterval, ProxyMealAnalysisService.requestTimeout)
        XCTAssertTrue(sentRequest?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertTrue(body.contains("name=\"response_version\""))
        XCTAssertTrue(body.contains("name=\"image\"; filename=\"meal.jpg\""))
    }

    func testProxyMapsRecoverableHTTPAndNetworkErrors() async throws {
        let configuration = try MealAnalysisConfiguration(baseURL: URL(string: "https://proxy.example.com")!)
        await assertProxy(StubTransport(data: Data(), statusCode: 504), configuration: configuration, equals: .timedOut)
        await assertProxy(StubTransport(data: Data(), statusCode: 500), configuration: configuration, equals: .serviceUnavailable)
        await assertProxy(
            StubTransport(data: Data("{\"code\":\"refused\",\"message\":\"No meal was visible.\"}".utf8), statusCode: 422),
            configuration: configuration,
            equals: .refused("No meal was visible.")
        )
        await assertProxy(FailingTransport(code: .notConnectedToInternet), configuration: configuration, equals: .noNetwork)
        await assertProxy(FailingTransport(code: .timedOut), configuration: configuration, equals: .timedOut)
    }

    func testProxyRejectsMalformedSuccessfulPayload() async throws {
        let service = ProxyMealAnalysisService(
            configuration: try MealAnalysisConfiguration(baseURL: URL(string: "https://proxy.example.com")!),
            transport: StubTransport(data: Data("{\"foods\":[]}".utf8), statusCode: 200)
        )
        do {
            _ = try await service.analyze(request)
            XCTFail("Malformed success response was accepted")
        } catch {
            guard case .invalidResponse = error as? MealAnalysisError else {
                return XCTFail("Expected invalid response, got \(error)")
            }
        }
    }

    private func assertFixture(_ fixture: MockMealAnalysisService.Fixture, equals expected: MealAnalysisError) async {
        do { _ = try await MockMealAnalysisService(fixture: fixture).analyze(request); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? MealAnalysisError, expected) }
    }

    private func assertProxy(
        _ transport: any MealAnalysisTransport,
        configuration: MealAnalysisConfiguration,
        equals expected: MealAnalysisError
    ) async {
        do {
            _ = try await ProxyMealAnalysisService(configuration: configuration, transport: transport).analyze(request)
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? MealAnalysisError, expected)
        }
    }
}

private actor StubTransport: MealAnalysisTransport {
    let data: Data
    let statusCode: Int
    private(set) var receivedRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequest = request
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private struct FailingTransport: MealAnalysisTransport {
    let code: URLError.Code

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(code)
    }
}
