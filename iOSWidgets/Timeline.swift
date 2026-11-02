import Foundation
import os
import UsageCore
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshots: [UsageSnapshot]
    /// The small widget drawn as bars instead of rings.
    var bars = false

    /// Older than the iPhone's stale limit at this entry's time.
    func isStale(_ snapshot: UsageSnapshot) -> Bool { UsagePolicy.isStale(fetchedAt: snapshot.fetchedAt, now: date) }
    /// The footer says how old the data is only while something is stale.
    var staleSince: Date? { snapshots.contains(where: isStale) ? snapshots.map(\.fetchedAt).min() : nil }
}

/// The widget reads what the app stored. If that is old, it asks CloudKit itself, but gives up after 10 seconds.
enum UsageSource {
    static func load(now: Date = .now) async -> SharedStore.Content? {
        let store = SharedStore()
        let stored = store.load()
        if let stored, now.timeIntervalSince(stored.syncedAt) <= 15 * 60 { return stored }
        let fetched = await withTimeout(seconds: 10) { () -> SharedStore.Content? in
            guard let data = try? await CloudSync().fetchAll() else { return nil }
            return SharedStore.Content(snapshots: data.snapshots, issues: data.issues, services: data.services, syncedAt: .now)
        }
        guard let fetched else { return stored }
        try? store.save(fetched)
        return fetched
    }
    /// CloudKit's async calls do not stop on cancellation, so a task group would wait for them; resume once, whichever finishes first.
    private static func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> T?) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (T?) -> Void = { value in
                if !resumed.withLock({ let was = $0; $0 = true; return was }) { continuation.resume(returning: value) }
            }
            Task { finish(await operation()) }
            Task { try? await Task.sleep(for: .seconds(seconds)); finish(nil) }
        }
    }

    /// Now, every minute until the next reload so the time left to reset counts down, and the moment each fresh snapshot turns stale.
    static func timeline(_ snapshots: [UsageSnapshot], bars: Bool = false, now: Date = .now) -> Timeline<UsageEntry> {
        let next = now.addingTimeInterval(15 * 60)
        let minute = (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        let ticks = (1...15).map { Date(timeIntervalSinceReferenceDate: minute + Double($0) * 60) }
        let flips = snapshots.map { $0.fetchedAt.addingTimeInterval(45 * 60 + 1) }
        let dates = Set((ticks + flips).filter { $0 > now && $0 < next }).sorted()
        return Timeline(entries: ([now] + dates).map { UsageEntry(date: $0, snapshots: snapshots, bars: bars) }, policy: .after(next))
    }
}

private let sample: [UsageSnapshot] = {
    let now = Date.now
    return [UsageSnapshot(provider: .claude, plan: "Max 5x", windows: [
                .init(kind: .fiveHour, usedPercent: 42, resetsAt: now.addingTimeInterval(8040)),
                .init(kind: .weekly, usedPercent: 68, resetsAt: now.addingTimeInterval(7 * 86400 * 0.46)),
                .init(kind: .weekly, usedPercent: 35, resetsAt: now.addingTimeInterval(7 * 86400 * 0.46), model: "Fable")], status: .ok, fetchedAt: now),
            UsageSnapshot(provider: .codex, plan: "Plus", windows: [
                .init(kind: .fiveHour, usedPercent: 18, resetsAt: now.addingTimeInterval(13200)),
                .init(kind: .weekly, usedPercent: 22, resetsAt: now.addingTimeInterval(7 * 86400 * 0.74))], status: .ok, fetchedAt: now)]
}()

struct UsageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, snapshots: sample) }
    func snapshot(for configuration: SelectServicesIntent, in context: Context) async -> UsageEntry {
        let bars = configuration.style == .bars
        return context.isPreview ? UsageEntry(date: .now, snapshots: sample, bars: bars)
            : UsageEntry(date: .now, snapshots: await UsageSource.snapshots(configuration.services.provider), bars: bars)
    }
    func timeline(for configuration: SelectServicesIntent, in context: Context) async -> Timeline<UsageEntry> {
        UsageSource.timeline(await UsageSource.snapshots(configuration.services.provider), bars: configuration.style == .bars)
    }
}

struct RingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, snapshots: [sample[0]]) }
    func snapshot(for configuration: SelectServiceIntent, in context: Context) async -> UsageEntry {
        context.isPreview ? placeholder(in: context) : UsageEntry(date: .now, snapshots: await UsageSource.snapshots(configuration.service.provider))
    }
    func timeline(for configuration: SelectServiceIntent, in context: Context) async -> Timeline<UsageEntry> {
        UsageSource.timeline(await UsageSource.snapshots(configuration.service.provider))
    }
}

extension UsageSource {
    /// nil means the services the Mac shows. A chosen service is shown even if the Mac stopped showing it; it simply goes stale.
    static func snapshots(_ provider: Provider?) async -> [UsageSnapshot] {
        guard let content = await load() else { return [] }
        guard let provider else { return content.visible }
        return content.snapshots.filter { $0.provider == provider }
    }
}
