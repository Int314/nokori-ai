import Foundation

public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date
    public let scopes: [String]
    public let subscriptionType: String?
    public let rateLimitTier: String?
    public var hasProfileScope: Bool { scopes.contains("user:profile") }
    public func isExpired(now: Date) -> Bool { expiresAt <= now }
    public static func parse(data: Data) -> Self? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty,
              let expires = oauth["expiresAt"] as? Double, expires.isFinite else { return nil }
        return Self(accessToken: token, expiresAt: Date(timeIntervalSince1970: expires / 1000),
                    scopes: oauth["scopes"] as? [String] ?? [], subscriptionType: oauth["subscriptionType"] as? String,
                    rateLimitTier: oauth["rateLimitTier"] as? String ?? oauth["rate_limit_tier"] as? String)
    }
}
public enum ClaudeUsageParser {
    public static func plan(subscriptionType: String?, rateLimitTier: String?) -> String? {
        let type = subscriptionType?.lowercased()
        if type == "max" || type == nil {
            if rateLimitTier?.contains("max_20x") == true { return "Max 20x" }
            if rateLimitTier?.contains("max_5x") == true { return "Max 5x" }
        }
        return (subscriptionType ?? rateLimitTier).map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
    public static func parse(data: Data, subscriptionType: String?, rateLimitTier: String?, fetchedAt: Date) throws -> UsageSnapshot {
        struct Window: Decodable { let utilization: Double; let resets_at: String? }
        struct Response: Decodable {
            let five_hour: Window?
            let seven_day: Window?
            enum CodingKeys: String, CodingKey { case five_hour, seven_day }
            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                guard container.contains(.five_hour) || container.contains(.seven_day) else { throw FetchFailure.unexpected }
                five_hour = try container.decodeIfPresent(Window.self, forKey: .five_hour)
                seven_day = try container.decodeIfPresent(Window.self, forKey: .seven_day)
            }
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        func window(_ value: Window, kind: WindowKind) throws -> UsageWindow {
            guard value.utilization.isFinite else { throw FetchFailure.unexpected }
            var date: Date?
            if let raw = value.resets_at {
                date = isoDate(raw)
                guard date != nil else { throw FetchFailure.unexpected }
            }
            return UsageWindow(kind: kind, usedPercent: min(100, max(0, value.utilization)), resetsAt: date)
        }
        var windows = [try response.five_hour.map { try window($0, kind: .fiveHour) } ?? UsageWindow(kind: .fiveHour, usedPercent: 0, resetsAt: nil)]
        if let weekly = response.seven_day { windows.append(try window(weekly, kind: .weekly)) }
        windows += modelWindows(data)
        return UsageSnapshot(provider: .claude, plan: plan(subscriptionType: subscriptionType, rateLimitTier: rateLimitTier), windows: windows, status: .ok, fetchedAt: fetchedAt)
    }
    /// Weekly limits that count one model only, from the `limits` list. These come and go with promotions,
    /// so an entry of an unexpected shape is skipped instead of failing the whole fetch.
    static func modelWindows(_ data: Data) -> [UsageWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let limits = root["limits"] as? [Any] else { return [] }
        var seen: Set<String> = []
        return limits.compactMap { item in
            guard let entry = item as? [String: Any], entry["kind"] as? String == "weekly_scoped", entry["group"] as? String == "weekly",
                  let number = entry["percent"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  let name = ((entry["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String else { return nil }
            let model = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty, model.lowercased() != "all models", seen.insert(model).inserted else { return nil }
            return UsageWindow(kind: .weekly, usedPercent: min(100, max(0, number.doubleValue)), resetsAt: (entry["resets_at"] as? String).flatMap(isoDate), model: model)
        }
    }
    private static func isoDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? { formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: raw) }()
    }
}
public enum CodexUsageParser {
    private struct Account: Decodable { let type: String; let planType: String? }
    private struct AccountResult: Decodable { let account: Account? }
    private struct Envelope<T: Decodable>: Decodable { let result: T }
    public static func isSubscriptionAccount(_ data: Data) throws -> Bool {
        try JSONDecoder().decode(Envelope<AccountResult>.self, from: data).result.account?.type == "chatgpt"
    }
    public static func plan(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.lowercased() == "prolite" { return "Pro Lite" }
        return value.prefix(1).uppercased() + value.dropFirst()
    }
    public static func parse(accountRead: Data?, rateLimitsRead: Data, fetchedAt: Date) throws -> UsageSnapshot {
        struct Window: Decodable { let usedPercent: Double; let windowDurationMins: Int; let resetsAt: Double? }
        struct Limits: Decodable { let primary: Window?; let secondary: Window?; let planType: String? }
        struct LimitsResult: Decodable { let rateLimits: Limits }
        var accountPlan: String?
        if let accountRead {
            let account = try JSONDecoder().decode(Envelope<AccountResult>.self, from: accountRead).result.account
            guard let account, account.type == "chatgpt" else { return UsageSnapshot(provider: .codex, status: .notLoggedIn, fetchedAt: fetchedAt) }
            accountPlan = account.planType
        }
        let limits = try JSONDecoder().decode(Envelope<LimitsResult>.self, from: rateLimitsRead).result.rateLimits
        var windows: [UsageWindow] = []
        for value in [limits.primary, limits.secondary].compactMap({ $0 }) {
            let kind: WindowKind
            switch value.windowDurationMins { case 300: kind = .fiveHour; case 10080: kind = .weekly; default: continue }
            guard value.usedPercent.isFinite else { throw FetchFailure.unexpected }
            // 上限を超えて使うと100超えが返りうる。バーと「一番危ない枠」は100で頭打ちにする
            windows.append(UsageWindow(kind: kind, usedPercent: min(100, max(0, value.usedPercent)), resetsAt: value.resetsAt.map(Date.init(timeIntervalSince1970:))))
        }
        return UsageSnapshot(provider: .codex, plan: plan(limits.planType ?? accountPlan), windows: windows, status: .ok, fetchedAt: fetchedAt)
    }
}
/// JSON-RPC framing stays independent of process I/O and never exposes response bodies in errors.
public enum CodexRPC {
    public static func responseID(_ data: Data) throws -> Int? {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FetchFailure.unexpected }
        guard let id = value["id"] as? Int else { return nil }
        if value["error"] != nil { throw FetchFailure.unexpected }
        return id
    }
}
