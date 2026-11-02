import SwiftUI
import UsageCore
import UsageUI

struct ContentView: View {
    let model: UsageModel
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    var body: some View {
        let theme = Theme(scheme)
        let snapshots = model.content?.visible ?? []
        TimelineView(.everyMinute) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(snapshots, now: context.date)
                    notice(snapshots, now: context.date)
                    if snapshots.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 30)).foregroundStyle(theme.sub)
                            Text("No usage yet").font(.system(size: 15, weight: .semibold))
                            Text("Open Nokori AI on your Mac and your usage will appear here.")
                                .font(.system(size: 13)).foregroundStyle(theme.sub).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 16)
                            .background(theme.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                    ForEach(snapshots, id: \.provider) { snapshot in
                        ServiceSection(snapshot: snapshot, now: context.date, layout: .phone)
                            .padding(18).background(theme.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                    Text("Services follow the Mac's settings").font(.system(size: 12)).foregroundStyle(theme.sub)
                        .frame(maxWidth: .infinity)
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
            }.refreshable { await model.pull() }
        }.foregroundStyle(theme.text).background(theme.screen.ignoresSafeArea())
    }
    /// A failed read says why; old data says what the Mac reported, or else points at the Mac being asleep or not running.
    @ViewBuilder private func notice(_ snapshots: [UsageSnapshot], now: Date) -> some View {
        let formatter = UsageFormatter(locale: locale)
        if let failure = model.failure {
            noticeCard(formatter.sync(failure), icon: icon(failure))
        } else if let issue = model.content?.issue(now: now) {
            noticeCard(formatter.macIssue(issue.status, provider: issue.provider), icon: "desktopcomputer")
        } else if snapshots.contains(where: { UsagePolicy.isStale(fetchedAt: $0.fetchedAt, now: now) }) {
            noticeCard(formatter.noNewData, icon: "desktopcomputer")
        }
    }
    private func icon(_ failure: SyncFailure) -> String {
        switch failure {
        case .noAccount: "person.crop.circle.badge.exclamationmark"
        case .offline: "wifi.slash"
        case .busy: "hourglass"
        case .other: "exclamationmark.icloud"
        }
    }
    private func noticeCard(_ message: (title: String, detail: String), icon: String) -> some View {
        let theme = Theme(scheme)
        return HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: message.title).font(.system(size: 14, weight: .semibold))
                Text(verbatim: message.detail).font(.system(size: 12)).foregroundStyle(theme.sub).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { Task { await model.pull() } } label: { Text("Retry") }.buttonStyle(ChipButtonStyle())
        }.padding(14).background(theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
    private func header(_ snapshots: [UsageSnapshot], now: Date) -> some View {
        let theme = Theme(scheme)
        let stale = snapshots.contains { UsagePolicy.isStale(fetchedAt: $0.fetchedAt, now: now) }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Nokori AI").font(.system(size: 32, weight: .bold))
                // The newest fetch says whether the Mac is at work; an unused service is fetched only half-hourly, so the oldest would look stuck.
                if let date = snapshots.map(\.fetchedAt).max() {
                    // The dot turns orange once the numbers are too old to trust, matching the dimmed cards.
                    HStack(spacing: 6) {
                        Circle().fill(stale ? Color.orange : Color.green).frame(width: 7, height: 7)
                        Text("\(UsageFormatter(locale: locale).dataAge(date, now: now)) ・ Fetched on Mac")
                    }.font(.system(size: 13)).foregroundStyle(theme.sub)
                }
            }
            Spacer()
            // Appearance is set once and rarely again, so it lives behind a button instead of on the screen.
            Menu {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 17, weight: .medium)).foregroundStyle(theme.text)
                    .frame(width: 36, height: 36).background(theme.card, in: Circle())
            }.accessibilityLabel(Text("Appearance")).padding(.top, 6)
        }
    }
}
