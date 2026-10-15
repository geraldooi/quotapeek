import Foundation
import CoreFoundation
#if canImport(Security)
import Security
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Reads Claude Code's official account usage endpoint without persisting credentials.
public struct ClaudeLiveUsageReader: Sendable {
    public struct LoadResult: Sendable {
        public let snapshot: UsageSnapshot
        public let retryAfter: Date?

        public init(snapshot: UsageSnapshot, retryAfter: Date? = nil) {
            self.snapshot = snapshot
            self.retryAfter = retryAfter
        }
    }

    public static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let credentialsURL: URL?
    private let configDirectory: URL?
    private let now: @Sendable () -> Date

    public init(
        credentialsURL: URL? = nil,
        configDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentialsURL = credentialsURL
        self.configDirectory = configDirectory
        self.now = now
    }

    /// Loads a current snapshot synchronously so callers can invoke it from a detached task.
    public func load() -> UsageSnapshot {
        loadResult().snapshot
    }

    /// Loads a snapshot and preserves a provider-supplied retry deadline, when present.
    public func loadResult() -> LoadResult {
        let currentDate = now()
        guard let token = accessToken() else {
            return LoadResult(snapshot: unavailable(
                health: .inactive,
                title: "Claude live quota is unavailable",
                message: "Claude Code credentials were not available to read its official usage.",
                recoverySuggestion: "Use Claude Code once, then refresh QuotaPeek."
            ))
        }

        var request = URLRequest(url: Self.usageEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeCode/1.0", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var response: URLResponse?
        var responseError: Error?
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        let task = session.dataTask(with: request) { data, urlResponse, error in
            responseData = data
            response = urlResponse
            responseError = error
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            session.invalidateAndCancel()
            return LoadResult(snapshot: unavailable(
                title: "Claude live quota could not be read",
                message: "QuotaPeek timed out while contacting Claude's official usage endpoint.",
                recoverySuggestion: "Check the network connection, then refresh QuotaPeek."
            ))
        }
        session.finishTasksAndInvalidate()
        let responseReceivedAt = now()

        guard responseError == nil, let httpResponse = response as? HTTPURLResponse else {
            return LoadResult(snapshot: unavailable(
                title: "Claude live quota could not be read",
                message: "QuotaPeek could not reach Claude's official usage endpoint.",
                recoverySuggestion: "Check the network connection, then refresh QuotaPeek."
            ))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            return LoadResult(
                snapshot: unavailable(issue: Self.issue(forHTTPStatus: httpResponse.statusCode)),
                retryAfter: Self.retryAfterDate(
                    from: httpResponse.value(forHTTPHeaderField: "Retry-After"),
                    now: responseReceivedAt
                )
            )
        }
        guard let responseData else {
            return LoadResult(snapshot: unavailable(
                title: "Claude live quota could not be read",
                message: "Claude's official usage endpoint did not return usable quota data.",
                recoverySuggestion: "Refresh QuotaPeek to try again."
            ))
        }

        guard let snapshot = Self.parse(data: responseData, now: currentDate) else {
            return LoadResult(snapshot: unavailable(
                kind: .unsupportedFormat,
                title: "Claude live quota data is invalid",
                message: "Claude supplied usage data in an unexpected format.",
                recoverySuggestion: "Update Claude Code, then refresh QuotaPeek."
            ))
        }
        return LoadResult(snapshot: snapshot)
    }

    /// Parses the documented usage response without reading credentials or making a request.
    public static func parse(data: Data, now: Date = Date()) -> UsageSnapshot? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let fiveHour = parseWindow(root["five_hour"], kind: .fiveHour, label: "5 hours")
        let sevenDay = parseWindow(root["seven_day"], kind: .weekly, label: "Weekly")
        guard fiveHour != .invalid, sevenDay != .invalid else { return nil }
        let windows = [fiveHour, sevenDay].compactMap { result -> UsageWindow? in
            guard case .valid(let window) = result else { return nil }
            return window
        }
            .filter { $0.resetAt.map { $0 > now } ?? true }
        guard !windows.isEmpty else { return nil }

        return UsageSnapshot(
            provider: .claude,
            source: .live,
            health: windows.count == 2 ? .ready : .limited,
            issue: windows.count == 2 ? nil : UsageIssue(
                kind: .quotaLimitsUnavailable,
                title: "Some Claude quota data is unavailable",
                message: "Claude supplied only one current quota window.",
                recoverySuggestion: "Refresh QuotaPeek after using Claude Code again."
            ),
            diagnostics: UsageDiagnostics(dataPath: "Claude Code live usage endpoint", filesFound: 0, readableRecords: 1, latestActivity: now),
            windows: windows,
            updatedAt: now
        )
    }

    private enum WindowParseResult: Equatable {
        case absent
        case valid(UsageWindow)
        case invalid
    }

    private static func parseWindow(_ value: Any?, kind: UsageWindowKind, label: String) -> WindowParseResult {
        guard let value, !(value is NSNull) else { return .absent }
        guard let object = value as? [String: Any],
              let rawUtilization = object["utilization"],
              !isBoolean(rawUtilization),
              let utilization = JSONValue.double(rawUtilization),
              utilization.isFinite, (0...100).contains(utilization)
        else { return .invalid }
        let resetAt: Date?
        if let rawReset = object["resets_at"], !(rawReset is NSNull) {
            guard !isBoolean(rawReset) else { return .invalid }
            if let text = rawReset as? String {
                resetAt = ISO8601DateFormatter.date(from: text)
            } else if let seconds = JSONValue.double(rawReset), seconds.isFinite {
                resetAt = Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1_000 : seconds)
            } else {
                return .invalid
            }
            guard let resetAt,
                  resetAt.timeIntervalSince1970.isFinite,
                  resetAt.timeIntervalSince1970 > 0 else { return .invalid }
        } else {
            resetAt = nil
        }
        return .valid(UsageWindow(kind: kind, label: label, usedPercent: utilization, resetAt: resetAt))
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func accessToken() -> String? {
        #if canImport(Security)
        for service in Self.keychainServices(configDirectory: configDirectory) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecMatchLimit as String: kSecMatchLimitAll,
                kSecReturnData as String: true
            ]
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess {
                let dataValues: [Data]
                if let values = result as? [Data] {
                    dataValues = values
                } else if let value = result as? Data {
                    dataValues = [value]
                } else {
                    dataValues = []
                }
                for data in dataValues where Self.token(from: data) != nil {
                    return Self.token(from: data)
                }
            }
        }
        #endif

        let url = credentialsURL ?? Self.credentialsFileURL(configDirectory: configDirectory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.token(from: data)
    }

    private static func token(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        if let rawExpiry = oauth["expiresAt"], let expiry = JSONValue.double(rawExpiry) {
            let seconds = expiry > 100_000_000_000 ? expiry / 1_000 : expiry
            guard seconds.isFinite, seconds > Date().timeIntervalSince1970 else { return nil }
        }
        return token
    }

    static func keychainServices(
        configDirectory: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        let base = "Claude Code-credentials"
        guard let selector = credentialSelector(configDirectory: configDirectory, environment: environment),
              !selector.isEmpty else { return [base] }
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(selector.precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return ["\(base)-\(digest.prefix(8))"]
        #else
        return []
        #endif
    }

    static func credentialsFileURL(
        configDirectory: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let selector = credentialSelector(configDirectory: configDirectory, environment: environment)
        let directory: URL
        if let selector, !selector.isEmpty {
            directory = URL(fileURLWithPath: selector, isDirectory: true)
        } else {
            directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
        }
        return directory.appendingPathComponent(".credentials.json")
    }

    private static func credentialSelector(configDirectory: URL?, environment: [String: String]) -> String? {
        // An explicitly empty secure-storage selector pins Claude's default store.
        // Nonempty selectors are hashed verbatim (NFC), without expanding paths.
        environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"]
            ?? environment["CLAUDE_CONFIG_DIR"]
            ?? configDirectory?.path
    }

    static func issue(forHTTPStatus statusCode: Int) -> UsageIssue {
        let title: String
        let recoverySuggestion: String
        switch statusCode {
        case 401, 403:
            title = "Claude live quota authorization expired"
            recoverySuggestion = "Use Claude Code again to refresh authorization, then refresh QuotaPeek."
        case 429:
            title = "Claude live quota is temporarily rate limited"
            recoverySuggestion = "Wait briefly, then refresh QuotaPeek."
        case 500..<600:
            title = "Claude live quota service is temporarily unavailable"
            recoverySuggestion = "Try again later, then refresh QuotaPeek."
        default:
            title = "Claude live quota could not be read"
            recoverySuggestion = "Refresh QuotaPeek to try again."
        }
        return UsageIssue(
            kind: .readError,
            title: title,
            message: "Claude's official usage endpoint did not return usable quota data.",
            recoverySuggestion: recoverySuggestion
        )
    }

    /// Parses the HTTP Retry-After field as delta-seconds or an HTTP date.
    /// Invalid, negative, or already elapsed values are ignored.
    public static func retryAfterDate(from value: String?, now: Date = Date()) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
           let seconds = Int64(trimmed) {
            let interval = TimeInterval(seconds)
            guard interval.isFinite else { return nil }
            return now.addingTimeInterval(interval)
        }

        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
        guard let date = formatters.lazy.compactMap({ $0.date(from: trimmed) }).first,
              date >= now else { return nil }
        return date
    }

    private func unavailable(issue: UsageIssue) -> UsageSnapshot {
        unavailable(
            kind: issue.kind,
            title: issue.title,
            message: issue.message,
            recoverySuggestion: issue.recoverySuggestion
        )
    }

    private func unavailable(
        kind: UsageIssueKind = .readError,
        health: UsageHealth = .needsAttention,
        title: String,
        message: String,
        recoverySuggestion: String
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude,
            source: .live,
            health: health,
            issue: UsageIssue(kind: kind, title: title, message: message, recoverySuggestion: recoverySuggestion),
            diagnostics: UsageDiagnostics(dataPath: "Claude Code live usage endpoint")
        )
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        withFractionalSeconds.date(from: value) ?? withoutFractionalSeconds.date(from: value)
    }
}
