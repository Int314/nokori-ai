import Foundation
import Testing
@testable import UsageCore

private let organizationA = "00000000-0000-0000-0000-000000000001"
private let organizationB = "00000000-0000-0000-0000-000000000002"

@Test func claudeWebOrganizationFollowsActiveAccount() throws {
    let data = Data("[{\"uuid\":\"\(organizationA)\",\"capabilities\":[\"chat\"]},{\"uuid\":\"\(organizationB)\",\"capabilities\":[\"chat\"]}]".utf8)
    #expect(try ClaudeWebParser.organization(data: data, preferred: UUID(uuidString: organizationB)).uuid == UUID(uuidString: organizationB))
    #expect(throws: (any Error).self) { try ClaudeWebParser.organization(data: data, preferred: nil) }
    #expect(throws: (any Error).self) { try ClaudeWebParser.organization(data: data, preferred: UUID()) }
}
@Test func claudeWebIgnoresAPIOnlyOrganization() throws {
    let data = Data("[{\"uuid\":\"\(organizationA)\",\"capabilities\":[\"api\"]},{\"uuid\":\"\(organizationB)\",\"capabilities\":[\"chat\"]}]".utf8)
    #expect(try ClaudeWebParser.organization(data: data, preferred: nil).uuid == UUID(uuidString: organizationB))
    #expect(throws: (any Error).self) { try ClaudeWebParser.organization(data: Data("[]".utf8), preferred: nil) }
    #expect(throws: (any Error).self) { try ClaudeWebParser.organization(data: Data(#"[{"uuid":"../account"}]"#.utf8), preferred: nil) }
}
@Test func claudeWebDoesNotInventMissingQuota() throws {
    let organization = try ClaudeWebParser.organization(data: Data("[{\"uuid\":\"\(organizationA)\",\"rate_limit_tier\":\"default_claude_max_5x\"}]".utf8), preferred: nil)
    let usage = try ClaudeWebParser.usage(data: Data(#"{"five_hour":null,"seven_day":{"utilization":42,"resets_at":null}}"#.utf8), organization: organization, fetchedAt: .now)
    #expect(usage.window(.fiveHour) == nil)
    #expect(usage.window(.weekly)?.usedPercent == 42)
    #expect(usage.plan == "Max 5x")
    for json in [#"{"five_hour":null,"seven_day":null}"#, "{}", "<html>challenge</html>"] {
        #expect(throws: (any Error).self) { try ClaudeWebParser.usage(data: Data(json.utf8), organization: organization, fetchedAt: .now) }
    }
}
@Test func claudeAppLoginGuidanceDoesNotRequireTerminal() {
    for language in ["en", "ja"] {
        let formatter = UsageFormatter(locale: Locale(identifier: language))
        for status in [FetchStatus.notLoggedIn, .expired, .needsKeychainPermission] {
            let detail = formatter.failure(status, provider: .claude, claudeApp: true).detail
            #expect(!detail.contains("Terminal") && !detail.contains("ターミナル"))
            #expect(detail.contains(language == "ja" ? "Claudeアプリ" : "Claude app"))
        }
        let phonePermission = formatter.macIssue(.needsKeychainPermission, provider: .claude).detail
        #expect(!phonePermission.contains("Claude Code"))
        #expect(formatter.failure(.notLoggedIn, provider: .codex, claudeApp: true).detail == formatter.failure(.notLoggedIn, provider: .codex).detail)
    }
}
