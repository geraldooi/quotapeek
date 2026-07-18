import Foundation

public struct CodexResetForecast: Equatable, Sendable {
    public let score: Int
    public let fetchedAt: Date
    public let nextRefreshAt: Date?

    public init(score: Int, fetchedAt: Date, nextRefreshAt: Date? = nil) {
        self.score = score
        self.fetchedAt = fetchedAt
        self.nextRefreshAt = nextRefreshAt
    }

    public func isFresh(
        at date: Date = Date(),
        maxAge: TimeInterval = 2 * 60 * 60
    ) -> Bool {
        let age = date.timeIntervalSince(fetchedAt)
        return age >= -5 * 60 && age <= maxAge
    }
}

public enum CodexResetForecastParser {
    public static func parse(data: Data) -> CodexResetForecast? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = fractionalFormatter.date(from: value)
                ?? ISO8601DateFormatter().date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 timestamp"
            )
        }

        guard
            let response = try? decoder.decode(ForecastResponse.self, from: data),
            (0...100).contains(response.forecast.score)
        else {
            return nil
        }

        return CodexResetForecast(
            score: response.forecast.score,
            fetchedAt: response.fetchedAt,
            nextRefreshAt: response.nextRefreshAt
        )
    }

    private struct ForecastResponse: Decodable {
        let fetchedAt: Date
        let nextRefreshAt: Date?
        let forecast: Forecast
    }

    private struct Forecast: Decodable {
        let score: Int
    }
}

public struct CodexResetForecastReader: Sendable {
    private let endpoint: URL

    public init(
        endpoint: URL = URL(string: "https://www.willcodexquotareset.com/api/forecast")!
    ) {
        self.endpoint = endpoint
    }

    public func load() async -> CodexResetForecast? {
        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let response = response as? HTTPURLResponse,
                (200...299).contains(response.statusCode)
            else {
                return nil
            }
            guard let forecast = CodexResetForecastParser.parse(data: data),
                  forecast.isFresh() else {
                return nil
            }
            return forecast
        } catch {
            return nil
        }
    }
}
