import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ProviderSupport {
    static let refreshLeeway: TimeInterval = 60

    static func checkedData(
        for request: URLRequest,
        using client: any HTTPClient
    ) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch let error as UsageFetchError {
            throw error
        } catch {
            throw UsageFetchError.network(error.localizedDescription)
        }

        switch response.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw UsageFetchError.unauthorized
        case 429:
            let retryAfter = self.header("Retry-After", in: response)
                .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            throw UsageFetchError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
            throw UsageFetchError.http(status: response.statusCode, body: String(body.prefix(500)))
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw UsageFetchError.decoding(error.localizedDescription)
        }
    }

    static func remainingPercent(fromUsed usedPercent: Double) -> Double {
        min(100, max(0, 100 - usedPercent))
    }

    private static func header(_ name: String, in response: HTTPURLResponse) -> String? {
        response.allHeaderFields.first { key, _ in
            String(describing: key).caseInsensitiveCompare(name) == .orderedSame
        }.map { String(describing: $0.value) }
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) {
            return date
        }

        // Some Kimi responses use nanosecond precision, while older Foundation
        // versions only accept milliseconds.
        guard let dot = raw.firstIndex(of: "."),
              let zone = raw[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        else { return nil }
        let fractionStart = raw.index(after: dot)
        let fraction = raw[fractionStart..<zone]
        guard fraction.count > 3 else { return nil }
        let normalized = String(raw[..<fractionStart])
            + String(fraction.prefix(3))
            + String(raw[zone...])
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: normalized)
    }

    static func accessTokenExpiresSoon(_ token: String, now: Date) -> Bool {
        guard let expiration = jwtExpiration(token) else { return false }
        return expiration <= now.addingTimeInterval(refreshLeeway)
    }

    private static func jwtExpiration(_ token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count.isMultiple(of: 4) == false {
            payload += "="
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let seconds: Double?
        if let value = object["exp"] as? Double {
            seconds = value
        } else if let value = object["exp"] as? Int {
            seconds = Double(value)
        } else if let value = object["exp"] as? String {
            seconds = Double(value)
        } else {
            seconds = nil
        }
        return seconds.map(Date.init(timeIntervalSince1970:))
    }
}
