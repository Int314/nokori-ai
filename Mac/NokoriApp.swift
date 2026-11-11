import SwiftUI
import UsageCore

@main struct NokoriApp: App {
    @State private var store: UsageStore
    @AppStorage("services") private var services = "both"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("interval") private var interval = 5
    @AppStorage("manualCodex") private var manualCodex = false
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("claudeApp") private var claudeApp = false
    @AppStorage("syncIPhone") private var syncIPhone = true
    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--render-previews") {
            Task {
                do { try await DebugPreviews.render(); exit(0) }
                catch { exit(1) }
            }
            RunLoop.main.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--probe") {
            Task {
                await withTaskGroup(of: FetchResult.self) { group in
                    group.addTask { await ClaudeFetcher().fetch(userInitiated: false, manualPath: nil) }
                    group.addTask {
                        await CodexFetcher().fetch(userInitiated: false, manualPath: UserDefaults.standard.bool(forKey: "manualCodex") ? UserDefaults.standard.string(forKey: "codexPath") : nil)
                    }
                    var fetched: [UsageSnapshot] = []
                    for await result in group {
                        let snapshot = result.snapshot
                        fetched.append(snapshot)
                        var lines = ["\(snapshot.provider.name): plan=\(snapshot.plan ?? "–") status=\(snapshot.status)"]
                        for window in snapshot.windows {
                            lines.append("  \(window.kind.rawValue): \(window.usedPercent)% reset=\(window.resetsAt?.ISO8601Format() ?? "–")")
                        }
                        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
                    }
                    // 署名に iCloud の権限があれば、成功分を書いて読み戻す（同期の確認用）
                    if ICloud.entitled {
                        var lines = ["iCloud account available=\(await ICloud.available())"]
                        do {
                            let cloud = CloudSync()
                            for snapshot in fetched where snapshot.status == .ok { try await cloud.save(snapshot: snapshot) }
                            let (snapshots, _, services) = try await cloud.fetchAll()
                            lines.append("iCloud services=\(services)")
                            lines += snapshots.map { "iCloud \($0.provider.name): fetchedAt=\($0.fetchedAt.ISO8601Format()) windows=\($0.windows.map { "\($0.kind.rawValue)=\($0.usedPercent)" })" }
                        } catch { lines.append("iCloud error: \(error)") }
                        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
                    }
                }
                exit(0)
            }
            RunLoop.main.run()
            exit(0)
        }
        #endif
        AppSettings.initialize()
        let store = UsageStore()
        _store = State(initialValue: store)
        let defaults = UserDefaults.standard
        // App の init の時点では NSApp がまだ nil なので、起動後に当てる
        DispatchQueue.main.async { AppSettings.appearance(defaults.string(forKey: "appearance") ?? "system") }
        store.configure(services: defaults.string(forKey: "services") ?? "both", minutes: defaults.object(forKey: "interval") as? Int ?? 5,
                        manualPath: defaults.bool(forKey: "manualCodex") ? defaults.string(forKey: "codexPath") ?? "" : nil, claudeApp: defaults.bool(forKey: "claudeApp"))
        store.setCloud(ICloud.sync(enabled: defaults.bool(forKey: "syncIPhone")))
        store.watchActivity()
        _ = Updater.controller
    }
    var body: some Scene {
        MenuBarExtra {
            UsagePopover(store: store)
        } label: {
            MenuBarLabel(store: store)
                .onChange(of: services) { configure() }
                .onChange(of: interval) { configure() }
                .onChange(of: manualCodex) { configure() }
                .onChange(of: codexPath) { configure() }
                .onChange(of: claudeApp) { configure() }
                .onChange(of: syncIPhone) { store.setCloud(ICloud.sync(enabled: syncIPhone)) }
                .onChange(of: appearance) { AppSettings.appearance(appearance) }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in store.refreshAll() }
        }.menuBarExtraStyle(.window)
        Settings { SettingsView(store: store) }
    }
    private func configure() { store.configure(services: services, minutes: interval, manualPath: manualCodex ? codexPath : nil, claudeApp: claudeApp) }
}
