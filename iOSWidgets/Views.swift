import SwiftUI
import UsageCore
import UsageUI
import WidgetKit

private let staleOpacity = 0.45

struct UsageEntryView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        switch family {
        case .systemSmall:
            Group { if entry.bars { SmallBarsView(entry: entry) } else { SmallView(entry: entry) } }
                .containerBackground(Theme(scheme).widget, for: .widget)
        case .systemMedium: MediumView(entry: entry).containerBackground(Theme(scheme).widget, for: .widget)
        case .accessoryCircular: CircularView(entry: entry).containerBackground(.clear, for: .widget)
        default: RectangularView(entry: entry).containerBackground(.clear, for: .widget)
        }
    }
}

private struct Empty: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text("Open Nokori AI on your Mac").font(.system(size: 12)).foregroundStyle(Theme(scheme).sub).multilineTextAlignment(.center).padding(16)
    }
}

/// The last line: how old the data is once something is stale, otherwise the given text.
private struct Footer: View {
    let entry: UsageEntry
    let text: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    var body: some View {
        if let date = entry.staleSince {
            Text(UsageFormatter(locale: locale).dataAge(date, now: entry.date)).font(.system(size: 11, weight: .semibold))
        } else {
            // The time left can outgrow a small widget's width in Japanese; shrink rather than wrap onto the rings.
            Text(text).font(.system(size: 11)).foregroundStyle(Theme(scheme).sub).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

private func spokenSummary(_ entry: UsageEntry, locale: Locale) -> String {
    let formatter = UsageFormatter(locale: locale)
    return (entry.snapshots.map { formatter.accessibility($0, now: entry.date, keepsValues: true) }
        + (entry.staleSince.map { [formatter.dataAge($0, now: entry.date)] } ?? [])).joined(separator: ". ")
}

/// Tinted and clear home screens keep only each color's opacity, so an opaque track would look as full as the fill.
private func track(_ theme: Theme, _ mode: WidgetRenderingMode) -> Color { mode == .fullColor ? theme.track : theme.text.opacity(0.25) }

/// The 5-hour time left in a narrow spot; the arrow says it is a reset, since "Resets in" does not fit.
private struct TimeLeft: View {
    let text: String
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.counterclockwise").font(.system(size: 8, weight: .semibold))
            Text(verbatim: text)
        }
    }
}

private func joined(_ parts: String...) -> String { parts.filter { !$0.isEmpty }.joined(separator: " ・ ") }
private func number(_ window: UsageWindow?) -> String { "\(Int((window?.usedPercent ?? 0).rounded()))" }

// MARK: Home screen

private struct SmallView: View {
    let entry: UsageEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.locale) private var locale
    var body: some View {
        let theme = Theme(scheme), formatter = UsageFormatter(locale: locale)
        // StandBy (iPhone charging on its side) drops the card and enlarges the widget, so the rings take the card's margins.
        let standBy = !showsBackground
        Group {
            switch entry.snapshots.count {
            case 0: Empty()
            case 1:
                let snapshot = entry.snapshots[0]
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack(spacing: 5) {
                            Circle().fill(theme.provider(snapshot.provider)).frame(width: 6, height: 6)
                            Text(verbatim: snapshot.provider.name).font(.system(size: 11, weight: .semibold))
                            // StandBy moves the weekly figure up here so the last line has room for the time left at a distance.
                            if standBy {
                                Spacer(minLength: 4)
                                Text(verbatim: formatter.weeklyShort(snapshot)).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.sub)
                            }
                        }
                        Spacer(minLength: 0)
                        ring(snapshot, size: standBy ? 116 : 84, font: standBy ? 30 : 18)
                        Spacer(minLength: 0)
                    }.opacity(entry.isStale(snapshot) ? staleOpacity : 1)
                    let left = formatter.resetsIn(snapshot.window(.fiveHour), now: entry.date)
                    Footer(entry: entry, text: standBy ? left : joined(formatter.weeklyShort(snapshot), left))
                }.padding(standBy ? 4 : 12)
            default:
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(entry.snapshots, id: \.provider) { snapshot in
                            VStack(spacing: 4) {
                                ring(snapshot, size: standBy ? 76 : 66, font: standBy ? 18 : 15)
                                // 「Claude ・ 週68」は列の幅に収まらないので行を分ける
                                VStack(spacing: 0) {
                                    Text(verbatim: snapshot.provider.shortName)
                                    Text(verbatim: formatter.weeklyShort(snapshot))
                                    TimeLeft(text: formatter.timeLeft(snapshot.window(.fiveHour), now: entry.date))
                                }.font(.system(size: 11)).foregroundStyle(theme.sub).lineLimit(1).minimumScaleFactor(0.8)
                            }.frame(maxWidth: .infinity).opacity(entry.isStale(snapshot) ? staleOpacity : 1)
                        }
                    }
                    Spacer(minLength: 0)
                    // Each column carries its own reset, so the last line is only for saying the data is old.
                    if entry.staleSince != nil { Footer(entry: entry, text: "") }
                }.padding(standBy ? EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0) : EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10))
            }
        }.foregroundStyle(theme.text).accessibilityElement(children: .ignore).accessibilityLabel(spokenSummary(entry, locale: locale))
    }
    private func ring(_ snapshot: UsageSnapshot, size: CGFloat, font: CGFloat) -> some View {
        UsageRings(fiveHour: snapshot.window(.fiveHour)?.usedPercent ?? 0, weekly: snapshot.window(.weekly)?.usedPercent ?? 0, tint: Theme(scheme).provider(snapshot.provider), track: track(Theme(scheme), mode))
            .frame(width: size, height: size)
            .overlay { Text(verbatim: number(snapshot.window(.fiveHour))).font(.system(size: font, weight: .bold)) }
    }
}

/// The small widget as bars: every window the app lists, model-only ones included. Two services share the height, so their rows go on one line each.
private struct SmallBarsView: View {
    let entry: UsageEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.locale) private var locale
    var body: some View {
        let theme = Theme(scheme), formatter = UsageFormatter(locale: locale)
        let one = entry.snapshots.count == 1
        Group {
            if entry.snapshots.isEmpty { Empty() } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entry.snapshots, id: \.provider) { snapshot in
                        VStack(alignment: .leading, spacing: one ? 7 : 3) {
                            HStack(spacing: 5) {
                                Circle().fill(theme.provider(snapshot.provider)).frame(width: 6, height: 6)
                                Text(verbatim: one ? snapshot.provider.name : snapshot.provider.shortName).font(.system(size: 11, weight: .semibold))
                                if !one {
                                    Spacer(minLength: 4)
                                    TimeLeft(text: formatter.timeLeft(snapshot.window(.fiveHour), now: entry.date)).font(.system(size: 10)).foregroundStyle(theme.sub)
                                }
                            }
                            ForEach(Array(windows(snapshot, formatter: formatter, short: !one).enumerated()), id: \.offset) { _, item in
                                if one { row(snapshot, item.window, label: item.label) } else { line(snapshot, item.window, label: item.label) }
                            }
                        }.opacity(entry.isStale(snapshot) ? staleOpacity : 1)
                        Spacer(minLength: one ? 4 : 6)
                    }
                    if one { Footer(entry: entry, text: formatter.resetsIn(entry.snapshots[0].window(.fiveHour), now: entry.date)) }
                    else if entry.staleSince != nil { Footer(entry: entry, text: "") }
                }.padding(12)
            }
        }.foregroundStyle(theme.text).accessibilityElement(children: .ignore).accessibilityLabel(spokenSummary(entry, locale: locale))
    }
    private func windows(_ snapshot: UsageSnapshot, formatter: UsageFormatter, short: Bool) -> [(label: String, window: UsageWindow?)] {
        WindowKind.allCases.map { (short ? formatter.shortWindowName($0) : formatter.windowName($0), snapshot.window($0)) }
            + snapshot.modelWindows.map { (short ? $0.model ?? "" : formatter.modelWindowName($0.model ?? ""), $0) }
    }
    private func row(_ snapshot: UsageSnapshot, _ window: UsageWindow?, label: String) -> some View {
        let theme = Theme(scheme)
        return VStack(spacing: 4) {
            HStack {
                Text(verbatim: label).foregroundStyle(theme.sub).lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: UsageFormatter(locale: locale).percent(window)).fontWeight(.semibold).monospacedDigit()
            }.font(.system(size: 11))
            UsageBar(percent: window?.usedPercent ?? 0, tint: theme.provider(snapshot.provider), track: track(theme, mode), height: 4)
        }
    }
    private func line(_ snapshot: UsageSnapshot, _ window: UsageWindow?, label: String) -> some View {
        let theme = Theme(scheme)
        return HStack(spacing: 6) {
            Text(verbatim: label).foregroundStyle(theme.sub).lineLimit(1).minimumScaleFactor(0.8).frame(width: 30, alignment: .leading)
            UsageBar(percent: window?.usedPercent ?? 0, tint: theme.provider(snapshot.provider), track: track(theme, mode), height: 4)
            Text(verbatim: number(window)).fontWeight(.semibold).monospacedDigit().frame(width: 22, alignment: .trailing)
        }.font(.system(size: 10))
    }
}

private struct MediumView: View {
    let entry: UsageEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.locale) private var locale
    var body: some View {
        let theme = Theme(scheme), formatter = UsageFormatter(locale: locale)
        Group {
            switch entry.snapshots.count {
            case 0: Empty()
            case 1:
                let snapshot = entry.snapshots[0]
                VStack(alignment: .leading, spacing: 0) {
                    detail(snapshot).opacity(entry.isStale(snapshot) ? staleOpacity : 1)
                    Spacer(minLength: 4)
                    let pace = snapshot.window(.weekly).flatMap { UsagePolicy.pace(usedPercent: $0.usedPercent, resetsAt: $0.resetsAt, now: entry.date) }
                    Footer(entry: entry, text: pace.map { formatter.pace($0.difference) } ?? "")
                }.padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(entry.snapshots, id: \.provider) { snapshot in
                            column(snapshot).frame(maxWidth: .infinity, alignment: .leading).opacity(entry.isStale(snapshot) ? staleOpacity : 1)
                        }
                    }
                    if entry.staleSince != nil { Footer(entry: entry, text: "") }
                }.padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            }
        }.foregroundStyle(theme.text).accessibilityElement(children: .ignore).accessibilityLabel(spokenSummary(entry, locale: locale))
    }
    private func header(_ snapshot: UsageSnapshot, plan: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Theme(scheme).provider(snapshot.provider)).frame(width: 6, height: 6)
            Text(verbatim: snapshot.provider.name).font(.system(size: 12, weight: .semibold))
            if plan, let name = snapshot.plan {
                Spacer()
                Text(verbatim: name).font(.system(size: 11)).foregroundStyle(Theme(scheme).sub)
            }
        }
    }
    private func column(_ snapshot: UsageSnapshot) -> some View {
        let formatter = UsageFormatter(locale: locale)
        return VStack(alignment: .leading, spacing: 0) {
            header(snapshot, plan: false)
            ForEach(WindowKind.allCases, id: \.self) { kind in
                Spacer(minLength: 9)
                row(snapshot, kind, label: formatter.windowName(kind))
            }
            Spacer(minLength: 4)
            // Once anything is stale, one footer below both columns says how old the data is instead.
            if entry.staleSince == nil {
                Text(formatter.resetsIn(snapshot.window(.fiveHour), now: entry.date)).font(.system(size: 11)).foregroundStyle(Theme(scheme).sub)
            }
        }
    }
    /// The widget is taller than these rows, so the spacers spread them instead of leaving one gap above the footer.
    @ViewBuilder private func detail(_ snapshot: UsageSnapshot) -> some View {
        let formatter = UsageFormatter(locale: locale)
        header(snapshot, plan: true)
        ForEach(WindowKind.allCases, id: \.self) { kind in
            let when = formatter.resetsIn(snapshot.window(kind), now: entry.date)
            Spacer(minLength: kind == .fiveHour ? 9 : 13)
            row(snapshot, kind, label: joined(formatter.windowName(kind), when))
        }
    }
    private func row(_ snapshot: UsageSnapshot, _ kind: WindowKind, label: String) -> some View {
        let theme = Theme(scheme), window = snapshot.window(kind)
        let pace = kind == .weekly ? window.flatMap { UsagePolicy.pace(usedPercent: $0.usedPercent, resetsAt: $0.resetsAt, now: entry.date) } : nil
        return VStack(spacing: 5) {
            HStack {
                Text(verbatim: label).foregroundStyle(theme.sub).lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: UsageFormatter(locale: locale).percent(window)).fontWeight(.semibold).monospacedDigit()
            }.font(.system(size: 11))
            UsageBar(percent: window?.usedPercent ?? 0, tint: theme.provider(snapshot.provider), track: track(theme, mode), height: 4, marker: entry.snapshots.count == 1 ? pace?.elapsed : nil)
        }
    }
}

// MARK: Lock screen

private struct CircularView: View {
    let entry: UsageEntry
    @Environment(\.locale) private var locale
    var body: some View {
        let snapshot = entry.snapshots.first
        ZStack {
            UsageRings(fiveHour: snapshot?.window(.fiveHour)?.usedPercent ?? 0, weekly: snapshot?.window(.weekly)?.usedPercent ?? 0, tint: .white,
                       track: .white.opacity(0.3), lineWidth: 5, innerRadius: 18, innerOpacity: 0.7)
            Text(verbatim: snapshot?.provider.label ?? "").font(.system(size: 11, weight: .bold))
        }.foregroundStyle(.white).opacity(snapshot.map(entry.isStale) ?? true ? staleOpacity : 1).padding(4)
            .accessibilityElement(children: .ignore).accessibilityLabel(snapshot.map { spokenSummary(UsageEntry(date: entry.date, snapshots: [$0]), locale: locale) } ?? "")
    }
}

private struct RectangularView: View {
    let entry: UsageEntry
    @Environment(\.locale) private var locale
    var body: some View {
        let formatter = UsageFormatter(locale: locale)
        VStack(alignment: .leading, spacing: 6) {
            if entry.snapshots.isEmpty { Text("Open Nokori AI on your Mac").font(.system(size: 12)) }
            ForEach(entry.snapshots, id: \.provider) { snapshot in
                let window = snapshot.window(.fiveHour)
                HStack(spacing: 8) {
                    Text(verbatim: snapshot.provider.label).fontWeight(.bold).frame(width: 22, alignment: .leading)
                    UsageBar(percent: window?.usedPercent ?? 0, tint: .white, track: .white.opacity(0.3), height: 5)
                    Text(verbatim: formatter.percent(window)).monospacedDigit().frame(width: 30, alignment: .trailing)
                }.font(.system(size: 12)).opacity(entry.isStale(snapshot) ? staleOpacity : 1)
            }
            // No room for a reset per service beside the bars, so this widget leaves resets to the others.
            if let date = entry.staleSince { Text(verbatim: formatter.dataAge(date, now: entry.date)).font(.system(size: 11, weight: .semibold)) }
        }.foregroundStyle(.white).accessibilityElement(children: .ignore).accessibilityLabel(spokenSummary(entry, locale: locale))
    }
}
