import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_793_389_200)
private func data(_ string: String) -> Data { Data(string.utf8) }
private func fixture(_ name: String) throws -> Data { try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))) }
private func snapshot(_ provider: Provider = .claude, percent: Double = 50, reset: Date? = nil, status: FetchStatus = .ok) -> UsageSnapshot {
    UsageSnapshot(provider: provider, plan: "Pro", windows: [.init(kind: .weekly, usedPercent: percent, resetsAt: reset)], status: status, fetchedAt: now)
}

@Test func modelRoundTrip() throws {
    let value = snapshot()
    #expect(try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(value)) == value)
    #expect(value.window(.weekly)?.usedPercent == 50)
    #expect(value.window(.fiveHour) == nil)
}
@Test(arguments: [FetchStatus.ok, .notLoggedIn, .expired, .needsKeychainPermission, .keychainChanged, .failed(.network), .failed(.timeout), .failed(.rateLimited), .failed(.codexNotFound), .failed(.launchFailed), .failed(.unexpected)])
func statusRoundTrip(_ status: FetchStatus) throws {
    #expect(try JSONDecoder().decode(FetchStatus.self, from: JSONEncoder().encode(status)) == status)
}
@Test(arguments: [("2026-11-03T09:00:00+09:00", 68.0, 54.0, 14.0), ("2026-11-05T09:00:00+09:00", 22.0, 26.0, -4.0)])
func mockPace(_ reset: String, _ used: Double, _ elapsed: Double, _ difference: Double) throws {
    let iso = ISO8601DateFormatter()
    let date = try #require(iso.date(from: "2026-10-31T04:20:00+09:00"))
    let pace = try #require(UsagePolicy.pace(usedPercent: used, resetsAt: iso.date(from: reset), now: date))
    #expect((pace.elapsed * 100).rounded() == elapsed)
    #expect(pace.difference.rounded() == difference)
}
@Test func paceBoundaries() {
    #expect(UsagePolicy.pace(usedPercent: 20, resetsAt: nil, now: now) == nil)
    #expect(UsagePolicy.pace(usedPercent: 20, resetsAt: now.addingTimeInterval(8 * 86400), now: now)!.elapsed < 0)
    #expect(UsagePolicy.pace(usedPercent: 20, resetsAt: now.addingTimeInterval(-1), now: now)!.elapsed > 1)
}
@Test func riskiestUsage() {
    let result = UsagePolicy.riskiest([snapshot(percent: 42), snapshot(.codex, percent: 68)])
    #expect(result?.provider == .codex)
    #expect(UsagePolicy.riskiest([snapshot(percent: 100, status: .failed(.network)), snapshot(.codex, percent: 18)])?.provider == .codex)
    #expect(UsagePolicy.riskiest([snapshot(status: .expired)]) == nil)
    #expect(UsagePolicy.riskiest([]) == nil)
}
@Test func riskiestTie() {
    #expect(UsagePolicy.riskiest([snapshot(reset: now), snapshot(.codex, reset: now.addingTimeInterval(1))])?.provider == .codex)
    #expect(UsagePolicy.riskiest([snapshot(reset: now), snapshot(.codex, reset: nil)])?.provider == .codex)
    #expect(UsagePolicy.riskiest([snapshot(reset: nil), snapshot(.codex, reset: now)])?.provider == .claude)
}
@Test func staleBoundary() {
    #expect(!UsagePolicy.isStale(fetchedAt: now, now: now.addingTimeInterval(2700)))
    #expect(UsagePolicy.isStale(fetchedAt: now, now: now.addingTimeInterval(2700.1)))
    #expect(!snapshot().isDisplayable(now: now.addingTimeInterval(2701)))
}
@Test func fetchesFollowUse() {
    #expect(UsagePolicy.nextFetch(after: now, interval: 300, lastActivity: nil) == now.addingTimeInterval(1800))
    #expect(UsagePolicy.nextFetch(after: now, interval: 300, lastActivity: now.addingTimeInterval(-1)) == now.addingTimeInterval(1800))
    #expect(UsagePolicy.nextFetch(after: now, interval: 300, lastActivity: now.addingTimeInterval(60)) == now.addingTimeInterval(300))
    // A longer setting than the idle cadence is kept either way.
    #expect(UsagePolicy.nextFetch(after: now, interval: 3600, lastActivity: nil) == now.addingTimeInterval(3600))
}
@Test func claudeRenewalCooldown() {
    #expect(ClaudeRenewal.shouldTry(lastAttempt: nil, now: now))
    #expect(!ClaudeRenewal.shouldTry(lastAttempt: now, now: now.addingTimeInterval(1799)))
    #expect(ClaudeRenewal.shouldTry(lastAttempt: now, now: now.addingTimeInterval(1800)))
}
/// As Claude Code 2.1 draws it: every word placed with a cursor move, so the escape letters must not join the words.
@Test func claudeTrustQuestion() {
    let question = "\u{1B}[2G\u{1B}[38;5;220m❯\u{1B}[39m No,\u{1B}[8Gexit\r\n\u{1B}[4GYes,\u{1B}[9GI\u{1B}[11Gtrust\u{1B}[17Gthis\u{1B}[22Gfolder\u{1B}[0m"
    #expect(ClaudeRenewal.asksForTrust(question))
    #expect(!ClaudeRenewal.asksForTrust("\u{1B}[2G> Try \"fix the trust check in this folder\""))
}
@Test(arguments: ["2025-12-25T12:00:00.000Z", "2026-07-03T00:30:00.282668+00:00", "2026-07-03T00:30:00Z"])
func claudeDates(_ date: String) throws {
    let value = try ClaudeUsageParser.parse(data: data("{\"five_hour\":{\"utilization\":42,\"resets_at\":\"\(date)\"},\"seven_day\":{\"utilization\":68,\"resets_at\":null}}"), subscriptionType: "max", rateLimitTier: "default_claude_max_5x", fetchedAt: now)
    #expect(value.plan == "Max 5x")
    #expect(value.window(.fiveHour)?.resetsAt != nil)
    #expect(value.window(.weekly)?.usedPercent == 68)
}
@Test(arguments: ["{\"five_hour\":null,\"seven_day\":{\"utilization\":20}}", "{\"seven_day\":{\"utilization\":20}}", "{\"five_hour\":null,\"seven_day\":null}"])
func claudeUnused(_ json: String) throws {
    let value = try ClaudeUsageParser.parse(data: data(json), subscriptionType: nil, rateLimitTier: nil, fetchedAt: now)
    #expect(value.window(.fiveHour) == UsageWindow(kind: .fiveHour, usedPercent: 0, resetsAt: nil))
    #expect(value.plan == nil)
}
@Test(arguments: [("max", "default_claude_max_5x", "Max 5x"), ("max", "default_claude_max_20x", "Max 20x"), ("max", "", "Max"), ("pro", "", "Pro"), ("team", "", "Team"), ("enterprise", "", "Enterprise"), ("future", "", "Future")])
func claudePlans(_ type: String, _ tier: String, _ expected: String) {
    #expect(ClaudeUsageParser.plan(subscriptionType: type, rateLimitTier: tier) == expected)
}
@Test func claudeTierFallback() {
    #expect(ClaudeUsageParser.plan(subscriptionType: nil, rateLimitTier: "default_claude_max_20x") == "Max 20x")
    #expect(ClaudeUsageParser.plan(subscriptionType: nil, rateLimitTier: nil) == nil)
}
@Test func credentials() throws {
    // Synthetic, deliberately unusable credential; never sourced from a local account.
    let value = try #require(ClaudeCredentials.parse(data: data("{\"claudeAiOauth\":{\"accessToken\":\"test-only-not-a-token\",\"expiresAt\":100000,\"scopes\":[\"user:profile\"],\"subscriptionType\":\"max\",\"rateLimitTier\":\"default_claude_max_5x\"}}")))
    #expect(value.hasProfileScope)
    #expect(value.expiresAt == Date(timeIntervalSince1970: 100))
    #expect(!value.isExpired(now: Date(timeIntervalSince1970: 99)))
    #expect(value.isExpired(now: Date(timeIntervalSince1970: 100)))
    #expect(value.subscriptionType == "max")
    #expect(value.rateLimitTier == "default_claude_max_5x")
}
@Test(arguments: ["{}", "{\"mcpOAuth\":{}}", "{\"claudeAiOauth\":{}}", "invalid"])
func invalidCredentials(_ json: String) { #expect(ClaudeCredentials.parse(data: data(json)) == nil) }
@Test func missingScope() throws {
    let value = try #require(ClaudeCredentials.parse(data: data("{\"claudeAiOauth\":{\"accessToken\":\"test-only\",\"expiresAt\":100000}}")))
    #expect(!value.hasProfileScope)
}
@Test func codexFixtures() throws {
    let value = try CodexUsageParser.parse(accountRead: fixture("codex-account-read"), rateLimitsRead: fixture("codex-rate-limits-read"), fetchedAt: now)
    #expect(value.status == .ok)
    #expect(value.plan == "Plus")
    #expect(value.window(.fiveHour)?.usedPercent == 0)
    #expect(value.window(.weekly)?.usedPercent == 33)
    #expect(value.window(.weekly)?.resetsAt == Date(timeIntervalSince1970: 1793935904))
    #expect(value.fetchedAt == now)
}
@Test(arguments: ["null", "{\"type\":\"apiKey\"}"])
func codexNotLoggedIn(_ account: String) throws {
    let value = try CodexUsageParser.parse(accountRead: data("{\"id\":2,\"result\":{\"account\":\(account)}}"), rateLimitsRead: fixture("codex-rate-limits-read"), fetchedAt: now)
    #expect(value.status == .notLoggedIn)
    #expect(value.windows.isEmpty)
}
@Test func codexWindowDurations() throws {
    let value = try CodexUsageParser.parse(accountRead: nil, rateLimitsRead: data("{\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":33,\"windowDurationMins\":10080,\"resetsAt\":100},\"secondary\":{\"usedPercent\":10,\"windowDurationMins\":43200}}}}"), fetchedAt: now)
    #expect(value.windows.count == 1)
    #expect(value.window(.weekly)?.usedPercent == 33)
    #expect(value.window(.fiveHour) == nil)
}
@Test func codexPlanFallbackAndPrecedence() throws {
    let account = data("{\"result\":{\"account\":{\"type\":\"chatgpt\",\"planType\":\"prolite\"}}}")
    #expect(try CodexUsageParser.parse(accountRead: account, rateLimitsRead: data("{\"result\":{\"rateLimits\":{}}}"), fetchedAt: now).plan == "Pro Lite")
    #expect(try CodexUsageParser.parse(accountRead: account, rateLimitsRead: fixture("codex-rate-limits-read"), fetchedAt: now).plan == "Plus")
}
@Test(arguments: [("plus", "Plus"), ("pro", "Pro"), ("prolite", "Pro Lite"), ("free", "Free"), ("go", "Go"), ("team", "Team"), ("business", "Business"), ("enterprise", "Enterprise"), ("edu", "Edu"), ("future", "Future")])
func codexPlans(_ value: String, _ expected: String) { #expect(CodexUsageParser.plan(value) == expected) }
@Test func overLimitIsCapped() throws {
    let claude = try ClaudeUsageParser.parse(data: data("{\"five_hour\":{\"utilization\":104.5},\"seven_day\":{\"utilization\":-1}}"), subscriptionType: nil, rateLimitTier: nil, fetchedAt: now)
    #expect(claude.window(.fiveHour)?.usedPercent == 100)
    #expect(claude.window(.weekly)?.usedPercent == 0)
    let codex = try CodexUsageParser.parse(accountRead: nil, rateLimitsRead: data("{\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":120,\"windowDurationMins\":300,\"resetsAt\":null}}}}"), fetchedAt: now)
    #expect(codex.window(.fiveHour)?.usedPercent == 100)
}
@Test(arguments: ["{}", "{\"five_hour\":{\"utilization\":42,\"resets_at\":\"bad-date\"}}"])
func malformedClaude(_ json: String) {
    #expect(throws: (any Error).self) { try ClaudeUsageParser.parse(data: data(json), subscriptionType: nil, rateLimitTier: nil, fetchedAt: now) }
}
@Test func rpcFraming() throws {
    #expect(try CodexRPC.responseID(data("{\"method\":\"notification\"}")) == nil)
    #expect(try CodexRPC.responseID(data("{\"id\":1,\"result\":{}}")) == 1)
    #expect(throws: FetchFailure.unexpected) { try CodexRPC.responseID(data("{\"id\":3,\"error\":{\"message\":\"synthetic\"}}")) }
}
@Test func retryPolicy() {
    #expect(UsagePolicy.retryDelay(interval: 300, failures: 0, retryAfter: nil) == 300)
    #expect(UsagePolicy.retryDelay(interval: 300, failures: 1, retryAfter: nil) == 600)
    #expect(UsagePolicy.retryDelay(interval: 300, failures: 20, retryAfter: nil) == 1800)
    #expect(UsagePolicy.retryDelay(interval: 300, failures: 20, retryAfter: 3600) == 3600)
    #expect(UsagePolicy.retryAfter("120", now: now) == 120)
    #expect(UsagePolicy.retryAfter("invalid", now: now) == nil)
    #expect(UsagePolicy.retryAfter("Thu, 01 Jan 1970 00:02:00 GMT", now: Date(timeIntervalSince1970: 0)) == 120)
}
@Test func englishFormatting() {
    let formatter = UsageFormatter(locale: Locale(identifier: "en_US"), timeZone: TimeZone(secondsFromGMT: 0)!)
    #expect(formatter.reset(.init(kind: .fiveHour, usedPercent: 0, resetsAt: now), now: now) == "Not used yet")
    #expect(formatter.reset(.init(kind: .weekly, usedPercent: 10, resetsAt: nil), now: now).isEmpty)
    let fiveHourReset = now.addingTimeInterval(8040)
    #expect(formatter.reset(.init(kind: .fiveHour, usedPercent: 42, resetsAt: fiveHourReset), now: now) == "Resets in 2h 14m (\(formatter.time(fiveHourReset)))")
    #expect(formatter.reset(.init(kind: .fiveHour, usedPercent: 42, resetsAt: now.addingTimeInterval(14 * 60)), now: now).hasPrefix("Resets in 14m ("))
    #expect(formatter.reset(.init(kind: .weekly, usedPercent: 10, resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)), now: now).hasPrefix("Resets in 3d 5h (Tue 12:40"))
    let weekly = UsageWindow(kind: .weekly, usedPercent: 42, resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600))
    #expect(formatter.used(weekly) == "42% used")
    #expect(formatter.used(nil) == "–")
    #expect(formatter.detail(weekly, now: now).hasPrefix("58% left ・ Resets in 3d 5h ("))
    #expect(formatter.detail(.init(kind: .fiveHour, usedPercent: 0, resetsAt: now), now: now) == "Not used yet")
    #expect(formatter.detail(.init(kind: .weekly, usedPercent: 120, resetsAt: nil), now: now) == "0% left")
    #expect(formatter.pace(0.49) == "On even pace")
    #expect(formatter.pace(-0.49) == "On even pace")
    #expect(formatter.pace(14) == "14% ahead of even pace")
    #expect(formatter.pace(-4) == "4% under even pace")
    #expect(formatter.updated(now, now: now) == "Updated just now")
    #expect(formatter.updated(now, now: now.addingTimeInterval(60)) == "Updated 1 min ago")
    #expect(formatter.accessibility(snapshot(), now: now) == "Claude Code 5-hour –, weekly 50%")
}
@Test(arguments: [FetchStatus.notLoggedIn, .expired, .needsKeychainPermission, .keychainChanged, .failed(.network), .failed(.timeout), .failed(.rateLimited), .failed(.codexNotFound), .failed(.launchFailed), .failed(.unexpected)])
func failureMessages(_ status: FetchStatus) {
    let formatter = UsageFormatter(locale: Locale(identifier: "en"))
    #expect(!formatter.failure(status, provider: .claude).title.isEmpty)
    #expect(!formatter.failure(status, provider: .codex).title.isEmpty)
}

@Test func japaneseFormatting() {
    let formatter = UsageFormatter(locale: Locale(identifier: "ja_JP"), timeZone: TimeZone(secondsFromGMT: 9 * 3600)!)
    #expect(formatter.reset(.init(kind: .fiveHour, usedPercent: 0, resetsAt: now), now: now) == "未使用")
    #expect(formatter.reset(.init(kind: .weekly, usedPercent: 10, resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)), now: now) == "リセットまで 3日5時間（火 9:40）")
    #expect(formatter.used(.init(kind: .weekly, usedPercent: 42, resetsAt: nil)) == "42% 使用済み")
    #expect(formatter.left(.init(kind: .weekly, usedPercent: 42, resetsAt: nil)) == "残り58%")
    #expect(formatter.pace(14) == "均等ペースより14%多め")
    #expect(formatter.pace(-4) == "均等ペースより4%余裕")
    #expect(formatter.updated(now, now: now) == "たった今更新")
    #expect(formatter.failure(.notLoggedIn, provider: .codex).detail == "ターミナルでCodexにログインしてください")
    #expect(formatter.failure(.needsKeychainPermission, provider: .claude).detail == "Claude Codeのログイン情報を読むには許可が要ります")
    #expect(formatter.failure(.keychainChanged, provider: .claude).detail == "Claude Codeの更新で許可が外れました")
    #expect(formatter.failure(.failed(.launchFailed), provider: .codex).title == "codexを起動できませんでした")
}

@Test func keychainStateTellsFirstTimeFromRenewal() {
    let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
    #expect(KeychainState.status(lastReadModification: nil, currentModification: new) == .needsKeychainPermission)
    #expect(KeychainState.status(lastReadModification: old, currentModification: new) == .keychainChanged)
    #expect(KeychainState.status(lastReadModification: new, currentModification: new) == .needsKeychainPermission)
    #expect(KeychainState.status(lastReadModification: new, currentModification: old) == .needsKeychainPermission)
    #expect(KeychainState.status(lastReadModification: old, currentModification: nil) == .needsKeychainPermission)
    #expect(FetchStatus.needsKeychainPermission.needsKeychainAccess && FetchStatus.keychainChanged.needsKeychainAccess)
    #expect(!FetchStatus.expired.needsKeychainAccess)
}
@Test func securityToolReadsOnlyWhenTrusted() {
    #expect(KeychainState.securityCanRead(decryptApplications: [["/Applications/Other.app", "/usr/bin/security"]]))
    #expect(KeychainState.securityCanRead(decryptApplications: [["/Applications/Other.app"], nil]))
    #expect(!KeychainState.securityCanRead(decryptApplications: [["/Applications/Other.app"]]))
    #expect(!KeychainState.securityCanRead(decryptApplications: [[]]))
    #expect(!KeychainState.securityCanRead(decryptApplications: []))
}
@Suite struct WeeklyResetGuardTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func week(_ percent: Double, resets: TimeInterval?) -> UsageWindow {
        .init(kind: .weekly, usedPercent: percent, resetsAt: resets.map { now.addingTimeInterval($0) })
    }
    @Test func firstFetchIsAdopted() {
        let fetched = week(10, resets: 86_400)
        let result = WeeklyResetGuard.apply(previous: nil, fetched: fetched, pending: nil, now: now)
        #expect(result.window == fetched && result.pending == nil)
    }
    @Test func normalWeekRolloverIsAdopted() {
        // The previous reset has passed, so a new reset time a week later is expected.
        let result = WeeklyResetGuard.apply(previous: week(90, resets: -3_600), fetched: week(2, resets: 7 * 86_400 - 3_600), pending: nil, now: now)
        #expect(result.window.usedPercent == 2 && result.pending == nil)
    }
    @Test func smallShiftIsAdopted() {
        let result = WeeklyResetGuard.apply(previous: week(40, resets: 86_400), fetched: week(41, resets: 86_400 + 3_599), pending: nil, now: now)
        #expect(result.window.usedPercent == 41 && result.pending == nil)
    }
    @Test func firstJumpKeepsPrevious() {
        let previous = week(40, resets: 86_400), fetched = week(1, resets: 8 * 86_400)
        let result = WeeklyResetGuard.apply(previous: previous, fetched: fetched, pending: nil, now: now)
        #expect(result.window == previous)
        #expect(result.pending == fetched.resetsAt)
    }
    @Test func sameJumpTwiceIsAdopted() {
        let fetched = week(1, resets: 8 * 86_400)
        let result = WeeklyResetGuard.apply(previous: week(40, resets: 86_400), fetched: fetched, pending: fetched.resetsAt, now: now)
        #expect(result.window == fetched && result.pending == nil)
    }
    @Test func differentJumpUpdatesPending() {
        let previous = week(40, resets: 86_400), fetched = week(1, resets: 9 * 86_400)
        let result = WeeklyResetGuard.apply(previous: previous, fetched: fetched, pending: now.addingTimeInterval(8 * 86_400), now: now)
        #expect(result.window == previous)
        #expect(result.pending == fetched.resetsAt)
    }
    @Test func backToNormalClearsPending() {
        let fetched = week(41, resets: 86_400)
        let result = WeeklyResetGuard.apply(previous: week(40, resets: 86_400), fetched: fetched, pending: now.addingTimeInterval(8 * 86_400), now: now)
        #expect(result.window == fetched && result.pending == nil)
    }
    @Test func missingResetIsAdopted() {
        let noReset = week(5, resets: nil)
        #expect(WeeklyResetGuard.apply(previous: week(40, resets: 86_400), fetched: noReset, pending: nil, now: now).window == noReset)
        let fetched = week(5, resets: 8 * 86_400)
        #expect(WeeklyResetGuard.apply(previous: noReset, fetched: fetched, pending: nil, now: now).window == fetched)
    }
    @Test func withinLastMinuteBeforeResetIsAdopted() {
        // The old week is about to end (under a minute), so a new reset time is the real rollover.
        let fetched = week(1, resets: 7 * 86_400)
        #expect(WeeklyResetGuard.apply(previous: week(99, resets: 30), fetched: fetched, pending: nil, now: now).window == fetched)
    }
}
@Suite struct ModelWindowTests {
    let base = "\"five_hour\":{\"utilization\":11,\"resets_at\":\"2026-07-03T00:30:00.282668+00:00\"},\"seven_day\":{\"utilization\":9,\"resets_at\":\"2026-07-08T09:00:00.282694+00:00\"}"
    func parse(_ limits: String) throws -> UsageSnapshot {
        try ClaudeUsageParser.parse(data: data("{\(base),\"limits\":\(limits)}"), subscriptionType: "max", rateLimitTier: nil, fetchedAt: now)
    }
    @Test func scopedWeeklyBecomesModelWindow() throws {
        let value = try parse("""
        [{"kind":"session","group":"session","percent":11,"resets_at":"2026-07-03T00:30:00.282668+00:00","scope":null},
         {"kind":"weekly_all","group":"weekly","percent":9,"resets_at":"2026-07-08T09:00:00.282694+00:00","scope":null},
         {"kind":"weekly_scoped","group":"weekly","percent":5,"resets_at":"2026-07-08T09:00:00.283070+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}}]
        """)
        #expect(value.window(.weekly)?.usedPercent == 9)
        #expect(value.modelWindows.count == 1)
        let fable = try #require(value.modelWindows.first)
        #expect(fable.model == "Fable")
        #expect(fable.usedPercent == 5)
        #expect(fable.resetsAt != nil)
    }
    @Test func oddEntriesAreSkippedWithoutFailingTheFetch() throws {
        let value = try parse("""
        [null, "x",
         {"kind":"weekly_scoped","group":"weekly","percent":"5","scope":{"model":{"display_name":"Text percent"}}},
         {"kind":"weekly_scoped","group":"weekly","percent":true,"scope":{"model":{"display_name":"Bool percent"}}},
         {"kind":"weekly_scoped","group":"weekly","percent":3,"scope":{"model":null}},
         {"kind":"weekly_scoped","group":"weekly","percent":3,"scope":{"model":{"display_name":"  "}}},
         {"kind":"weekly_scoped","group":"weekly","percent":3,"scope":{"model":{"display_name":"All models"}}},
         {"kind":"weekly_scoped","group":"weekly","percent":140,"resets_at":1791800000,"scope":{"model":{"display_name":"Fable"}}},
         {"kind":"weekly_scoped","group":"weekly","percent":20,"scope":{"model":{"display_name":"Fable"}}}]
        """)
        #expect(value.modelWindows == [UsageWindow(kind: .weekly, usedPercent: 100, resetsAt: nil, model: "Fable")])
    }
    @Test func noLimitsMeansNoModelWindows() throws {
        #expect(try ClaudeUsageParser.parse(data: data("{\(base)}"), subscriptionType: nil, rateLimitTier: nil, fetchedAt: now).modelWindows.isEmpty)
        #expect(try parse("{}").modelWindows.isEmpty)
    }
    @Test func olderSnapshotsWithoutModelStillDecode() throws {
        let json = "{\"provider\":\"claude\",\"windows\":[{\"kind\":\"weekly\",\"usedPercent\":40}],\"status\":{\"ok\":{}},\"fetchedAt\":0}"
        let value = try JSONDecoder().decode(UsageSnapshot.self, from: data(json))
        #expect(value.window(.weekly)?.model == nil)
        #expect(value.modelWindows.isEmpty)
    }
    @Test func modelWindowCountsForRiskiestOnly() {
        let value = UsageSnapshot(provider: .claude, windows: [.init(kind: .weekly, usedPercent: 30, resetsAt: nil), .init(kind: .weekly, usedPercent: 80, resetsAt: nil, model: "Fable")], status: .ok, fetchedAt: now)
        #expect(value.window(.weekly)?.usedPercent == 30)
        #expect(UsagePolicy.riskiest([value, snapshot(.codex, percent: 60)])?.window.model == "Fable")
        let formatter = UsageFormatter(locale: Locale(identifier: "en"))
        #expect(formatter.accessibility(value, now: now) == "Claude Code 5-hour –, weekly 30%, Fable only 80%")
        #expect(UsageFormatter(locale: Locale(identifier: "ja")).modelWindowName("Fable") == "Fable のみ")
    }
}
