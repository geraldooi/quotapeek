import Foundation

enum UsageDirectoryState {
    case directory
    case missing
    case failure(Error)
}

enum UsageReaderSupport {
    static func directoryState(
        for url: URL,
        fileManager: FileManager
    ) -> UsageDirectoryState {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true ? .directory : .missing
        } catch {
            return isMissingError(error) ? .missing : .failure(error)
        }
    }

    static func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            return true
        }
        return error.domain == NSPOSIXErrorDomain
            && (error.code == Int(EACCES) || error.code == Int(EPERM))
    }

    static func unavailable(
        provider: Provider,
        kind: UsageIssueKind,
        title: String,
        message: String,
        recoverySuggestion: String,
        diagnostics: UsageDiagnostics
    ) -> UsageSnapshot {
        snapshot(
            provider: provider,
            health: .needsAttention,
            kind: kind,
            title: title,
            message: message,
            recoverySuggestion: recoverySuggestion,
            diagnostics: diagnostics
        )
    }

    static func inactive(
        provider: Provider,
        title: String,
        message: String,
        recoverySuggestion: String,
        diagnostics: UsageDiagnostics
    ) -> UsageSnapshot {
        snapshot(
            provider: provider,
            health: .inactive,
            kind: .noRecentActivity,
            title: title,
            message: message,
            recoverySuggestion: recoverySuggestion,
            diagnostics: diagnostics
        )
    }

    private static func snapshot(
        provider: Provider,
        health: UsageHealth,
        kind: UsageIssueKind,
        title: String,
        message: String,
        recoverySuggestion: String,
        diagnostics: UsageDiagnostics
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            health: health,
            issue: UsageIssue(
                kind: kind,
                title: title,
                message: message,
                recoverySuggestion: recoverySuggestion
            ),
            diagnostics: diagnostics
        )
    }

    private static func isMissingError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return true
        }
        return error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
    }
}
