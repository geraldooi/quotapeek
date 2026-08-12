import Foundation
import QuotaPeekCore

let input = FileHandle.standardInput.readDataToEndOfFile()
let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    .standardizedFileURL
let supportDirectory = executableURL.deletingLastPathComponent()
let paths = ClaudeQuotaPaths(supportDirectory: supportDirectory)

if let capture = ClaudeQuotaCaptureParser.parse(data: input) {
    let statusStore = ClaudeQuotaCaptureStatusStore(
        statusURL: paths.captureStatusURL
    )
    do {
        try ClaudeQuotaStore(cacheURL: paths.cacheURL).save(capture)
        try statusStore.record(.ready)
    } catch {
        try? statusStore.record(.failure(for: error))
    }
}

let integration = ClaudeStatusLineIntegration(
    settingsURL: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json"),
    supportDirectory: supportDirectory
)

if let originalCommand = integration.originalCommand {
    let process = Process()
    let standardInput = Pipe()
    let standardOutput = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", originalCommand]
    process.standardInput = standardInput
    process.standardOutput = standardOutput
    process.standardError = FileHandle.standardError

    do {
        try process.run()
        standardInput.fileHandleForWriting.write(input)
        try standardInput.fileHandleForWriting.close()
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        FileHandle.standardOutput.write(output)
        exit(process.terminationStatus)
    } catch {
        exit(1)
    }
}
