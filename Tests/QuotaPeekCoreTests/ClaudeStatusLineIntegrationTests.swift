import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Claude status-line integration")
struct ClaudeStatusLineIntegrationTests {
    @Test("Installing and removing the bridge preserves an existing status line")
    func preservesExistingStatusLine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeDirectory = root.appendingPathComponent(".claude", isDirectory: true)
        let supportDirectory = root.appendingPathComponent("support", isDirectory: true)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let helperSourceURL = root.appendingPathComponent("QuotaPeekClaudeBridge")
        try FileManager.default.createDirectory(
            at: claudeDirectory,
            withIntermediateDirectories: true
        )
        try Data("helper".utf8).write(to: helperSourceURL)
        let originalStatusLine: [String: Any] = [
            "type": "command",
            "command": "~/.claude/my-statusline.sh",
            "padding": 0
        ]
        let originalSettings: [String: Any] = [
            "statusLine": originalStatusLine,
            "permissions": ["defaultMode": "acceptEdits"]
        ]
        try JSONSerialization.data(
            withJSONObject: originalSettings,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: settingsURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let integration = ClaudeStatusLineIntegration(
            settingsURL: settingsURL,
            supportDirectory: supportDirectory
        )
        try integration.install(helperSourceURL: helperSourceURL)

        #expect(integration.isInstalled)
        #expect(FileManager.default.fileExists(atPath: integration.helperURL.path))
        #expect(integration.originalCommand == "~/.claude/my-statusline.sh")
        let installed = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL))
                as? [String: Any]
        )
        let installedStatusLine = try #require(installed["statusLine"] as? [String: Any])
        #expect(installedStatusLine["padding"] as? Int == 0)

        try integration.uninstall()
        let restored = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL))
                as? [String: Any]
        )
        #expect((restored["statusLine"] as? NSDictionary) == originalStatusLine as NSDictionary)
        #expect(
            ((restored["permissions"] as? [String: Any])?["defaultMode"] as? String)
                == "acceptEdits"
        )
    }

    @Test("Refuses to overwrite malformed Claude settings")
    func preservesMalformedSettings() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let settingsURL = root.appendingPathComponent("settings.json")
        let helperSourceURL = root.appendingPathComponent("helper")
        let original = Data("not valid JSON".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try original.write(to: settingsURL)
        try Data("helper".utf8).write(to: helperSourceURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let integration = ClaudeStatusLineIntegration(
            settingsURL: settingsURL,
            supportDirectory: root.appendingPathComponent("support")
        )

        #expect(throws: ClaudeStatusLineIntegrationError.self) {
            try integration.install(helperSourceURL: helperSourceURL)
        }
        #expect(try Data(contentsOf: settingsURL) == original)
        #expect(!FileManager.default.fileExists(atPath: integration.helperURL.path))
    }

    @Test("Re-enabling preserves a status line changed after installation")
    func preservesNewStatusLine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let settingsURL = root.appendingPathComponent("settings.json")
        let helperSourceURL = root.appendingPathComponent("helper")
        let supportDirectory = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("helper".utf8).write(to: helperSourceURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let integration = ClaudeStatusLineIntegration(
            settingsURL: settingsURL,
            supportDirectory: supportDirectory
        )
        try integration.install(helperSourceURL: helperSourceURL)
        try JSONSerialization.data(withJSONObject: [
            "statusLine": [
                "type": "command",
                "command": "~/.claude/replacement.sh"
            ]
        ]).write(to: settingsURL)

        try integration.install(helperSourceURL: helperSourceURL)
        try integration.uninstall()

        let restored = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL))
                as? [String: Any]
        )
        let statusLine = try #require(restored["statusLine"] as? [String: Any])
        #expect(statusLine["command"] as? String == "~/.claude/replacement.sh")
    }

    @Test("A failed bridge refresh preserves the installed helper")
    func preservesHelperWhenRefreshFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let settingsURL = root.appendingPathComponent("settings.json")
        let helperSourceURL = root.appendingPathComponent("helper")
        let missingSourceURL = root.appendingPathComponent("missing-helper")
        let supportDirectory = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalHelper = Data("working helper".utf8)
        try originalHelper.write(to: helperSourceURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let integration = ClaudeStatusLineIntegration(
            settingsURL: settingsURL,
            supportDirectory: supportDirectory
        )
        try integration.install(helperSourceURL: helperSourceURL)

        #expect(throws: (any Error).self) {
            try integration.install(helperSourceURL: missingSourceURL)
        }
        #expect(try Data(contentsOf: integration.helperURL) == originalHelper)
        #expect(integration.isInstalled)
    }

    @Test("A failed settings read preserves all uninstall artifacts")
    func preservesArtifactsWhenSettingsCannotBeRead() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let settingsURL = root.appendingPathComponent("settings.json")
        let helperSourceURL = root.appendingPathComponent("helper")
        let supportDirectory = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("working helper".utf8).write(to: helperSourceURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let integration = ClaudeStatusLineIntegration(
            settingsURL: settingsURL,
            supportDirectory: supportDirectory
        )
        try integration.install(helperSourceURL: helperSourceURL)
        try Data("temporarily malformed".utf8).write(to: settingsURL)

        #expect(throws: ClaudeStatusLineIntegrationError.self) {
            try integration.uninstall()
        }
        #expect(FileManager.default.fileExists(atPath: integration.helperURL.path))
        #expect(FileManager.default.fileExists(atPath: integration.paths.backupURL.path))
        #expect(FileManager.default.fileExists(atPath: integration.paths.captureStatusURL.path))
    }
}
