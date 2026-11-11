import SwiftUI
import UsageCore

public struct UsageBar: View {
    public let percent: Double
    public let tint: Color
    public let track: Color
    public let height: CGFloat
    public var marker: Double?
    @Environment(\.colorScheme) private var scheme
    public init(percent: Double, tint: Color, track: Color, height: CGFloat = 6, marker: Double? = nil) {
        self.percent = percent; self.tint = tint; self.track = track; self.height = height; self.marker = marker
    }
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: height)
                Capsule().fill(tint).frame(width: geometry.size.width * min(1, max(0, percent / 100)), height: height)
                if let marker {
                    RoundedRectangle(cornerRadius: 1).fill(Theme(scheme).marker)
                        .frame(width: 2, height: height + 6).offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * marker)))
                }
            }.frame(height: height)
        }.frame(height: height).accessibilityHidden(true)
    }
}
/// Two concentric rings (outer = 5-hour, inner = weekly), drawn in a 64-unit space and scaled to the frame.
public struct UsageRings: View {
    public let fiveHour: Double
    public let weekly: Double
    public let tint: Color
    public var track: Color?
    public var lineWidth: CGFloat
    public var innerRadius: CGFloat
    public var innerOpacity: Double
    @Environment(\.colorScheme) private var scheme
    public init(fiveHour: Double, weekly: Double, tint: Color, track: Color? = nil, lineWidth: CGFloat = 6, innerRadius: CGFloat = 17, innerOpacity: Double = 0.55) {
        self.fiveHour = fiveHour; self.weekly = weekly; self.tint = tint; self.track = track
        self.lineWidth = lineWidth; self.innerRadius = innerRadius; self.innerOpacity = innerOpacity
    }
    public var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width, geometry.size.height) / 64
            ZStack {
                ring(fiveHour, radius: 26 * unit, opacity: 1, unit: unit)
                ring(weekly, radius: innerRadius * unit, opacity: innerOpacity, unit: unit)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
    private func ring(_ percent: Double, radius: CGFloat, opacity: Double, unit: CGFloat) -> some View {
        ZStack {
            Circle().stroke(track ?? Theme(scheme).track, lineWidth: lineWidth * unit)
            Circle().trim(from: 0, to: min(1, max(0, percent / 100)))
                .stroke(tint.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth * unit, lineCap: .round)).rotationEffect(.degrees(-90))
        }.frame(width: radius * 2, height: radius * 2)
    }
}
public struct ServiceSection: View {
    /// `popover` is the Mac popup; `phone` is the larger iPhone card, which keeps numbers on stale data.
    public enum Layout { case popover, phone }
    private struct Metrics {
        let name, chip, label, note, bar, section, row, staleOpacity: CGFloat
        static let popover = Metrics(name: 13, chip: 11, label: 12, note: 11, bar: 6, section: 10, row: 5, staleOpacity: 0.4)
        static let phone = Metrics(name: 15, chip: 12, label: 14, note: 12, bar: 8, section: 12, row: 6, staleOpacity: 0.45)
    }
    public let snapshot: UsageSnapshot
    public let now: Date
    public let layout: Layout
    public let retry: () -> Void
    public let claudeApp: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    public init(snapshot: UsageSnapshot, now: Date, layout: Layout = .popover, claudeApp: Bool = false, retry: @escaping () -> Void = {}) {
        self.snapshot = snapshot; self.now = now; self.layout = layout; self.claudeApp = claudeApp; self.retry = retry
    }
    private var metrics: Metrics { layout == .phone ? .phone : .popover }
    private var theme: Theme { Theme(scheme) }
    private var formatter: UsageFormatter { UsageFormatter(locale: locale) }
    private var available: Bool { snapshot.status == .ok && (layout == .phone || snapshot.isDisplayable(now: now)) }
    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.section) {
            HStack(spacing: 8) {
                Circle().fill(theme.provider(snapshot.provider)).frame(width: 8, height: 8)
                Text(verbatim: snapshot.provider.name).font(.system(size: metrics.name, weight: .semibold))
                Spacer()
                // The Mac fetches each service on its own schedule, so on the iPhone each card says how old its numbers are.
                if layout == .phone && snapshot.fetchedAt != .distantPast {
                    Text(verbatim: formatter.fetched(snapshot.fetchedAt, now: now)).font(.system(size: metrics.note)).foregroundStyle(theme.sub)
                }
                if let plan = snapshot.plan { Text(verbatim: plan).font(.system(size: metrics.chip)).foregroundStyle(theme.sub).padding(.horizontal, 6).padding(.vertical, 2).background(theme.chip, in: RoundedRectangle(cornerRadius: 4)) }
            }
            VStack(spacing: available ? metrics.section : 8) {
                row(.fiveHour, label: formatter.windowName(.fiveHour), window: snapshot.window(.fiveHour))
                row(.weekly, label: formatter.windowName(.weekly), window: snapshot.window(.weekly))
                // A model-only limit is a side allowance, so it gets no even-pace line of its own.
                ForEach(snapshot.modelWindows, id: \.model) { window in
                    row(.weekly, label: formatter.modelWindowName(window.model ?? ""), window: window, showsPace: false)
                }
            }.opacity(snapshot.isDisplayable(now: now) ? 1 : metrics.staleOpacity)
            if snapshot.status != .ok {
                let failure = formatter.failure(snapshot.status, provider: snapshot.provider, claudeApp: claudeApp)
                HStack(spacing: 10) {
                    Image(systemName: snapshot.status.needsKeychainAccess ? "lock" : "exclamationmark.circle").font(.system(size: 16)).foregroundStyle(theme.sub)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.title).font(.system(size: 12, weight: .semibold))
                        if !failure.detail.isEmpty { Text(failure.detail).font(.system(size: 11)).foregroundStyle(theme.sub).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer(minLength: 0)
                    Button(action: retry) {
                        Text(snapshot.status.needsKeychainAccess ? String(localized: "Allow", bundle: .module) : String(localized: "Retry", bundle: .module))
                    }.buttonStyle(ChipButtonStyle())
                }.padding(10).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.divider, lineWidth: 1))
            }
        }.foregroundStyle(theme.text)
    }
    private func row(_ kind: WindowKind, label: String, window: UsageWindow?, showsPace: Bool = true) -> some View {
        let window = available ? window : nil
        let pace = kind == .weekly && showsPace ? window.flatMap { UsagePolicy.pace(usedPercent: $0.usedPercent, resetsAt: $0.resetsAt, now: now) } : nil
        return VStack(alignment: .leading, spacing: available ? metrics.row : 8) {
            HStack {
                Text(label)
                Spacer()
                Text(formatter.used(window)).fontWeight(.semibold).monospacedDigit()
            }.font(.system(size: metrics.label))
            UsageBar(percent: window?.usedPercent ?? 0, tint: theme.provider(snapshot.provider), track: theme.track, height: metrics.bar, marker: pace?.elapsed)
            if let window {
                // Even pace gets its own line: appended, it broke mid-phrase in the narrow popup.
                VStack(alignment: .leading, spacing: 1) {
                    Text(formatter.detail(window, now: now))
                    if let pace { Text(formatter.pace(pace.difference)) }
                }.font(.system(size: metrics.note)).foregroundStyle(theme.sub).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
public struct ChipButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12)).foregroundStyle(Theme(scheme).text)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme(scheme).chip.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 6))
    }
}
