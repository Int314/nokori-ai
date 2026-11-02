import Foundation
import Darwin
import UsageCore

struct CodexFetcher: Fetcher {
    static func detectedPath() -> String? {
        ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npm-global/bin/codex").path,
         "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func hasLogin() -> Bool {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path)
    }
    func fetch(userInitiated: Bool, manualPath: String?) async -> FetchResult {
        guard let path = manualPath ?? Self.detectedPath(), FileManager.default.isExecutableFile(atPath: path) else { return .failure(.codex, .failed(.codexNotFound)) }
        // Blocking POSIX poll runs off the main actor; each invocation owns all its handles.
        return await Task.detached(priority: .utility) { Self.run(path: path) }.value
    }
    private static func run(path: String) -> FetchResult {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([URL(fileURLWithPath: path).deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(.codex, .failed(.launchFailed)) }
        // Close the parent's copies of child-owned ends so EOF is observable.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let started = ProcessInfo.processInfo.systemUptime
        var buffer = Data()
        var pending: [Int: Data] = [:]
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        /// `eof` is what a closed stdout means: before the first response, codex never really started.
        func receive(_ id: Int, deadline: TimeInterval, eof: FetchFailure = .unexpected) throws -> Data {
            if let data = pending.removeValue(forKey: id) { return data }
            while ProcessInfo.processInfo.systemUptime < deadline {
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                    if line.isEmpty { continue }
                    if let responseID = try CodexRPC.responseID(line) {
                        if responseID == id { return line }
                        pending[responseID] = line
                    }
                }
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let remaining = max(1, min(100, Int((deadline - ProcessInfo.processInfo.systemUptime) * 1000)))
                let ready = poll(&descriptor, 1, Int32(remaining))
                if ready < 0 { if errno == EINTR { continue }; throw FetchFailure.unexpected }
                if ready > 0 {
                    var bytes = [UInt8](repeating: 0, count: 8192)
                    let count = read(descriptor.fd, &bytes, bytes.count)
                    guard count > 0 else { throw eof }
                    buffer.append(contentsOf: bytes.prefix(count))
                    guard buffer.count <= 4 * 1024 * 1024 else { throw FetchFailure.unexpected }
                }
            }
            throw FetchFailure.timeout
        }
        do {
            // A write failing this early means the process is already gone.
            do { try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "nokori-ai", "title": "Nokori AI", "version": AppVersion.current], "capabilities": NSNull()]]) }
            catch { throw FetchFailure.launchFailed }
            _ = try receive(1, deadline: started + 10, eof: .launchFailed)
            try send(["method": "initialized"])
            try send(["id": 2, "method": "account/read", "params": [:]])
            let account = try receive(2, deadline: started + 15)
            guard try CodexUsageParser.isSubscriptionAccount(account) else { return .failure(.codex, .notLoggedIn) }
            try send(["id": 3, "method": "account/rateLimits/read", "params": ["excludeResetCreditDetails": true]])
            let limits = try receive(3, deadline: started + 15)
            return FetchResult(snapshot: try CodexUsageParser.parse(accountRead: account, rateLimitsRead: limits, fetchedAt: .now))
        } catch let failure as FetchFailure { return .failure(.codex, .failed(failure)) }
        catch { return .failure(.codex, .failed(.unexpected)) }
    }
}
