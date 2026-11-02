import Foundation
import Testing
import Darwin
import UsageCore

/// No app host: these tests cannot launch the real app or touch real credentials.
private struct FakeCodex {
    let directory: URL
    let executable: URL
    init(mode: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("nokori-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent("codex")
        let script = """
        #!/usr/bin/python3
        import os, sys, json, time, signal
        from pathlib import Path
        Path(__file__).with_suffix('.pid').write_text(str(os.getpid()))
        mode = '\(mode)'
        if mode == 'timeout':
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            time.sleep(60)
        if mode == 'exit':
            sys.exit(0)
        assert sys.argv[1:] == ['-s','read-only','-a','never','app-server']
        assert os.environ['PATH'].split(':')[0] == str(Path(__file__).parent)
        sys.stderr.write('discarded diagnostic\\n' * 10000)
        sys.stderr.flush()
        for line in sys.stdin:
            req = json.loads(line)
            method = req['method']
            if method == 'initialize':
                assert req['params']['clientInfo']['name'] == 'nokori-ai'
                print(json.dumps({'method':'notification'}), flush=True)
                result = {}
            elif method == 'initialized':
                continue
            elif method == 'account/read':
                if mode == 'exit-after-initialize':
                    sys.exit(0)
                result = {'account':None if mode == 'loggedout' else {'type':'chatgpt','planType':'plus'}}
            elif method == 'account/rateLimits/read':
                assert req['params']['excludeResetCreditDetails'] is True
                if mode == 'later-timeout':
                    signal.signal(signal.SIGTERM, signal.SIG_IGN)
                    time.sleep(60)
                if mode == 'error':
                    print(json.dumps({'id':req['id'],'error':{'code':-1}}), flush=True)
                    continue
                result = {'rateLimits':{'primary':{'usedPercent':42,'windowDurationMins':300,'resetsAt':1793444298},'secondary':{'usedPercent':68,'windowDurationMins':10080}}}
            else:
                sys.exit(1)
            print(json.dumps({'id':req['id'],'result':result}), flush=True)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func assertTerminated() throws {
        let pid = try #require(Int32(String(contentsOf: executable.appendingPathExtension("pid"), encoding: .utf8)))
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}
@Test(arguments: ["success", "error", "loggedout", "exit", "exit-after-initialize", "timeout", "later-timeout"])
func codexProcessLifecycle(_ mode: String) async throws {
    let fake = try FakeCodex(mode: mode)
    defer { fake.remove() }
    let start = Date.now
    let result = await CodexFetcher().fetch(userInitiated: false, manualPath: fake.executable.path)
    switch mode {
    case "success":
        #expect(result.snapshot.status == .ok)
        #expect(result.snapshot.window(.fiveHour)?.usedPercent == 42)
        #expect(result.snapshot.window(.weekly)?.usedPercent == 68)
    case "loggedout": #expect(result.snapshot.status == .notLoggedIn)
    case "timeout", "later-timeout":
        #expect(result.snapshot.status == .failed(.timeout))
        #expect(Date.now.timeIntervalSince(start) < (mode == "timeout" ? 13 : 18))
    case "exit": #expect(result.snapshot.status == .failed(.launchFailed))
    default: #expect(result.snapshot.status == .failed(.unexpected))
    }
    try fake.assertTerminated()
}
@Test func unlaunchableExecutable() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nokori-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("codex")
    try "#!/nonexistent/interpreter\n".write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let result = await CodexFetcher().fetch(userInitiated: false, manualPath: executable.path)
    #expect(result.snapshot.status == .failed(.launchFailed))
}
@Test func missingExecutable() async {
    let result = await CodexFetcher().fetch(userInitiated: false, manualPath: "/not/a/codex")
    #expect(result.snapshot.status == .failed(.codexNotFound))
}

private actor StubFetcher: Fetcher {
    var calls = 0
    let result: FetchResult
    init(_ result: FetchResult) { self.result = result }
    func fetch(userInitiated: Bool, manualPath: String?) async -> FetchResult { calls += 1; return result }
}
@Test @MainActor func storeHonorsRateLimitAndHiddenServices() async {
    let claude = StubFetcher(.failure(.claude, .failed(.rateLimited), retryAfter: 3600))
    let codex = StubFetcher(.failure(.codex, .notLoggedIn))
    let store = UsageStore(claude: claude, codex: codex)
    store.visible = [.claude]
    await store.refresh(.claude, userInitiated: false)
    await store.refresh(.claude, userInitiated: true)
    await store.refresh(.codex, userInitiated: true)
    #expect(await claude.calls == 1)
    #expect(await codex.calls == 0)
}

private actor SequenceFetcher: Fetcher {
    var results: [FetchResult]
    init(_ results: [FetchResult]) { self.results = results }
    func fetch(userInitiated: Bool, manualPath: String?) async -> FetchResult { results.removeFirst() }
}
@Test @MainActor func failurePreservesOnlyPlan() async {
    let success = FetchResult(snapshot: UsageSnapshot(provider: .claude, plan: "Max 5x", windows: [.init(kind: .fiveHour, usedPercent: 42, resetsAt: nil)], status: .ok, fetchedAt: .now))
    let claude = SequenceFetcher([success, .failure(.claude, .failed(.network))])
    let store = UsageStore(claude: claude, codex: StubFetcher(.failure(.codex, .notLoggedIn)))
    await store.refresh(.claude, userInitiated: false)
    await store.refresh(.claude, userInitiated: true)
    #expect(store.snapshot(.claude).plan == "Max 5x")
    #expect(store.snapshot(.claude).windows.isEmpty)
    #expect(store.snapshot(.claude).status == .failed(.network))
}

@Test @MainActor func goodFetchWaitsForUseBeforeTheSetInterval() async {
    let success = FetchResult(snapshot: UsageSnapshot(provider: .claude, windows: [.init(kind: .fiveHour, usedPercent: 42, resetsAt: nil)], status: .ok, fetchedAt: .now))
    let store = UsageStore(claude: StubFetcher(success), codex: StubFetcher(.failure(.codex, .notLoggedIn)))
    await store.refresh(.claude, userInitiated: false)
    #expect(abs(store.dueDate(.claude).timeIntervalSinceNow - UsagePolicy.idleInterval) < 5)
    store.noteActivity(.claude)
    #expect(abs(store.dueDate(.claude).timeIntervalSinceNow - store.interval) < 5)
    // A failure keeps its own retry time, whatever the use.
    await store.refresh(.codex, userInitiated: true)
    #expect(store.dueDate(.codex).timeIntervalSinceNow < UsagePolicy.idleInterval)
}
@Test @MainActor func launchFailedPausesOnlyAutomaticFetches() async {
    let codex = StubFetcher(.failure(.codex, .failed(.launchFailed)))
    let store = UsageStore(claude: StubFetcher(.failure(.claude, .notLoggedIn)), codex: codex)
    await store.refresh(.codex, userInitiated: false)
    await store.refresh(.codex, userInitiated: false)
    #expect(await codex.calls == 1)
    await store.refresh(.codex, userInitiated: true)
    #expect(await codex.calls == 2)
    #expect(store.snapshot(.codex).status == .failed(.launchFailed))
}
@Test @MainActor func otherFailuresDoNotPauseAutomaticFetches() async {
    let codex = StubFetcher(.failure(.codex, .failed(.network)))
    let store = UsageStore(claude: StubFetcher(.failure(.claude, .notLoggedIn)), codex: codex)
    await store.refresh(.codex, userInitiated: false)
    await store.refresh(.codex, userInitiated: false)
    #expect(await codex.calls == 2)
}
@Test @MainActor func unconfirmedWeeklyResetJumpIsHeldUntilSeenTwice() async {
    func result(resetsIn days: Double) -> FetchResult {
        FetchResult(snapshot: UsageSnapshot(provider: .claude, windows: [.init(kind: .weekly, usedPercent: 40, resetsAt: Date.now.addingTimeInterval(days * 86400))], status: .ok, fetchedAt: .now))
    }
    let normal = result(resetsIn: 2), jump = result(resetsIn: 9)
    let store = UsageStore(claude: SequenceFetcher([normal, jump, jump]), codex: StubFetcher(.failure(.codex, .notLoggedIn)))
    await store.refresh(.claude, userInitiated: false)
    let kept = store.snapshot(.claude).window(.weekly)?.resetsAt
    #expect(kept == normal.snapshot.window(.weekly)?.resetsAt)
    await store.refresh(.claude, userInitiated: true)
    #expect(store.snapshot(.claude).window(.weekly)?.resetsAt == kept)
    await store.refresh(.claude, userInitiated: true)
    #expect(store.snapshot(.claude).window(.weekly)?.resetsAt == jump.snapshot.window(.weekly)?.resetsAt)
}

/// A stand-in for `/usr/bin/security`; the real one would read the real keychain.
@Test(arguments: ["success", "fail", "hang"])
func securityToolRead(_ mode: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nokori-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("security")
    try """
    #!/bin/sh
    [ "$*" = "find-generic-password -s Claude Code-credentials -w" ] || exit 2
    case \(mode) in
    success) printf '{"claudeAiOauth":{}}\\n' ;;
    fail) exit 44 ;;
    hang) trap '' TERM; exec sleep 60 ;;
    esac
    """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let start = Date.now
    let data = ClaudeFetcher.readWithSecurity(path: executable.path, timeout: 1)
    #expect(data == (mode == "success" ? Data(#"{"claudeAiOauth":{}}"#.utf8) : nil))
    #expect(Date.now.timeIntervalSince(start) < 3)
}
