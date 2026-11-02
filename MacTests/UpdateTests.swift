import Foundation
import Testing

/// Shipped copies only ever look at the feed and key they were built with, so a wrong one cannot be fixed by an update.
@Suite struct UpdateTests {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private func info() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Mac/Info.plist"))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
    @Test func feedIsWhereTheReleaseScriptPublishes() throws {
        let script = try String(contentsOf: root.appendingPathComponent("scripts/release-mac.sh"), encoding: .utf8)
        let repo = try #require(script.split(separator: "\n").first { $0.hasPrefix("repo=") }).dropFirst("repo=".count)
        #expect(try info()["SUFeedURL"] as? String == "\(repo)/releases/latest/download/appcast.xml")
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
