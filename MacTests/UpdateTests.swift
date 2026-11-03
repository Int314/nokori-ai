import Foundation
import Testing

/// Shipped copies only ever look at the feed and key they were built with, so a wrong one cannot be fixed by an update.
@Suite struct UpdateTests {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private func info() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Mac/Info.plist"))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
    private func value(_ prefix: String, in file: String) throws -> Substring {
        let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
        return try #require(text.split(separator: "\n").first { $0.hasPrefix(prefix) }).dropFirst(prefix.count)
    }
    /// The feed belongs to this project's team, so a build signed by anyone else has none.
    @Test func feedIsWhereTheReleaseScriptPublishes() throws {
        let repo = try value("repo=", in: "scripts/release-mac.sh")
        let team = try value("DEVELOPMENT_TEAM = ", in: "Config/Identity.xcconfig")
        let feed = try value("        NOKORI_FEED_\(team): ", in: "project.yml")
        #expect(feed == "\(repo)/releases/latest/download/appcast.xml")
        #expect(try info()["SUFeedURL"] as? String == "$(NOKORI_UPDATE_FEED)")
    }
    @Test func updatesAreSignedWithAnEdDSAKey() throws {
        let key = try #require(try info()["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
    }
    @Test func versionComesFromTheProjectSettings() throws {
        let info = try info()
        #expect(info["CFBundleShortVersionString"] as? String == "$(MARKETING_VERSION)")
        #expect(info["CFBundleVersion"] as? String == "$(CURRENT_PROJECT_VERSION)")
    }
}
