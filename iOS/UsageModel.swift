import BackgroundTasks
import Observation
import UsageCore
import WidgetKit

/// Pulls what the Mac wrote to CloudKit and hands it to the widgets through the App Group.
@MainActor @Observable final class UsageModel {
    static let shared = UsageModel()
    static let refreshID = "dev.int314.nokori.refresh"
    private(set) var content: SharedStore.Content?
    /// Why the last read from iCloud failed; nil once one succeeds.
    private(set) var failure: SyncFailure?
    private let store = SharedStore()
    private let cloud = CloudSync()
    private init() {
        content = store.load()
        #if DEBUG
        if CommandLine.arguments.contains("--sample") { content = Self.sample }
        if CommandLine.arguments.contains("--sample-failure") { failure = .offline }
        #endif
    }
    @discardableResult func pull() async -> Bool {
        #if DEBUG
        if CommandLine.arguments.contains("--sample") { return false }
        #endif
        do {
            let fetched = try await cloud.fetchAll()
            let content = SharedStore.Content(snapshots: fetched.snapshots, issues: fetched.issues, services: fetched.services, syncedAt: .now)
            try store.save(content)
            self.content = content
            WidgetCenter.shared.reloadAllTimelines()
            failure = nil
            return true
        } catch {
            failure = SyncFailure(error)
            return false
        }
    }
    func subscribe() async {
        #if DEBUG
        if CommandLine.arguments.contains("--sample") { return }
        #endif
        try? await cloud.subscribeToChanges()
    }
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    #if DEBUG
    /// Synthetic data for looking at the screen in a simulator without iCloud: launch with `--sample`.
    private static var sample: SharedStore.Content {
        let now = Date.now
        return SharedStore.Content(snapshots: [
            UsageSnapshot(provider: .claude, plan: "Max 5x", windows: [
                .init(kind: .fiveHour, usedPercent: 42, resetsAt: now.addingTimeInterval(8040)),
                .init(kind: .weekly, usedPercent: 68, resetsAt: now.addingTimeInterval(7 * 86400 * 0.46)),
                .init(kind: .weekly, usedPercent: 35, resetsAt: now.addingTimeInterval(7 * 86400 * 0.46), model: "Fable")], status: .ok, fetchedAt: now.addingTimeInterval(-12 * 60)),
            UsageSnapshot(provider: .codex, plan: "Plus", windows: [
                .init(kind: .fiveHour, usedPercent: 18, resetsAt: now.addingTimeInterval(13200)),
                .init(kind: .weekly, usedPercent: 22, resetsAt: now.addingTimeInterval(7 * 86400 * 0.74))], status: .ok, fetchedAt: now.addingTimeInterval(-12 * 60))
        ], services: .both, syncedAt: now)
    }
    #endif
}
