#if DEBUG
import SwiftUI
import UsageCore
import UsageUI

/// Local, synthetic visual review. No keychain, network, CLI, or login-item registration.
@MainActor enum DebugPreviews {
    private struct SampleFetcher: Fetcher {
        let snapshot: UsageSnapshot
        func fetch(userInitiated: Bool, manualPath: String?) async -> FetchResult { FetchResult(snapshot: snapshot) }
    }
    static func render() async throws {
        let directory = URL(fileURLWithPath: "/tmp/nokori-visual-review", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date.now
        let claude = UsageSnapshot(provider: .claude, plan: "Max 5x", windows: [
            .init(kind: .fiveHour, usedPercent: 42, resetsAt: now.addingTimeInterval(8040)),
            .init(kind: .weekly, usedPercent: 68, resetsAt: now.addingTimeInterval(7 * 86400 * 0.46))], status: .ok, fetchedAt: now.addingTimeInterval(-60))
        let codex = UsageSnapshot(provider: .codex, plan: "Plus", windows: [
            .init(kind: .fiveHour, usedPercent: 18, resetsAt: now.addingTimeInterval(13200)),
            .init(kind: .weekly, usedPercent: 22, resetsAt: now.addingTimeInterval(7 * 86400 * 0.74))], status: .ok, fetchedAt: now.addingTimeInterval(-60))
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            let store = UsageStore(claude: SampleFetcher(snapshot: claude), codex: SampleFetcher(snapshot: codex))
            await store.refresh(.claude, userInitiated: false)
            await store.refresh(.codex, userInitiated: false)
            try save(UsagePopover(store: store), scheme: scheme, to: directory.appendingPathComponent("popover-\(name).png"))
            let failure = UsageSnapshot(provider: .claude, status: .needsKeychainPermission, fetchedAt: now)
            let errorStore = UsageStore(claude: SampleFetcher(snapshot: failure), codex: SampleFetcher(snapshot: codex))
            await errorStore.refresh(.claude, userInitiated: false)
            await errorStore.refresh(.codex, userInitiated: false)
            try save(UsagePopover(store: errorStore), scheme: scheme, to: directory.appendingPathComponent("error-\(name).png"))
            try saveNative(SettingsView(), scheme: scheme, to: directory.appendingPathComponent("settings-\(name).png"))
            let presets = VStack(alignment: .leading, spacing: 16) {
                ForEach(MenuPreset.allCases, id: \.rawValue) { preset in
                    HStack {
                        Text(preset.title).frame(width: 140, alignment: .leading)
                        Image(nsImage: MenuBarIcon(snapshots: [claude, codex], preset: preset, now: now).image())
                    }
                }
            }.padding(20).foregroundStyle(Theme(scheme).text).background(Theme(scheme).menubar)
            try save(presets, scheme: scheme, to: directory.appendingPathComponent("presets-\(name).png"))
        }
    }
    private static func saveNative<V: View>(_ view: V, scheme: ColorScheme, to url: URL) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")))
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw FetchFailure.unexpected }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw FetchFailure.unexpected }
        try data.write(to: url)
    }
    private static func save<V: View>(_ view: V, scheme: ColorScheme, to url: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")))
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw FetchFailure.unexpected }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw FetchFailure.unexpected }
        try data.write(to: url)
    }
}
#endif
