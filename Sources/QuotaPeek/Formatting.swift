import Foundation

enum AppVersion {
    static var current: String? {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return nil
        }

        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var label: String {
        current.map { "v\($0)" } ?? "Development"
    }
}
