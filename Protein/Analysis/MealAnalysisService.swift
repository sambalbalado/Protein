import Foundation

public protocol MealAnalysisService: Sendable {
    func analyze(_ request: MealImageRequest) async throws -> MealAnalysisResult
}

public struct UnavailableMealAnalysisService: MealAnalysisService {
    public init() {}

    public func analyze(_ request: MealImageRequest) async throws -> MealAnalysisResult {
        _ = try request.validated(maxByteCount: ProxyMealAnalysisService.maximumUploadByteCount)
        throw MealAnalysisError.configurationMissing
    }
}

public enum MealAnalysisError: LocalizedError, Equatable, Sendable {
    case noNetwork
    case timedOut
    case refused(String)
    case invalidResponse(String)
    case serviceUnavailable
    case configurationMissing
    case cancelled
    case invalidImage

    public var errorDescription: String? {
        switch self {
        case .noNetwork: "Photo analysis needs an internet connection. Manual logging still works offline."
        case .timedOut: "Analysis took too long. Try again when your connection is stable."
        case .refused(let reason): reason
        case .invalidResponse: "The estimate could not be verified, so nothing was saved. Try another photo or log manually."
        case .serviceUnavailable: "Photo analysis is temporarily unavailable. Try again, or log protein manually."
        case .configurationMissing: "Photo analysis is not configured in this build. Add your secure proxy URL in Secrets.xcconfig."
        case .cancelled: "Analysis was cancelled."
        case .invalidImage: "Choose a valid meal photo. Protein prepares a metadata-minimized JPEG under 2 MB before upload."
        }
    }
}

public enum MealAnalysisDecoder {
    public static func decode(_ data: Data, using decoder: JSONDecoder = JSONDecoder()) throws -> EditableMealAnalysis {
        do { return try decoder.decode(MealAnalysisResult.self, from: data).validated() }
        catch let error as MealAnalysisError { throw error }
        catch { throw MealAnalysisError.invalidResponse("The service response was malformed.") }
    }
}

public struct MealAnalysisConfiguration: Equatable, Sendable {
    public let baseURL: URL

    public init(baseURL: URL) throws {
        guard baseURL.scheme == "https",
              let host = baseURL.host,
              !host.hasSuffix(".invalid"),
              baseURL.user == nil,
              baseURL.password == nil else {
            throw MealAnalysisError.configurationMissing
        }
        self.baseURL = baseURL
    }

    public static func from(bundle: Bundle = .main) throws -> Self {
        guard let value = bundle.object(forInfoDictionaryKey: "ProteinAnalysisServiceURL") as? String,
              let url = URL(string: value) else { throw MealAnalysisError.configurationMissing }
        return try Self(baseURL: url)
    }
}

public struct MockMealAnalysisService: MealAnalysisService {
    public enum Fixture: String, CaseIterable, Sendable {
        case success, lowConfidence, refusal, timeout, malformed, noNetwork
    }

    public let fixture: Fixture
    public let delay: Duration

    public init(fixture: Fixture, delay: Duration = .zero) {
        self.fixture = fixture
        self.delay = delay
    }

    public func analyze(_ request: MealImageRequest) async throws -> MealAnalysisResult {
        _ = try request.validated()
        do { try await Task.sleep(for: delay) }
        catch is CancellationError { throw MealAnalysisError.cancelled }
        try Task.checkCancellation()
        switch fixture {
        case .success:
            return .init(foods: [
                .init(name: "Grilled chicken", assumedPortion: "About one palm-sized breast", proteinGrams: 38, confidence: 0.88),
                .init(name: "Brown rice", assumedPortion: "About one cup", proteinGrams: 5, confidence: 0.78)
            ], totalProteinGrams: 43, warnings: ["Portion sizes are inferred from the image."])
        case .lowConfidence:
            return .init(foods: [.init(name: "Mixed tofu dish", assumedPortion: "Approximately one bowl", proteinGrams: 22, confidence: 0.42)], totalProteinGrams: 22, warnings: ["Ingredients are partly obscured."])
        case .refusal: throw MealAnalysisError.refused("This image could not be analyzed as a meal.")
        case .timeout: throw MealAnalysisError.timedOut
        case .malformed: return .init(foods: [.init(name: "Unknown", assumedPortion: "", proteinGrams: -4, confidence: 2)], totalProteinGrams: 900)
        case .noNetwork: throw MealAnalysisError.noNetwork
        }
    }
}
