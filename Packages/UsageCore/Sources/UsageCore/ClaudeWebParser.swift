import Foundation

public enum ClaudeWebParser {
    public struct Organization: Decodable, Sendable {
        public let uuid: UUID
        public let capabilities: [String]?
        public let rate_limit_tier: String?
    }
    public static func organization(data: Data, preferred: UUID?) throws -> Organization {
        let organizations = try JSONDecoder().decode([Organization].self, from: data)
        if let preferred {
            guard let match = organizations.first(where: { $0.uuid == preferred }) else { throw FetchFailure.unexpected }
            return match
        }
        let chat = organizations.filter { $0.capabilities?.contains("chat") == true }
        let candidates = chat.isEmpty ? organizations : chat
        // Without an active organization cookie, an ambiguous account must be chosen in Claude.
        guard candidates.count == 1, let selected = candidates.first else { throw FetchFailure.unexpected }
        return selected
    }
    public static func usage(data: Data, organization: Organization, fetchedAt: Date) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FetchFailure.unexpected }
        let measuredFiveHour = root["five_hour"] as? [String: Any] != nil
        let measuredWeekly = root["seven_day"] as? [String: Any] != nil
        guard measuredFiveHour || measuredWeekly else { throw FetchFailure.unexpected }
        let parsed = try ClaudeUsageParser.parse(data: data, subscriptionType: nil,
                                                rateLimitTier: organization.rate_limit_tier, fetchedAt: fetchedAt)
        return UsageSnapshot(provider: .claude, plan: parsed.plan,
            windows: parsed.windows.filter { measuredFiveHour || $0.kind != .fiveHour }, status: .ok, fetchedAt: fetchedAt)
    }
}
