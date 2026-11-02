import SwiftUI
import UsageCore
import UsageUI

enum MenuPreset: String, CaseIterable {
    case bars, vertical, numbers, riskiest
    var title: String {
        switch self {
        case .bars: String(localized: "Two bars")
        case .vertical: String(localized: "Vertical bars")
        case .numbers: String(localized: "Numbers only")
        case .riskiest: String(localized: "Riskiest window")
        }
    }
}
struct MenuBarIcon: View {
    let snapshots: [UsageSnapshot]
    let preset: MenuPreset
    let now: Date
    private let track = Color.black.opacity(0.2)
    var body: some View {
        HStack(spacing: preset == .numbers ? 8 : (preset == .vertical ? 9 : 12)) {
            if preset == .riskiest {
                if let risky = UsagePolicy.riskiest(snapshots.filter { $0.isDisplayable(now: now) }) {
                    HStack(spacing: 4) {
                        Text(verbatim: risky.provider.label).bold()
                        UsageBar(percent: risky.window.usedPercent, tint: .black, track: track, height: 4).frame(width: 26)
                        HStack(spacing: 0) {
                            Text(verbatim: "\(Int(risky.window.usedPercent.rounded()))").fontWeight(.semibold)
                            Text(UsageFormatter().shortWindowName(risky.window.kind)).opacity(0.55)
                        }
                    }.font(.system(size: 10))
                } else { Text(verbatim: "–").opacity(0.4) }
            } else {
                ForEach(snapshots, id: \.provider) { snapshot in service(snapshot) }
            }
        }.foregroundStyle(.black).monospacedDigit().frame(height: 22).fixedSize()
    }
    private func service(_ snapshot: UsageSnapshot) -> some View {
        let valid = snapshot.isDisplayable(now: now)
        let five = valid ? snapshot.window(.fiveHour) : nil
        let week = valid ? snapshot.window(.weekly) : nil
        return HStack(spacing: preset == .vertical ? 3 : 4) {
            Text(verbatim: snapshot.provider.label).font(.system(size: preset == .numbers ? 11 : 10, weight: .bold))
            switch preset {
            case .bars:
                VStack(spacing: 2) {
                    UsageBar(percent: five?.usedPercent ?? 0, tint: .black, track: track, height: 4)
                    UsageBar(percent: week?.usedPercent ?? 0, tint: .black.opacity(0.55), track: track, height: 2)
                }.frame(width: 28)
            case .vertical:
                HStack(spacing: 2) {
                    vertical(five?.usedPercent ?? 0, opacity: 1)
                    vertical(week?.usedPercent ?? 0, opacity: 0.55)
                }
            case .numbers:
                HStack(spacing: 0) {
                    Text(verbatim: number(five))
                    Text(verbatim: "/" + number(week)).opacity(0.55)
                }.font(.system(size: 11))
            case .riskiest: EmptyView()
            }
        }.opacity(valid ? 1 : 0.4)
    }
    private func number(_ window: UsageWindow?) -> String { window.map { String(Int($0.usedPercent.rounded())) } ?? "–" }
    private func vertical(_ percent: Double, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 1.5).fill(track).frame(width: 4, height: 14)
            .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 1.5).fill(.black.opacity(opacity)).frame(width: 4, height: 14 * min(1, max(0, percent / 100))) }
    }
    @MainActor func image() -> NSImage {
        let renderer = ImageRenderer(content: self)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 22, height: 22))
        image.isTemplate = true
        return image
    }
}
struct MenuBarLabel: View {
    let store: UsageStore
    @AppStorage("preset") private var preset = MenuPreset.bars.rawValue
    @State private var now = Date.now
    // MenuBarExtra のラベルに TimelineView を置くと、起動時に再描画が止まらずアイコンが出ない
    var body: some View {
        let snapshots = store.visible.map { store.snapshot($0) }
        Image(nsImage: MenuBarIcon(snapshots: snapshots, preset: MenuPreset(rawValue: preset) ?? .bars, now: now).image())
            .accessibilityLabel(snapshots.map { UsageFormatter().accessibility($0, now: now) }.joined(separator: "; "))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    now = .now
                }
            }
    }
}
