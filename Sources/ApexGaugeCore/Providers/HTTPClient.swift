import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if #available(macOS 10.15, *) {
            return try await withCheckedThrowingContinuation { continuation in
                self.session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let httpResponse = response as? HTTPURLResponse else {
                        continuation.resume(
                            throwing: UsageFetchError.network("Provider returned a non-HTTP response"))
                        return
                    }
                    continuation.resume(returning: (data, httpResponse))
                }.resume()
            }
        }
        throw UsageFetchError.network("Async HTTP requires macOS 10.15 or newer")
    }
}
