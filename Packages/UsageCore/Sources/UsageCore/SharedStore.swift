import Foundation

/// What the iPhone app last pulled from CloudKit, shared with the widgets through the App Group.
public struct SharedStore: Sendable {
    public static let appGroup = Bundle.main.identifier("NokoriAppGroup")
    public struct Content: Sendable, Equatable {
        public let snapshots: [UsageSnapshot]
        /// Why the Mac's latest fetch of a service failed, if it did.
        public let issues: [Provider: FetchStatus]
        public let services: DisplayServices
        /// When this device last pulled from CloudKit (not when the Mac fetched).
        public let syncedAt: Date
        public init(snapshots: [UsageSnapshot], issues: [Provider: FetchStatus] = [:], services: DisplayServices, syncedAt: Date) {
            self.snapshots = snapshots; self.issues = issues; self.services = services; self.syncedAt = syncedAt
        }
        /// Snapshots for the services the Mac shows, in Claude, Codex order.
        public var visible: [UsageSnapshot] { services.providers.compactMap { provider in snapshots.first { $0.provider == provider } } }
        /// The first shown service whose data is old or missing because the Mac could not fetch it. A failure behind fresh data is passing, so it is left out.
        public func issue(now: Date) -> (provider: Provider, status: FetchStatus)? {
            for provider in services.providers {
                guard let status = issues[provider], status != .ok else { continue }
                let snapshot = snapshots.first { $0.provider == provider }
                if snapshot.map({ UsagePolicy.isStale(fetchedAt: $0.fetchedAt, now: now) }) ?? true { return (provider, status) }
            }
            return nil
        }
    }
    private let suiteName: String
    public init(suiteName: String = SharedStore.appGroup) { self.suiteName = suiteName }
    // `UserDefaults` is not Sendable, so open it per call. The suite is nil only for the app's own bundle ID or the global domain.
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
    public func save(_ content: Content) throws {
        defaults.set(try JSONEncoder().encode(content.snapshots), forKey: "snapshots")
        defaults.set(try JSONEncoder().encode(content.issues), forKey: "issues")
        defaults.set(content.services.rawValue, forKey: "services")
        defaults.set(content.syncedAt, forKey: "syncedAt")
    }
    public func load() -> Content? {
        guard let json = defaults.data(forKey: "snapshots"), let snapshots = try? JSONDecoder().decode([UsageSnapshot].self, from: json),
              let syncedAt = defaults.object(forKey: "syncedAt") as? Date else { return nil }
        let issues = defaults.data(forKey: "issues").flatMap { try? JSONDecoder().decode([Provider: FetchStatus].self, from: $0) } ?? [:]
        return Content(snapshots: snapshots, issues: issues, services: defaults.string(forKey: "services").flatMap(DisplayServices.init(rawValue:)) ?? .both, syncedAt: syncedAt)
    }
}

extension Bundle {
    /// An identifier registered with Apple, which project.yml writes into Info.plist from Config/Identity.xcconfig, so that
    /// whoever builds the apps changes it in one place.
    func identifier(_ key: String) -> String {
        guard let value = object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { fatalError("\(key) is missing from Info.plist") }
        return value
    }
}
