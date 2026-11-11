import Foundation
import Testing
import SQLite3
import CommonCrypto
import CryptoKit
import UsageCore

private struct CookieDatabase {
    let directory: URL
    init(encrypted: Data? = nil, value: String = "test-only-session", expires: Int64 = 0, host: String = ".claude.ai") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("nokori-cookie-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var db: OpaquePointer?
        try #require(sqlite3_open(directory.appendingPathComponent("Cookies").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, "CREATE TABLE meta (key TEXT, value TEXT); INSERT INTO meta VALUES ('version', '24'); CREATE TABLE cookies (host_key TEXT, name TEXT, path TEXT, value TEXT, encrypted_value BLOB, expires_utc INTEGER);", nil, nil, nil) == SQLITE_OK)
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "INSERT INTO cookies VALUES (?, 'sessionKey', '/', ?, ?, ?)", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, host, -1, transient)
        sqlite3_bind_text(statement, 2, encrypted == nil ? value : "", -1, transient)
        if let encrypted { _ = encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), transient) } }
        sqlite3_bind_int64(statement, 4, expires)
        try #require(sqlite3_step(statement) == SQLITE_DONE)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func encryptedCookie(host: String = ".claude.ai", value: String = "test-only-encrypted-session", version: Int32 = 24) throws -> Data {
    let key = try ClaudeDesktopCookies.deriveKey(Data("test-only-password".utf8))
    let plaintext = (version >= 24 ? Data(SHA256.hash(data: Data(host.utf8))) : Data()) + Data(value.utf8)
    let iv = Data(repeating: 32, count: 16)
    var output = Data(count: plaintext.count + 16), count = 0
    let status = output.withUnsafeMutableBytes { output in
        key.withUnsafeBytes { key in iv.withUnsafeBytes { iv in plaintext.withUnsafeBytes { input in
            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                key.baseAddress, key.count, iv.baseAddress, input.baseAddress, input.count, output.baseAddress, output.count, &count)
        } } }
    }
    try #require(status == kCCSuccess)
    return Data("v10".utf8) + output.prefix(count)
}

@Test func desktopCookiesReadOnlyAndHostBound() throws {
    let encrypted = try encryptedCookie()
    let derived = try ClaudeDesktopCookies.deriveKey(Data("test-only-password".utf8))
    #expect(derived.map { String(format: "%02x", $0) }.joined() == "ef9aa3faedcf6ad634ad56cd8a1629d4")
    let fixture = try CookieDatabase(encrypted: encrypted)
    defer { fixture.remove() }
    let before = try Data(contentsOf: fixture.directory.appendingPathComponent("Cookies"))
    let session = try ClaudeDesktopCookies.read(allowsUI: false, directory: fixture.directory) { allowsUI in
        #expect(!allowsUI)
        return Data("test-only-password".utf8)
    }
    #expect(session.key == "test-only-encrypted-session")
    #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("Cookies")) == before)
    let key = try ClaudeDesktopCookies.deriveKey(Data("test-only-password".utf8))
    #expect(throws: (any Error).self) { try ClaudeDesktopCookies.decrypt(encrypted, key: key, host: "other.example", version: 24) }
    let wrongKey = try ClaudeDesktopCookies.deriveKey(Data("wrong-test-only-password".utf8))
    #expect(throws: (any Error).self) { try ClaudeDesktopCookies.decrypt(encrypted, key: wrongKey, host: ".claude.ai", version: 24) }
    #expect(throws: (any Error).self) { try ClaudeDesktopCookies.decrypt(Data("v20unsupported".utf8), key: key, host: ".claude.ai", version: 24) }
    let legacy = try encryptedCookie(version: 23)
    #expect(try ClaudeDesktopCookies.decrypt(legacy, key: key, host: ".claude.ai", version: 23) == "test-only-encrypted-session")
}
@Test func expiredOrOtherSiteCookiesNeverReadKeychain() throws {
    for fixture in [try CookieDatabase(expires: 1), try CookieDatabase(host: "claude.ai.evil.example")] {
        defer { fixture.remove() }
        #expect(throws: ClaudeDesktopCookieError.notLoggedIn) {
            try ClaudeDesktopCookies.read(allowsUI: true, directory: fixture.directory) { _ in
                Issue.record("Must not read a key for an ineligible cookie")
                throw ClaudeDesktopCookieError.permission
            }
        }
    }
}
@Test func desktopCookieHeaderRejectsInjection() throws {
    let fixture = try CookieDatabase(value: "test-only; another=value")
    defer { fixture.remove() }
    #expect(throws: ClaudeDesktopCookieError.notLoggedIn) {
        try ClaudeDesktopCookies.read(allowsUI: false, directory: fixture.directory) { _ in throw ClaudeDesktopCookieError.permission }
    }
}

private final class ClaudeWebProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct ClaudeDesktopHTTPTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaudeWebProtocol.self]
        return URLSession(configuration: config)
    }
    @Test func appSessionIsReloadedAndUsageUsesItsOrganization() async {
        let id = "00000000-0000-0000-0000-000000000001"
        var requests = 0
        ClaudeWebProtocol.handler = { request in
            requests += 1
            #expect(request.url?.host == "claude.ai")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("NokoriAI/") == true)
            #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=test-only-session")
            if request.url?.path == "/api/organizations" { return (200, [:], Data("[{\"uuid\":\"\(id)\"}]".utf8)) }
            #expect(request.url?.path == "/api/organizations/\(id)/usage")
            return (200, [:], Data(#"{"five_hour":{"utilization":25,"resets_at":null},"seven_day":{"utilization":50,"resets_at":null}}"#.utf8))
        }
        let reader = TestSessionReader()
        let fetcher = ClaudeDesktopFetcher(session: session(), readSession: { try reader.read($0) })
        let first = await fetcher.fetch(userInitiated: true, manualPath: nil)
        #expect(first.snapshot.status == .ok)
        #expect(first.snapshot.window(.fiveHour)?.usedPercent == 25)
        #expect(first.resetsHistory)
        let sameAccount = await fetcher.fetch(userInitiated: false, manualPath: nil)
        #expect(!sameAccount.resetsHistory)
        reader.key = "test-only-other-session"
        ClaudeWebProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=test-only-other-session")
            requests += 1
            return request.url?.path == "/api/organizations"
                ? (200, [:], Data("[{\"uuid\":\"\(id)\"}]".utf8))
                : (200, [:], Data(#"{"five_hour":{"utilization":75,"resets_at":null}}"#.utf8))
        }
        let switched = await fetcher.fetch(userInitiated: false, manualPath: nil)
        #expect(switched.resetsHistory)
        #expect(switched.snapshot.window(.fiveHour)?.usedPercent == 75)
        reader.signedOut = true
        let second = await fetcher.fetch(userInitiated: false, manualPath: nil)
        #expect(second.snapshot.status == .notLoggedIn)
        #expect(requests == 6)
        #expect(reader.interactions == [true, false, false, false])
    }
    @Test(arguments: [401, 403, 429, 500]) func webFailuresStopWithoutCLIFallback(_ status: Int) async {
        var requests = 0
        ClaudeWebProtocol.handler = { _ in requests += 1; return (status, ["Retry-After": "120"], Data()) }
        let fetcher = ClaudeDesktopFetcher(session: session(), readSession: { _ in ClaudeDesktopSession(key: "test-only-session", organization: nil) })
        let result = await fetcher.fetch(userInitiated: false, manualPath: nil)
        #expect(requests == 1)
        #expect(result.snapshot.status == (status == 401 ? .notLoggedIn : status == 429 ? .failed(.rateLimited) : .failed(.unexpected)))
        #expect(result.retryAfter == (status == 429 ? 120 : nil))
    }
    @Test func permissionFailureDoesNotIssueHTTP() async {
        ClaudeWebProtocol.handler = { _ in Issue.record("No HTTP without permission"); return (200, [:], Data()) }
        let fetcher = ClaudeDesktopFetcher(session: session(), readSession: { _ in throw ClaudeDesktopCookieError.permission })
        #expect(await fetcher.fetch(userInitiated: false, manualPath: nil).snapshot.status == .needsKeychainPermission)
    }
    @Test func desktopSelectionRoutesBeforeReadingCLICredentials() async {
        let desktop = ClaudeDesktopFetcher(session: session(), readSession: { _ in throw ClaudeDesktopCookieError.notLoggedIn })
        let fetcher = ClaudeFetcher(desktop: desktop, useClaudeApp: { true })
        #expect(await fetcher.fetch(userInitiated: true, manualPath: nil).snapshot.status == .notLoggedIn)
    }
}

private final class TestSessionReader: @unchecked Sendable {
    private let lock = NSLock()
    private var loggedOut = false
    private var reads: [Bool] = []
    private var sessionKey = "test-only-session"
    var key: String {
        get { lock.withLock { sessionKey } }
        set { lock.withLock { sessionKey = newValue } }
    }
    var signedOut: Bool {
        get { lock.withLock { loggedOut } }
        set { lock.withLock { loggedOut = newValue } }
    }
    var interactions: [Bool] { lock.withLock { reads } }
    func read(_ allowsUI: Bool) throws -> ClaudeDesktopSession {
        try lock.withLock {
            reads.append(allowsUI)
            if loggedOut { throw ClaudeDesktopCookieError.notLoggedIn }
            return ClaudeDesktopSession(key: sessionKey, organization: nil)
        }
    }
}

private actor PendingClaudeFetcher: Fetcher {
    private var pending: CheckedContinuation<FetchResult, Never>?
    private(set) var calls: [Bool] = []
    func fetch(userInitiated: Bool, manualPath: String?) async -> FetchResult {
        calls.append(userInitiated)
        if calls.count == 1 { return await withCheckedContinuation { pending = $0 } }
        return FetchResult(snapshot: UsageSnapshot(provider: .claude, windows: [.init(kind: .weekly, usedPercent: 75, resetsAt: nil)], status: .ok, fetchedAt: .now))
    }
    func completeOldSource() {
        pending?.resume(returning: FetchResult(snapshot: UsageSnapshot(provider: .claude, windows: [.init(kind: .weekly, usedPercent: 10, resetsAt: nil)], status: .ok, fetchedAt: .now)))
        pending = nil
    }
}

private actor AccountSwitchFetcher: Fetcher {
    private var first = true
    func fetch(userInitiated: Bool, manualPath: String?) async -> FetchResult {
        defer { first = false }
        let window = UsageWindow(kind: .weekly, usedPercent: first ? 10 : 75,
                                 resetsAt: Date.now.addingTimeInterval((first ? 2 : 9) * 86_400))
        return FetchResult(snapshot: UsageSnapshot(provider: .claude, windows: [window], status: .ok, fetchedAt: .now), resetsHistory: !first)
    }
}

@Test @MainActor func appAccountSwitchDoesNotReuseOldWeeklyReset() async throws {
    let fetcher = AccountSwitchFetcher()
    let store = UsageStore(claude: fetcher, codex: fetcher)
    await store.refresh(.claude, userInitiated: false)
    await store.refresh(.claude, userInitiated: false)
    let reset = try #require(store.snapshot(.claude).window(.weekly)?.resetsAt)
    #expect(reset.timeIntervalSinceNow > 8 * 86_400)
}

@Test @MainActor func sourceSwitchDiscardsInFlightCLIResult() async throws {
    let fetcher = PendingClaudeFetcher()
    let store = UsageStore(claude: fetcher, codex: fetcher)
    store.configure(services: "claude", minutes: 5, manualPath: nil)
    let deadline = Date.now.addingTimeInterval(3)
    while await fetcher.calls.isEmpty && Date.now < deadline { await Task.yield() }
    try #require(await !fetcher.calls.isEmpty)
    store.configure(services: "claude", minutes: 5, manualPath: nil, claudeApp: true)
    // A simultaneous display/interval update must not lose the user's permission request.
    store.configure(services: "claude", minutes: 15, manualPath: nil, claudeApp: true)
    await fetcher.completeOldSource()
    while store.snapshot(.claude).status != .ok && Date.now < deadline { await Task.yield() }
    #expect(store.snapshot(.claude).window(.weekly)?.usedPercent == 75)
    #expect(await fetcher.calls == [false, true])
    store.configure(services: "codex", minutes: 5, manualPath: nil, claudeApp: true)
}
