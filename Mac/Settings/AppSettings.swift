import SwiftUI
import ServiceManagement

@MainActor enum AppSettings {
    static func initialize() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "initialized") else { return }
        let claude = ClaudeFetcher.hasLogin(), codex = CodexFetcher.hasLogin()
        defaults.set(claude == codex ? "both" : (claude ? "claude" : "codex"), forKey: "services")
        defaults.set(true, forKey: "syncIPhone")
        do { try SMAppService.mainApp.register(); defaults.set(true, forKey: "launchAtLogin") }
        catch { defaults.set(false, forKey: "launchAtLogin") }
        defaults.set(true, forKey: "initialized")
    }
    static func appearance(_ value: String) {
        NSApp.appearance = value == "system" ? nil : NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
    }
}
