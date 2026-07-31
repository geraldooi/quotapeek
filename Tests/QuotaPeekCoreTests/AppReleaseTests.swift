import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("App release awareness")
struct AppReleaseTests {
    @Test("Parses the latest stable GitHub release")
    func parsesLatestRelease() throws {
        let data = try #require(
            #"{"tag_name":"v0.6.0","html_url":"https://github.com/geraldooi/quotapeek/releases/tag/v0.6.0"}"#
                .data(using: .utf8)
        )

        let release = try #require(AppReleaseParser.parse(data: data))

        #expect(release.version == "0.6.0")
        #expect(release.url.absoluteString.hasSuffix("/v0.6.0"))
    }

    @Test("Compares semantic version components numerically")
    func comparesVersionsNumerically() {
        let release = AppRelease(
            version: "0.10.0",
            url: URL(string: "https://github.com/geraldooi/quotapeek/releases/tag/v0.10.0")!
        )

        #expect(release.isNewer(than: "0.9.0"))
        #expect(!release.isNewer(than: "0.10.0"))
        #expect(!release.isNewer(than: "0.11.0"))
    }

    @Test("Rejects malformed release metadata")
    func rejectsMalformedReleaseMetadata() throws {
        let invalidTag = try #require(
            #"{"tag_name":"latest","html_url":"https://github.com/geraldooi/quotapeek/releases/latest"}"#
                .data(using: .utf8)
        )
        let insecureURL = try #require(
            #"{"tag_name":"v0.6.0","html_url":"http://example.com/v0.6.0"}"#
                .data(using: .utf8)
        )
        let wrongRepository = try #require(
            #"{"tag_name":"v0.6.0","html_url":"https://github.com/example/project/releases/tag/v0.6.0"}"#
                .data(using: .utf8)
        )

        #expect(AppReleaseParser.parse(data: invalidTag) == nil)
        #expect(AppReleaseParser.parse(data: insecureURL) == nil)
        #expect(AppReleaseParser.parse(data: wrongRepository) == nil)
    }
}
