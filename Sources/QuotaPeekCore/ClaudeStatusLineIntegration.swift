import Foundation

public struct ClaudeQuotaPaths: Sendable {
    public let supportDirectory: URL

    public init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
    }

    public static var currentUser: ClaudeQuotaPaths {
        ClaudeQuotaPaths(
            supportDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/QuotaPeek", isDirectory: true)
        )
    }

    public var cacheURL: URL {
        supportDirectory.appendingPathComponent("claude-rate-limits.json")
    }

    public var helperURL: URL {
        supportDirectory.appendingPathComponent("QuotaPeekClaudeBridge")
    }

    public var backupURL: URL {
        supportDirectory.appendingPathComponent("claude-statusline-backup.json")
    }

    public var captureStatusURL: URL {
        supportDirectory.appendingPathComponent("claude-capture-status")
    }
}

public struct ClaudeStatusLineIntegration: Sendable {
    public let settingsURL: URL
    public let paths: ClaudeQuotaPaths

    public init(settingsURL: URL, supportDirectory: URL) {
        self.settingsURL = settingsURL
        paths = ClaudeQuotaPaths(supportDirectory: supportDirectory)
    }

    public static var currentUser: ClaudeStatusLineIntegration {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ClaudeStatusLineIntegration(
            settingsURL: home
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json"),
            supportDirectory: ClaudeQuotaPaths.currentUser.supportDirectory
        )
    }

    public var helperURL: URL { paths.helperURL }

    public var isInstalled: Bool {
        currentCommand == bridgeCommand
            && FileManager.default.isExecutableFile(atPath: helperURL.path)
    }

    public var originalCommand: String? {
        guard
            let backup = readJSONObject(at: paths.backupURL),
            let statusLine = backup["statusLine"] as? [String: Any]
        else {
            return nil
        }
        return statusLine["command"] as? String
    }

    public func install(helperSourceURL: URL) throws {
        let fileManager = FileManager.default
        var settings = try readSettings()
        let existingStatusLine = settings["statusLine"]
        let existingCommand = (existingStatusLine as? [String: Any])?["command"] as? String

        if existingCommand != bridgeCommand {
            var backup: [String: Any] = [
                "hadStatusLine": existingStatusLine != nil
            ]
            if let existingStatusLine {
                backup["statusLine"] = existingStatusLine
            }
            try writeJSONObject(backup, to: paths.backupURL)
        } else if readJSONObject(at: paths.backupURL) == nil {
            throw ClaudeStatusLineIntegrationError.invalidBackup
        }

        try fileManager.createDirectory(
            at: paths.supportDirectory,
            withIntermediateDirectories: true
        )
        try ClaudeQuotaCaptureStatusStore(
            statusURL: paths.captureStatusURL
        ).ensureExists()

        let stagedHelperURL = paths.supportDirectory.appendingPathComponent(
            ".QuotaPeekClaudeBridge-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: stagedHelperURL) }
        try fileManager.copyItem(at: helperSourceURL, to: stagedHelperURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: stagedHelperURL.path
        )
        guard fileManager.isExecutableFile(atPath: stagedHelperURL.path) else {
            throw ClaudeStatusLineIntegrationError.invalidHelper
        }
        if fileManager.fileExists(atPath: helperURL.path) {
            _ = try fileManager.replaceItemAt(
                helperURL,
                withItemAt: stagedHelperURL
            )
        } else {
            try fileManager.moveItem(at: stagedHelperURL, to: helperURL)
        }

        var bridgeStatusLine = existingStatusLine as? [String: Any] ?? [:]
        bridgeStatusLine["type"] = "command"
        bridgeStatusLine["command"] = bridgeCommand
        settings["statusLine"] = bridgeStatusLine
        try writeJSONObject(settings, to: settingsURL)
    }

    public func uninstall() throws {
        let fileManager = FileManager.default
        var settings = try readSettings()
        let statusLine = settings["statusLine"] as? [String: Any]
        let command = statusLine?["command"] as? String
        if command == bridgeCommand {
            guard let backup = readJSONObject(at: paths.backupURL) else {
                throw ClaudeStatusLineIntegrationError.invalidBackup
            }
            if backup["hadStatusLine"] as? Bool == true,
               let statusLine = backup["statusLine"] {
                settings["statusLine"] = statusLine
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try writeJSONObject(settings, to: settingsURL)
        }

        for url in [
            paths.helperURL,
            paths.backupURL,
            paths.cacheURL,
            paths.captureStatusURL
        ]
        where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private var currentCommand: String? {
        let settings = readJSONObject(at: settingsURL)
        let statusLine = settings?["statusLine"] as? [String: Any]
        return statusLine?["command"] as? String
    }

    private var bridgeCommand: String {
        shellQuote(helperURL.path)
    }

    private func readJSONObject(at url: URL) -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return [:]
        }
        guard let settings = readJSONObject(at: settingsURL) else {
            throw ClaudeStatusLineIntegrationError.invalidSettings
        }
        return settings
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum ClaudeStatusLineIntegrationError: LocalizedError {
    case invalidSettings
    case invalidBackup
    case invalidHelper

    public var errorDescription: String? {
        switch self {
        case .invalidSettings:
            "Claude Code settings are not valid JSON. QuotaPeek left them unchanged."
        case .invalidBackup:
            "QuotaPeek could not restore the previous Claude Code status line."
        case .invalidHelper:
            "QuotaPeek's Claude quota helper is not executable."
        }
    }
}
