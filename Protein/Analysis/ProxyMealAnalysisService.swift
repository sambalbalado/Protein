import Foundation

public protocol MealAnalysisTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionMealAnalysisTransport: MealAnalysisTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public struct ProxyMealAnalysisService: MealAnalysisService {
    public static let maximumUploadByteCount = 2_000_000
    public static let requestTimeout: TimeInterval = 25

    private let configuration: MealAnalysisConfiguration
    private let transport: any MealAnalysisTransport

    public init(
        configuration: MealAnalysisConfiguration,
        transport: any MealAnalysisTransport = URLSessionMealAnalysisTransport()
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    public func analyze(_ imageRequest: MealImageRequest) async throws -> MealAnalysisResult {
        let imageRequest = try imageRequest.validated(maxByteCount: Self.maximumUploadByteCount)
        let request = makeRequest(for: imageRequest)

        do {
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw MealAnalysisError.invalidResponse("The proxy did not return an HTTP response.")
            }
            return try decode(data: data, statusCode: response.statusCode)
        } catch is CancellationError {
            throw MealAnalysisError.cancelled
        } catch let error as MealAnalysisError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw MealAnalysisError.cancelled
            case .timedOut: throw MealAnalysisError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw MealAnalysisError.noNetwork
            default: throw MealAnalysisError.serviceUnavailable
            }
        } catch {
            throw MealAnalysisError.serviceUnavailable
        }
    }

    private func makeRequest(for imageRequest: MealImageRequest) -> URLRequest {
        let endpoint = configuration.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("meal-analysis")
        let boundary = "Protein-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartMealRequest.build(imageRequest, boundary: boundary)
        return request
    }

    private func decode(data: Data, statusCode: Int) throws -> MealAnalysisResult {
        switch statusCode {
        case 200..<300:
            do {
                let result = try JSONDecoder().decode(MealAnalysisResult.self, from: data)
                _ = try result.validated()
                return result
            } catch let error as MealAnalysisError {
                throw error
            } catch {
                throw MealAnalysisError.invalidResponse("The proxy response was malformed.")
            }
        case 408, 504:
            throw MealAnalysisError.timedOut
        case 413:
            throw MealAnalysisError.invalidImage
        case 422:
            let response = try? JSONDecoder().decode(ProxyErrorResponse.self, from: data)
            if response?.code == "refused" {
                throw MealAnalysisError.refused(response?.safeMessage ?? "This image could not be analyzed as a meal.")
            }
            throw MealAnalysisError.invalidResponse("The proxy could not verify this estimate.")
        case 429, 500...599:
            throw MealAnalysisError.serviceUnavailable
        default:
            throw MealAnalysisError.invalidResponse("The proxy rejected the request.")
        }
    }
}

private enum MultipartMealRequest {
    static func build(_ request: MealImageRequest, boundary: String) -> Data {
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"response_version\"\r\n\r\n")
        body.appendUTF8("1\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"image\"; filename=\"meal.jpg\"\r\n")
        body.appendUTF8("Content-Type: \(request.mimeType)\r\n\r\n")
        body.append(request.imageData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }
}

private struct ProxyErrorResponse: Decodable {
    let code: String
    let message: String?

    var safeMessage: String? {
        guard let message else { return nil }
        let flattened = message.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return nil }
        return String(flattened.prefix(160))
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }
}
