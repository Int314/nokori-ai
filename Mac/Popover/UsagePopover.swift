import SwiftUI
import UsageCore
import UsageUI

struct UsagePopover: View {
    let store: UsageStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    var body: some View {
        TimelineView(.everyMinute) { context in
            let theme = Theme(scheme)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Usage").font(.system(size: 14, weight: .bold))
                    Spacer()
                    if let date = store.visible.compactMap({ store.snapshots[$0]?.fetchedAt }).min() {
                        Text(UsageFormatter(locale: locale).updated(date, now: context.date)).font(.system(size: 11)).foregroundStyle(theme.sub)
                    }
                    Button { store.refreshAll(userInitiated: true) } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14)).frame(width: 24, height: 24)
                            .background(theme.chip, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).help("Refresh now").accessibilityLabel("Refresh now")
                }
                ForEach(Array(store.visible.enumerated()), id: \.element) { index, provider in
                    if index > 0 { theme.divider.frame(height: 1) }
                    ServiceSection(snapshot: store.snapshot(provider), now: context.date) {
                        Task { await store.refresh(provider, userInitiated: true) }
                    }
                }
                HStack(spacing: 8) {
                    Button("Settings…") { NSApp.activate(ignoringOtherApps: true); openSettings() }
                    Button("Quit") { NSApp.terminate(nil) }
                }.buttonStyle(ChipButtonStyle()).padding(.top, 2)
            }.padding(16).frame(width: 340).foregroundStyle(theme.text).background(theme.pop)
        }.onAppear { store.refreshAll(onOpen: true) }
    }
}
