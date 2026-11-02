import Foundation

public struct UsageFormatter: Sendable {
    public var locale: Locale
    public var timeZone: TimeZone
    public init(locale: Locale = .current, timeZone: TimeZone = .current) { self.locale = locale; self.timeZone = timeZone }
    private func text(_ key: String.LocalizationValue) -> String {
        // `locale` formats interpolations, but does not choose the bundle language.
        let language = locale.language.languageCode?.identifier ?? "en"
        let bundle = Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
        return String(localized: key, bundle: bundle, locale: locale)
    }
    public func windowName(_ kind: WindowKind) -> String { kind == .fiveHour ? text("5-hour") : text("Weekly") }
    public func modelWindowName(_ model: String) -> String { text("\(model) only") }
    public func shortWindowName(_ kind: WindowKind) -> String { kind == .fiveHour ? text("5h") : text("wk") }
    public func percent(_ window: UsageWindow?) -> String { window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "–" }
    /// The bars fill with what was used, so the popup and the app say so in words, as Claude's own settings do.
    public func used(_ window: UsageWindow?) -> String { window.map { text("\(Int($0.usedPercent.rounded()))% used") } ?? "–" }
    public func left(_ window: UsageWindow) -> String { text("\(max(0, 100 - Int(window.usedPercent.rounded())))% left") }
    /// The line under a bar: what is left and when it resets. An unused 5-hour window says only "Not used yet", since "100% left" adds nothing.
    public func detail(_ window: UsageWindow, now: Date) -> String {
        let unused = window.kind == .fiveHour && window.usedPercent == 0
        return ((unused ? [] : [left(window)]) + [reset(window, now: now)]).filter { !$0.isEmpty }.joined(separator: " ・ ")
    }
    public func time(_ date: Date) -> String {
        var style = Date.FormatStyle().hour().minute().locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
    /// A weekly reset is always within the coming week, so the weekday is enough to place it.
    private func weekdayTime(_ date: Date) -> String {
        var style = Date.FormatStyle().weekday(.abbreviated).hour().minute().locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
    /// "Resets in 2h 14m (6:34 PM)", or "Resets in 3d 5h (Wed 3:14 PM)" for a weekly window.
    public func reset(_ window: UsageWindow, now: Date) -> String {
        if window.kind == .fiveHour && window.usedPercent == 0 { return text("Not used yet") }
        guard let date = window.resetsAt else { return "" }
        let when = window.kind == .weekly ? weekdayTime(date) : time(date)
        return text("Resets in \(remaining(date, now: now)) (\(when))")
    }
    /// Time left until `date`: "2h 14m", "14m", or "4d 22h" from one day up. A past date counts as no time left.
    public func remaining(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 1440 { return text("\(minutes / 1440)d \(minutes % 1440 / 60)h") }
        if minutes >= 60 { return text("\(minutes / 60)h \(minutes % 60)m") }
        return text("\(minutes)m")
    }
    /// Widget: "Resets in 2h 14m", or "Not used yet" for an unused 5-hour window.
    public func resetsIn(_ window: UsageWindow?, now: Date) -> String {
        guard let window else { return "" }
        if window.kind == .fiveHour && window.usedPercent == 0 { return text("Not used yet") }
        return window.resetsAt.map { text("Resets in \(remaining($0, now: now))") } ?? ""
    }
    /// Widget columns, too narrow for "Resets in": just "2h 14m", or "Not used yet" for an unused 5-hour window.
    public func timeLeft(_ window: UsageWindow?, now: Date) -> String {
        guard let window else { return "" }
        if window.kind == .fiveHour && window.usedPercent == 0 { return text("Not used yet") }
        return window.resetsAt.map { remaining($0, now: now) } ?? ""
    }
    public func weeklyShort(_ snapshot: UsageSnapshot) -> String {
        text("wk \(Int((snapshot.window(.weekly)?.usedPercent ?? 0).rounded()))")
    }
    /// "Data from 12m ago" for data older than the sync can explain.
    public func dataAge(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return text("Data from just now") }
        let relative = RelativeDateTimeFormatter()
        relative.locale = locale
        relative.unitsStyle = .abbreviated
        return text("Data from \(relative.localizedString(for: date, relativeTo: now))")
    }
    public func pace(_ difference: Double) -> String {
        if abs(difference) < 0.5 { return text("On even pace") }
        let amount = Int(abs(difference).rounded())
        return difference > 0 ? text("\(amount)% ahead of even pace") : text("\(amount)% under even pace")
    }
    public func updated(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes == 0 { return text("Updated just now") }
        return text("Updated \(minutes) min ago")
    }
    /// `keepsValues` is for the iPhone, which shows stale numbers instead of "–".
    public func accessibility(_ snapshot: UsageSnapshot, now: Date, keepsValues: Bool = false) -> String {
        let shown = snapshot.status == .ok && (keepsValues || !UsagePolicy.isStale(fetchedAt: snapshot.fetchedAt, now: now))
        let five = shown ? percent(snapshot.window(.fiveHour)) : "–"
        let week = shown ? percent(snapshot.window(.weekly)) : "–"
        let models = shown ? snapshot.modelWindows.map { text(", \($0.model ?? "") only \(percent($0))") }.joined() : ""
        return text("\(snapshot.provider.name) 5-hour \(five), weekly \(week)") + models
    }
    /// The iPhone's notice when iCloud could not be read. The code is there to quote when asking for help.
    public func sync(_ failure: SyncFailure) -> (title: String, detail: String) {
        switch failure {
        case .noAccount: return (text("Not signed in to iCloud"), text("Sign in with the same Apple Account as your Mac"))
        case .offline: return (text("No internet connection"), text("Showing the last data received"))
        case .busy: return (text("iCloud is busy"), text("Try again in a moment"))
        case .other(let code): return (text("Couldn't read from iCloud"), text("Error code \(code)"))
        }
    }
    /// The iPhone read iCloud fine, but the Mac has not written for a while.
    public var noNewData: (title: String, detail: String) {
        (text("No new data from your Mac"), text("Check that Nokori AI is running on your Mac and the Mac is awake"))
    }
    /// On the iPhone: the Mac's own message for a service it could not fetch, marked as something to do on the Mac.
    public func macIssue(_ status: FetchStatus, provider: Provider) -> (title: String, detail: String) {
        let message = failure(status, provider: provider)
        return (text("\(provider.name): \(message.title)"), message.detail.isEmpty ? text("On your Mac") : text("On your Mac: \(message.detail)"))
    }
    public func failure(_ status: FetchStatus, provider: Provider) -> (title: String, detail: String) {
        switch status {
        case .ok: return ("", "")
        case .notLoggedIn:
            return (text("Not logged in"), provider == .claude ? text("Log in to Claude Code in Terminal") : text("Log in to Codex in Terminal"))
        case .expired: return (text("Login has expired"), text("Launch Claude Code once"))
        case .needsKeychainPermission: return (text("Keychain access needed"), text("Allow Nokori AI to read Claude Code's sign-in"))
        case .keychainChanged: return (text("Keychain access needed"), text("Claude Code renewed its sign-in, so access was reset"))
        case .failed(.network): return (text("Connection error"), "")
        case .failed(.timeout): return (text("Connection error"), text("No response from codex for 15 seconds"))
        case .failed(.rateLimited): return (text("Service is busy"), text("Will retry automatically in a moment"))
        case .failed(.codexNotFound): return (text("codex not found"), text("Set the codex location in Settings"))
        case .failed(.launchFailed): return (text("Couldn't start codex"), text("macOS may have blocked it. Press refresh to try again"))
        case .failed(.unexpected): return (text("Could not read the response"), "")
        }
    }
}
