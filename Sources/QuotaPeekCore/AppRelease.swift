import Foundation

public struct AppRelease: Equatable, Sendable {
    public let version: String
    public let url: URL

    public init(version: String, url: URL) {
        self.version = version
        self.url = url
    }

    public func isNewer(than currentVersion: String) -> Bool {
        guard
            let releaseVersion = SemanticVersion(version),
            let installedVersion = SemanticVersion(currentVersion)
        else {
            return false
        }
        return releaseVersion > installedVersion
    }
}

public enum AppReleaseParser {
    public static func parse(data: Data) -> AppRelease? {
        guard
            let response = try? JSONDecoder().decode(Response.self, from: data),
            response.tagName.hasPrefix("v"),
            response.htmlURL.scheme == "https",
            response.htmlURL.host == "github.com",
            response.htmlURL.path.hasPrefix("/geraldooi/quotapeek/releases/")
        else {
            return nil
        }

        let version = String(response.tagName.dropFirst())
        guard SemanticVersion(version) != nil else {
            return nil
        }
        return AppRelease(version: version, url: response.htmlURL)
    }

    private struct Response: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}

public struct AppReleaseReader: Sendable {
    private let endpoint: URL

    public init(
        endpoint: URL = URL(
            string: "https://api.github.com/repos/geraldooi/quotapeek/releases/latest"
        )!
    ) {
        self.endpoint = endpoint
    }

    public func load() async -> AppRelease? {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("QuotaPeek", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let response = response as? HTTPURLResponse,
                (200...299).contains(response.statusCode)
            else {
                return nil
            }
            return AppReleaseParser.parse(data: data)
        } catch {
            return nil
        }
    }
}

private struct SemanticVersion: Comparable {
    let components: [Int]

    init?(_ value: String) {
        let normalized = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else {
            return nil
        }

        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let number = Int(part) else {
                return nil
            }
            components.append(number)
        }
        while components.count < 3 {
            components.append(0)
        }
        self.components = components
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}
