import Foundation
import UsageCore

struct FetchResult: Sendable {
    let snapshot: UsageSnapshot
    var retryAfter: TimeInterval?
    static func failure(_ provider: Provider, _ status: FetchStatus, retryAfter: TimeInterval? = nil) -> Self {
        Self(snapshot: UsageSnapshot(provider: provider, status: status, fetchedAt: .now), retryAfter: retryAfter)
    }
}
protocol Fetcher: Sendable {
    func fetch(userInitiated: Bool, manualPath: String?) async -> FetchResult
}
enum AppVersion {
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
}
