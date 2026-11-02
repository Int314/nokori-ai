import AppKit
import Observation
import UsageCore

@MainActor @Observable final class UsageStore {
    private(set) var snapshots: [Provider: UsageSnapshot] = [:]
    private(set) var fetching: Set<Provider> = []
    private var tasks: [Provider: Task<Void, Never>] = [:]
    private var failures: [Provider: Int] = [:]
    private var blockedUntil: [Provider: Date] = [:]
    /// Set only while failing; after a good fetch the next one follows use (`UsagePolicy.nextFetch`).
    private var nextFetch: [Provider: Date] = [:]
    private var lastGoodFetch: [Provider: Date] = [:]
    private var lastActivity: [Provider: Date] = [:]
    private var watcher: ActivityWatcher?
    /// Automatic fetches are off until this time (codex could not start). Unlike `blockedUntil`, a manual refresh ignores it.
    private var autoPausedUntil: [Provider: Date] = [:]
    private var lastWeekly: [Provider: UsageWindow] = [:]
    private var pendingWeeklyReset: [Provider: Date] = [:]
    private let claude: any Fetcher
    private let codex: any Fetcher
    var visible: [Provider] = Provider.allCases
    private var services = DisplayServices.both
    private var cloud: CloudSync?
    var interval: TimeInterval = 300
    var manualPath: String?
    init(claude: any Fetcher = ClaudeFetcher(), codex: any Fetcher = CodexFetcher()) { self.claude = claude; self.codex = codex }
    func configure(services: String, minutes: Int, manualPath: String?) {
        let previous = visible
        let displayServices = DisplayServices(rawValue: services) ?? .both
        let servicesChanged = displayServices != self.services
        self.services = displayServices
        visible = displayServices.providers
        if servicesChanged { push { try await $0.save(services: displayServices) } }
        interval = TimeInterval(minutes * 60)
        let pathChanged = self.manualPath != manualPath
        self.manualPath = manualPath
        for provider in Provider.allCases {
            tasks[provider]?.cancel()
            tasks[provider] = nil
            guard visible.contains(provider) else { continue }
            tasks[provider] = Task { [weak self] in
                guard let self else { return }
                if snapshots[provider] == nil || !previous.contains(provider) || (provider == .codex && pathChanged) {
                    await refresh(provider, userInitiated: false)
                }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    if Date.now >= dueDate(provider) { await refresh(provider, userInitiated: false) }
                }
            }
        }
    }
    func dueDate(_ provider: Provider) -> Date {
        nextFetch[provider] ?? UsagePolicy.nextFetch(after: lastGoodFetch[provider] ?? .distantPast, interval: interval, lastActivity: lastActivity[provider])
    }
    func noteActivity(_ provider: Provider) { lastActivity[provider] = .now }
    func watchActivity() { watcher = ActivityWatcher { [weak self] provider in MainActor.assumeIsolated { self?.noteActivity(provider) } } }
    /// `nil` stops syncing. Turning it on sends what is already known, so the iPhone does not wait for the next fetch.
    func setCloud(_ cloud: CloudSync?) {
        self.cloud = cloud
        let services = services
        push { try await $0.save(services: services) }
        for snapshot in snapshots.values where snapshot.status == .ok { push { try await $0.save(snapshot: snapshot) } }
    }
    /// Sync failures never reach the UI: the menu bar keeps working and the next success retries.
    private func push(_ operation: @escaping @Sendable (CloudSync) async throws -> Void) {
        guard let cloud else { return }
        Task { try? await operation(cloud) }
    }
    func refreshAll(userInitiated: Bool = false, onOpen: Bool = false) {
        for provider in visible {
            if onOpen, let date = snapshots[provider]?.fetchedAt, Date.now.timeIntervalSince(date) < 60 { continue }
            Task { await refresh(provider, userInitiated: userInitiated) }
        }
    }
    func refresh(_ provider: Provider, userInitiated: Bool) async {
        guard visible.contains(provider), !fetching.contains(provider), Date.now >= (blockedUntil[provider] ?? .distantPast) else { return }
        guard userInitiated || Date.now >= (autoPausedUntil[provider] ?? .distantPast) else { return }
        fetching.insert(provider)
        defer { fetching.remove(provider) }
        let result = await (provider == .claude ? claude : codex).fetch(userInitiated: userInitiated, manualPath: manualPath)
        let snapshot = result.snapshot
        if snapshot.status == .ok {
            failures[provider] = 0
            lastGoodFetch[provider] = .now
            nextFetch[provider] = nil
        } else {
            failures[provider] = min(10, (failures[provider] ?? 0) + 1)
            let delay = UsagePolicy.retryDelay(interval: interval, failures: failures[provider] ?? 0, retryAfter: result.retryAfter)
            if snapshot.status == .failed(.rateLimited) { blockedUntil[provider] = Date.now.addingTimeInterval(delay) }
            nextFetch[provider] = Date.now.addingTimeInterval(delay)
        }
        autoPausedUntil[provider] = snapshot.status == .failed(.launchFailed) ? Date.now.addingTimeInterval(UsagePolicy.launchFailedPause) : nil
        var windows = snapshot.status == .ok ? snapshot.windows : []
        if let index = windows.firstIndex(where: { $0.kind == .weekly && $0.model == nil }) {
            let guarded = WeeklyResetGuard.apply(previous: lastWeekly[provider], fetched: windows[index], pending: pendingWeeklyReset[provider], now: .now)
            windows[index] = guarded.window
            lastWeekly[provider] = guarded.window
            pendingWeeklyReset[provider] = guarded.pending
        }
        snapshots[provider] = UsageSnapshot(provider: provider, plan: snapshot.status == .ok ? snapshot.plan : snapshots[provider]?.plan,
                                            windows: windows, status: snapshot.status, fetchedAt: snapshot.fetchedAt)
        if snapshot.status == .ok, let saved = snapshots[provider] { push { try await $0.save(snapshot: saved) } }
        else if snapshot.status != .ok { push { try await $0.save(issue: snapshot.status, for: provider) } }
    }
    func snapshot(_ provider: Provider) -> UsageSnapshot {
        snapshots[provider] ?? UsageSnapshot(provider: provider, status: .notLoggedIn, fetchedAt: .distantPast)
    }
}
