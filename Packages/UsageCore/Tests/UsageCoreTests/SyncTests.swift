import CloudKit
import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_793_389_200)
private func snapshot(_ provider: Provider = .claude, five: Double = 42, reset: Date? = nil) -> UsageSnapshot {
    UsageSnapshot(provider: provider, plan: "Max 5x", windows: [.init(kind: .fiveHour, usedPercent: five, resetsAt: reset), .init(kind: .weekly, usedPercent: 68, resetsAt: now.addingTimeInterval(86400))], status: .ok, fetchedAt: now)
}

@Test(arguments: Provider.allCases)
func snapshotRecordRoundTrip(_ provider: Provider) throws {
    let value = snapshot(provider)
    let record = try CloudRecords.record(for: value)
    #expect(record.recordType == "UsageSnapshot")
    #expect(record.recordID.recordName == provider.rawValue)
    #expect(record.recordID.zoneID.zoneName == "Usage")
    #expect(CloudRecords.snapshot(from: record) == value)
    #expect(CloudRecords.fetchedAt(of: record) == now)
}
@Test func recordCarriesOnlySnapshotFields() throws {
    // No credentials can leak through sync: the record has the snapshot JSON and its timestamp, nothing else.
    #expect(Set(try CloudRecords.record(for: snapshot()).allKeys()) == ["json", "fetchedAt"])
    #expect(Set(CloudRecords.record(for: .claude).allKeys()) == ["services"])
}
@Test func recordUpdateKeepsIdentity() throws {
    let first = try CloudRecords.record(for: snapshot(five: 10))
    let updated = try CloudRecords.record(for: snapshot(five: 20), existing: first)
    #expect(updated === first)
    #expect(CloudRecords.snapshot(from: updated)?.window(.fiveHour)?.usedPercent == 20)
}
@Test func issueSitsBesideTheLastGoodSnapshot() throws {
    let good = try CloudRecords.record(for: snapshot())
    let failed = try CloudRecords.record(issue: .expired, provider: .claude, existing: good)
    #expect(failed.recordID == CloudRecords.snapshotID(.claude))
    #expect(CloudRecords.issue(from: failed) == .expired)
    #expect(CloudRecords.snapshot(from: failed) == snapshot())
    #expect(CloudRecords.issue(from: try CloudRecords.record(for: snapshot(five: 50), existing: failed)) == nil)
    // A service that never succeeded still reports why; it simply has no snapshot.
    let first = try CloudRecords.record(issue: .failed(.codexNotFound), provider: .codex)
    #expect(CloudRecords.snapshot(from: first) == nil)
    #expect(CloudRecords.issue(from: first) == .failed(.codexNotFound))
}
@Test func corruptSnapshotRecord() throws {
    let record = CKRecord(recordType: "UsageSnapshot", recordID: CloudRecords.snapshotID(.claude))
    #expect(CloudRecords.snapshot(from: record) == nil)
    record["json"] = Data("not json".utf8)
    #expect(CloudRecords.snapshot(from: record) == nil)
    #expect(CloudRecords.snapshot(from: CKRecord(recordType: "Other")) == nil)
}
@Test(arguments: [DisplayServices.both, .claude, .codex])
func servicesRecordRoundTrip(_ services: DisplayServices) {
    let record = CloudRecords.record(for: services)
    #expect(record.recordID.recordName == "display")
    #expect(CloudRecords.services(from: record) == services)
}
@Test func unknownServicesRecord() {
    let record = CKRecord(recordType: "DisplaySettings", recordID: CloudRecords.displayID)
    #expect(CloudRecords.services(from: record) == nil)
    record["services"] = "future"
    #expect(CloudRecords.services(from: record) == nil)
}
@Test func writeOnlyWhenNewer() {
    #expect(CloudRecords.shouldWrite(local: now, remote: nil))
    #expect(CloudRecords.shouldWrite(local: now, remote: now.addingTimeInterval(-1)))
    #expect(!CloudRecords.shouldWrite(local: now, remote: now))
    #expect(!CloudRecords.shouldWrite(local: now, remote: now.addingTimeInterval(1)))
}
@Test func displayServicesProviders() {
    #expect(DisplayServices.both.providers == [.claude, .codex])
    #expect(DisplayServices.claude.providers == [.claude])
    #expect(DisplayServices.codex.providers == [.codex])
}

@Test func sharedStoreRoundTrip() throws {
    let suite = "nokori-test-\(UUID().uuidString)"
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let store = SharedStore(suiteName: suite)
    #expect(store.load() == nil)
    let content = SharedStore.Content(snapshots: [snapshot(.codex), snapshot(.claude)], services: .codex, syncedAt: now)
    try store.save(content)
    #expect(store.load() == content)
    #expect(store.load()?.visible.map(\.provider) == [.codex])
    try store.save(.init(snapshots: [snapshot(.codex), snapshot(.claude)], services: .both, syncedAt: now))
    #expect(store.load()?.visible.map(\.provider) == [.claude, .codex])
    let withIssue = SharedStore.Content(snapshots: [snapshot(.claude)], issues: [.claude: .expired], services: .both, syncedAt: now)
    try store.save(withIssue)
    #expect(store.load() == withIssue)
}
@Test func issueShowsOnlyBehindOldOrMissingData() {
    let fresh = SharedStore.Content(snapshots: [snapshot(.claude), snapshot(.codex)], issues: [.claude: .failed(.network)], services: .both, syncedAt: now)
    #expect(fresh.issue(now: now.addingTimeInterval(60)) == nil)
    #expect(fresh.issue(now: now.addingTimeInterval(46 * 60))?.provider == .claude)
    #expect(fresh.issue(now: now.addingTimeInterval(46 * 60))?.status == .failed(.network))
    let missing = SharedStore.Content(snapshots: [snapshot(.claude)], issues: [.codex: .failed(.codexNotFound)], services: .both, syncedAt: now)
    #expect(missing.issue(now: now)?.provider == .codex)
    // A hidden service's trouble is not the person's concern.
    let hidden = SharedStore.Content(snapshots: [], issues: [.codex: .notLoggedIn], services: .claude, syncedAt: now)
    #expect(hidden.issue(now: now) == nil)
}
@Test func macIssueWording() {
    let english = UsageFormatter(locale: Locale(identifier: "en")).macIssue(.expired, provider: .claude)
    #expect(english.title == "Claude Code: Login has expired")
    #expect(english.detail == "On your Mac: Run claude in Terminal to renew your login")
    #expect(UsageFormatter(locale: Locale(identifier: "en")).macIssue(.failed(.network), provider: .codex).detail == "On your Mac")
    let japanese = UsageFormatter(locale: Locale(identifier: "ja")).macIssue(.expired, provider: .claude)
    #expect(japanese.title == "Claude Code：ログインの期限が切れています")
    #expect(japanese.detail == "Mac で：ターミナルで claude を起動してログインを更新してください")
}

@Test func englishWidgetFormatting() {
    let formatter = UsageFormatter(locale: Locale(identifier: "en_US"), timeZone: TimeZone(secondsFromGMT: 0)!)
    let reset = Date(timeIntervalSince1970: 1_793_389_200 + 3600)
    #expect(formatter.dataAge(now, now: now.addingTimeInterval(30)) == "Data from just now")
    #expect(formatter.dataAge(now, now: now.addingTimeInterval(52 * 60)) == "Data from 52m ago")
    #expect(formatter.weeklyShort(snapshot()) == "wk 68")
    #expect(formatter.timeLeft(snapshot(reset: reset).window(.fiveHour), now: reset.addingTimeInterval(-8040)) == "2h 14m")
    #expect(formatter.timeLeft(snapshot(five: 0, reset: reset).window(.fiveHour), now: now) == "Not used yet")
    #expect(formatter.timeLeft(nil, now: now).isEmpty)
    #expect(formatter.resetsIn(snapshot(reset: reset).window(.fiveHour), now: reset.addingTimeInterval(-840)) == "Resets in 14m")
    #expect(formatter.resetsIn(snapshot(reset: reset).window(.fiveHour), now: reset.addingTimeInterval(60)) == "Resets in 0m")
    #expect(formatter.resetsIn(snapshot(five: 0, reset: reset).window(.fiveHour), now: now) == "Not used yet")
    #expect(formatter.resetsIn(UsageWindow(kind: .weekly, usedPercent: 0, resetsAt: reset), now: reset.addingTimeInterval(-(4 * 86400 + 22 * 3600 + 59))) == "Resets in 4d 22h")
    #expect(formatter.resetsIn(nil, now: now).isEmpty)
}
@Test func japaneseWidgetFormatting() {
    let formatter = UsageFormatter(locale: Locale(identifier: "ja_JP"), timeZone: TimeZone(secondsFromGMT: 9 * 3600)!)
    let reset = Date(timeIntervalSince1970: 1_793_389_200 + 3600)
    #expect(formatter.dataAge(now, now: now.addingTimeInterval(52 * 60)) == "52分前のデータ")
    #expect(formatter.dataAge(now, now: now) == "たった今のデータ")
    #expect(formatter.weeklyShort(snapshot()) == "週68")
    #expect(formatter.timeLeft(snapshot(reset: reset).window(.fiveHour), now: reset.addingTimeInterval(-8040)) == "2時間14分")
    #expect(formatter.resetsIn(snapshot(reset: reset).window(.fiveHour), now: reset.addingTimeInterval(-840)) == "リセットまで 14分")
    #expect(formatter.resetsIn(UsageWindow(kind: .weekly, usedPercent: 30, resetsAt: reset), now: reset.addingTimeInterval(-4 * 86400)) == "リセットまで 4日0時間")
}
@Test func syncFailureFollowsWhatThePersonCanDo() {
    #expect(SyncFailure(CKError(.notAuthenticated)) == .noAccount)
    #expect(SyncFailure(CKError(.networkUnavailable)) == .offline)
    #expect(SyncFailure(CKError(.networkFailure)) == .offline)
    #expect(SyncFailure(CKError(.requestRateLimited)) == .busy)
    #expect(SyncFailure(CKError(.zoneBusy)) == .busy)
    #expect(SyncFailure(CKError(.quotaExceeded)) == .other(code: CKError.Code.quotaExceeded.rawValue))
    #expect(SyncFailure(URLError(.timedOut)) == .other(code: URLError.Code.timedOut.rawValue))
    let english = UsageFormatter(locale: Locale(identifier: "en_US"))
    #expect(english.sync(.other(code: 25)) == ("Couldn't read from iCloud", "Error code 25"))
    let japanese = UsageFormatter(locale: Locale(identifier: "ja_JP"))
    #expect(japanese.sync(.offline).title == "インターネットにつながっていません")
    #expect(japanese.noNewData.title == "Macから新しいデータが届いていません")
}
