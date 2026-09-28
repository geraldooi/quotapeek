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
        let currentDate = now()
        guard let token = accessToken() else {
            return unavailable(
                health: .inactive,
                title: "Claude live quota is unavailable",
                message: "Claude Code credentials were not available to read its official usage.",
                recoverySuggestion: "Use Claude Code once, then refresh QuotaPeek."
            )
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
            return unavailable(
                title: "Claude live quota could not be read",
                message: "QuotaPeek timed out while contacting Claude's official usage endpoint.",
                recoverySuggestion: "Check the network connection, then refresh QuotaPeek."
            )
        }
        session.finishTasksAndInvalidate()

        guard responseError == nil, let httpResponse = response as? HTTPURLResponse else {
            return unavailable(
                title: "Claude live quota could not be read",
                message: "QuotaPeek could not reach Claude's official usage endpoint.",
                recoverySuggestion: "Check the network connection, then refresh QuotaPeek."
            )
        }
        guard (200..<300).contains(httpResponse.statusCode), let responseData else {
            return unavailable(
                title: httpResponse.statusCode == 401 || httpResponse.statusCode == 403
                    ? "Claude live quota authorization expired"
                    : "Claude live quota could not be read",
                message: "Claude's official usage endpoint did not return usable quota data.",
                recoverySuggestion: "Use Claude Code again to refresh authorization, then refresh QuotaPeek."
            )
        }

        guard let snapshot = Self.parse(data: responseData, now: currentDate) else {
            return unavailable(
                kind: .unsupportedFormat,
                title: "Claude live quota data is invalid",
                message: "Claude supplied usage data in an unexpected format.",
                recoverySuggestion: "Update Claude Code, then refresh QuotaPeek."
            )
        }
        return snapshot
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

        let url = credentialsURL ?? (configDirectory ?? Self.defaultConfigDirectory)
            .appendingPathComponent(".credentials.json")
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

    private static var defaultConfigDirectory: URL {
        if let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    static func keychainServices(configDirectory: URL?) -> [String] {
        let base = "Claude Code-credentials"
        let configured = ProcessInfo.processInfo.environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"]
            ?? ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            ?? configDirectory?.path
            ?? defaultConfigDirectory.path
        let expanded = (configured as NSString).expandingTildeInPath
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(expanded.precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return ["\(base)-\(digest.prefix(8))", base, "Claude Code"]
        #else
        return [base, "Claude Code"]
        #endif
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
