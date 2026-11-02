import Foundation

public enum Provider: String, Codable, Sendable, Equatable, CaseIterable {
    case claude, codex
    public var name: String { self == .claude ? "Claude Code" : "Codex" }
    public var shortName: String { self == .claude ? "Claude" : "Codex" }
    public var label: String { self == .claude ? "C" : "X" }
}
/// The Mac's "services to show" setting, synced to the iPhone.
public enum DisplayServices: String, Codable, Sendable, Equatable {
    case both, claude, codex
    public var providers: [Provider] { Provider.allCases.filter { self == .both || $0.rawValue == rawValue } }
}
public enum WindowKind: String, Codable, Sendable, Equatable, CaseIterable { case fiveHour, weekly }
public struct UsageWindow: Codable, Sendable, Equatable {
    public let kind: WindowKind
    public let usedPercent: Double
    public let resetsAt: Date?
    /// Set for a weekly limit that counts only one model (Claude's "Fable only"); nil for the plan-wide windows.
    public let model: String?
    public init(kind: WindowKind, usedPercent: Double, resetsAt: Date?, model: String? = nil) {
        self.kind = kind; self.usedPercent = usedPercent; self.resetsAt = resetsAt; self.model = model
    }
}
public enum FetchFailure: String, Codable, Sendable, Equatable, Error {
    case network, timeout, rateLimited, codexNotFound, launchFailed, unexpected
}
public enum FetchStatus: Codable, Sendable, Equatable {
    case ok, notLoggedIn, expired, needsKeychainPermission, keychainChanged, failed(FetchFailure)
    /// Both keychain cases are fixed by the same button: read with the permission dialog allowed.
    public var needsKeychainAccess: Bool { self == .needsKeychainPermission || self == .keychainChanged }
}
public enum KeychainState {
    /// Dates are the keychain item's modification dates. `lastReadModification` is nil until the item has been read once.
    public static func status(lastReadModification: Date?, currentModification: Date?) -> FetchStatus {
        if let last = lastReadModification, let current = currentModification, current > last { return .keychainChanged }
        return .needsKeychainPermission
    }
    /// `decryptApplications` holds each decrypt ACL entry's trusted application paths; nil means any application.
    /// Claude Code writes the item with `/usr/bin/security`, so that tool stays trusted after every renewal.
    public static func securityCanRead(decryptApplications: [[String]?], securityPath: String = "/usr/bin/security") -> Bool {
        decryptApplications.contains { $0?.contains(securityPath) ?? true }
    }
}
public enum WeeklyResetGuard {
    /// The server sometimes returns a different weekly reset for one response. Keep the previous window until the same new value comes twice.
    public static func apply(previous: UsageWindow?, fetched: UsageWindow, pending: Date?, now: Date) -> (window: UsageWindow, pending: Date?) {
        guard let previous, let before = previous.resetsAt, let after = fetched.resetsAt,
              now < before.addingTimeInterval(-60), abs(after.timeIntervalSince(before)) >= 3600 else { return (fetched, nil) }
        if pending == after { return (fetched, nil) }
        return (previous, after)
    }
}
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let provider: Provider
    public let plan: String?
    public let windows: [UsageWindow]
    public let status: FetchStatus
    public let fetchedAt: Date
    public init(provider: Provider, plan: String? = nil, windows: [UsageWindow] = [], status: FetchStatus, fetchedAt: Date) {
        self.provider = provider; self.plan = plan; self.windows = windows; self.status = status; self.fetchedAt = fetchedAt
    }
    public func window(_ kind: WindowKind) -> UsageWindow? { windows.first { $0.kind == kind && $0.model == nil } }
    public var modelWindows: [UsageWindow] { windows.filter { $0.model != nil } }
    public func isDisplayable(now: Date) -> Bool { status == .ok && !UsagePolicy.isStale(fetchedAt: fetchedAt, now: now) }
}
public struct Pace: Sendable, Equatable { public let elapsed: Double; public let difference: Double }
public enum UsagePolicy {
    public static func pace(usedPercent: Double, resetsAt: Date?, now: Date) -> Pace? {
        guard let resetsAt else { return nil }
        let elapsed = 1 - resetsAt.timeIntervalSince(now) / (7 * 86400)
        return Pace(elapsed: elapsed, difference: usedPercent - elapsed * 100)
    }
    public static func isStale(fetchedAt: Date, now: Date) -> Bool { now.timeIntervalSince(fetchedAt) > 45 * 60 }
    public static func riskiest(_ snapshots: [UsageSnapshot]) -> (provider: Provider, window: UsageWindow)? {
        snapshots.filter { $0.status == .ok }.flatMap { snapshot in
            snapshot.windows.map { (provider: snapshot.provider, window: $0) }
        }.max {
            if $0.window.usedPercent != $1.window.usedPercent { return $0.window.usedPercent < $1.window.usedPercent }
            return ($0.window.resetsAt ?? .distantFuture) < ($1.window.resetsAt ?? .distantFuture)
        }
    }
    /// Usage can move without Claude Code or Codex running here (the web, other devices), but rarely enough for this.
    public static let idleInterval: TimeInterval = 1800
    /// When the next automatic fetch is due after a good one: the set interval once the tool has been used since, else the idle cadence.
    public static func nextFetch(after lastFetch: Date, interval: TimeInterval, lastActivity: Date?) -> Date {
        let active = lastActivity.map { $0 >= lastFetch } ?? false
        return lastFetch.addingTimeInterval(active ? interval : max(interval, idleInterval))
    }
    /// How long automatic fetches stay off after codex could not be started. A manual refresh is never held back.
    public static let launchFailedPause: TimeInterval = 1800
    public static func retryDelay(interval: TimeInterval, failures: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter { return max(0, retryAfter) }
        return min(1800, interval * pow(2, Double(min(10, max(0, failures)))))
    }
    public static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
/// Claude Code renews its own sign-in when it starts, so the Mac starts it briefly instead of renewing the token itself:
/// Anthropic's refresh tokens are single-use, and a renewal outside Claude Code would sign Claude Code out.
public enum ClaudeRenewal {
    /// A start that cannot renew (signed out, offline) would otherwise repeat on every fetch.
    public static let cooldown: TimeInterval = 1800
    public static func shouldTry(lastAttempt: Date?, now: Date) -> Bool { lastAttempt.map { now.timeIntervalSince($0) >= cooldown } ?? true }
    /// Claude Code's folder-trust question. The terminal places each word with cursor moves, so compare letters only.
    public static func asksForTrust(_ screen: String) -> Bool {
        let text = screen.replacingOccurrences(of: "\u{1B}\\[[0-9;?<>=]*[ -/]*[@-~]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}.", with: "", options: .regularExpression)
        return text.filter(\.isLetter).lowercased().contains("itrustthisfolder")
    }
}
