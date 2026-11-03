import SwiftUI
import ServiceManagement
import UsageCore
import UsageUI

struct SettingsView: View {
    @AppStorage("services") private var services = "both"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("preset") private var preset = "bars"
    @AppStorage("interval") private var interval = 5
    @AppStorage("manualCodex") private var manualCodex = false
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("syncIPhone") private var syncIPhone = true
    @Environment(\.colorScheme) private var scheme
    @State private var launchError = false
    @State private var iCloudAvailable = true
    @State private var checksForUpdates = Updater.controller.updater.automaticallyChecksForUpdates
    private var previews: [UsageSnapshot] {
        [UsageSnapshot(provider: .claude, windows: [.init(kind: .fiveHour, usedPercent: 42, resetsAt: nil), .init(kind: .weekly, usedPercent: 68, resetsAt: nil)], status: .ok, fetchedAt: .now),
         UsageSnapshot(provider: .codex, windows: [.init(kind: .fiveHour, usedPercent: 18, resetsAt: nil), .init(kind: .weekly, usedPercent: 22, resetsAt: nil)], status: .ok, fetchedAt: .now)]
    }
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 18) {
            GridRow {
                label("Services")
                segments($services, options: [("both", String(localized: "Both")), ("claude", String(localized: "Claude Code only")), ("codex", String(localized: "Codex only"))])
            }
            GridRow {
                label("Appearance")
                segments($appearance, options: [("system", String(localized: "System")), ("light", String(localized: "Light")), ("dark", String(localized: "Dark"))])
            }
            GridRow {
                label("Menu bar display")
                HStack(spacing: 10) {
                    ForEach(MenuPreset.allCases, id: \.rawValue) { option in
                        Button { preset = option.rawValue } label: {
                            VStack(spacing: 8) {
                                Image(nsImage: MenuBarIcon(snapshots: previews, preset: option, now: .now).image())
                                    .frame(maxWidth: .infinity).frame(height: 28).background(Theme(scheme).settingsMenubar, in: RoundedRectangle(cornerRadius: 5))
                                HStack(spacing: 5) {
                                    Image(systemName: preset == option.rawValue ? "largecircle.fill.circle" : "circle")
                                    Text(option.title).font(.system(size: 12))
                                }
                            }.padding(.horizontal, 6).padding(.vertical, 10)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(preset == option.rawValue ? Theme(scheme).text : Theme(scheme).settingsDivider, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityAddTraits(preset == option.rawValue ? [.isSelected] : [])
                    }
                }
            }
            GridRow {
                label("Refresh while in use")
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Refresh while in use", selection: $interval) {
                        Text("5 minutes").tag(5); Text("15 minutes").tag(15); Text("30 minutes").tag(30)
                    }.labelsHidden().frame(width: 120)
                    Text("While Claude Code or Codex is at work. Otherwise every 30 minutes, since usage elsewhere still counts.")
                        .font(.system(size: 12)).foregroundStyle(Theme(scheme).sub)
                }
            }
            GridRow {
                label("Codex path")
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Button { manualCodex = false } label: {
                            Label("Automatic", systemImage: !manualCodex ? "largecircle.fill.circle" : "circle")
                        }.buttonStyle(.plain)
                        Text(CodexFetcher.detectedPath() ?? String(localized: "Not found")).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme(scheme).sub).textSelection(.enabled)
                    }
                    HStack(spacing: 8) {
                        Button { manualCodex = true } label: {
                            Label("Manual", systemImage: manualCodex ? "largecircle.fill.circle" : "circle")
                        }.buttonStyle(.plain)
                        TextField("codex location", text: $codexPath).font(.system(size: 12)).textFieldStyle(.plain)
                            .padding(.horizontal, 8).padding(.vertical, 4).frame(width: 260)
                            .background(Theme(scheme).chip, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme(scheme).settingsDivider, lineWidth: 1)).disabled(!manualCodex)
                        Button("Choose…") { choosePath() }.disabled(!manualCodex)
                    }
                }
            }
            GridRow {
                label("Launch at login")
                Toggle("Start automatically when you log in to your Mac", isOn: $launchAtLogin).toggleStyle(.checkbox)
            }
            GridRow {
                label("Sync to iPhone")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Send usage to iPhone via iCloud", isOn: $syncIPhone).toggleStyle(.checkbox)
                    if syncIPhone && !iCloudAvailable {
                        Text("This Mac isn't signed in to iCloud, so syncing is paused. The menu bar keeps updating.")
                            .font(.system(size: 12)).foregroundStyle(Theme(scheme).sub)
                    }
                }
            }
            GridRow {
                label("Updates")
                VStack(alignment: .leading, spacing: 8) {
                    if Updater.enabled { Toggle("Check for updates automatically", isOn: $checksForUpdates).toggleStyle(.checkbox) }
                    HStack(spacing: 10) {
                        if Updater.enabled {
                            Button("Check Now") { NSApp.activate(ignoringOtherApps: true); Updater.controller.checkForUpdates(nil) }
                                .disabled(!Updater.controller.updater.canCheckForUpdates)
                        }
                        Text("Version \(AppVersion.current)").font(.system(size: 12)).foregroundStyle(Theme(scheme).sub)
                    }
                }
            }
        }.font(.system(size: 13)).padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 28)
            .frame(width: 760).background(Theme(scheme).pop).foregroundStyle(Theme(scheme).text)
            .task { iCloudAvailable = await ICloud.available() }
            .onChange(of: syncIPhone) { Task { iCloudAvailable = await ICloud.available() } }
            .onChange(of: checksForUpdates) { Updater.controller.updater.automaticallyChecksForUpdates = checksForUpdates }
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchError = true
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }.alert("Could not change launch at login", isPresented: $launchError) {
                Button("OK", role: .cancel) {}
            } message: { Text("Check Login Items in System Settings.") }
    }
    private func label(_ key: LocalizedStringKey) -> some View { Text(key).frame(width: 160, alignment: .trailing).gridCellAnchor(.topTrailing).padding(.top, 5) }
    private func segments(_ selection: Binding<String>, options: [(String, String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                Button { selection.wrappedValue = value } label: {
                    Text(title).font(.system(size: 12)).padding(.horizontal, 14).padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 5).fill(selection.wrappedValue == value ? Theme(scheme).pop : .clear)
                                .shadow(color: .black.opacity(selection.wrappedValue == value ? 0.12 : 0), radius: 1, y: 1)
                        }
                }.buttonStyle(.plain).accessibilityAddTraits(selection.wrappedValue == value ? [.isSelected] : [])
            }
        }.padding(2).background(Theme(scheme).chip, in: RoundedRectangle(cornerRadius: 7)).fixedSize()
    }
    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { codexPath = url.path }
    }
}
