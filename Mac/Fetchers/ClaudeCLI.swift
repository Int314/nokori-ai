import Foundation
import Darwin
import UsageCore

/// Starts Claude Code briefly so it renews its own sign-in (see `ClaudeRenewal`). The Claude desktop app signs in on its
/// own and never renews the keychain item, so without this a desktop-only day ends at the token's eight-hour lifetime.
enum ClaudeCLI {
    static func detectedPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    /// True once `renewed()` reports the new sign-in. Blocking; call it off the main actor.
    static func renewSignIn(path: String, timeout: TimeInterval = 30, renewed: () -> Bool) -> Bool {
        guard let directory = probeDirectory() else { return false }
        let process = Process()
        let input = Pipe(), output = Pipe()
        // `script` gives Claude Code the terminal it needs to start interactively; `-p` would not renew.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        // No hooks or MCP servers of the person's own: this start only exists to renew.
        process.arguments = ["-q", "/dev/null", path, "--strict-mcp-config", "--settings", #"{"disableAllHooks":true}"#]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        // Either would make Claude Code skip the keychain sign-in this is meant to renew.
        environment["ANTHROPIC_API_KEY"] = nil
        environment["CLAUDE_CODE_OAUTH_TOKEN"] = nil
        environment["TERM"] = "xterm-256color"
        environment["PATH"] = [URL(fileURLWithPath: path).deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        func type(_ text: String) { try? input.fileHandleForWriting.write(contentsOf: Data(text.utf8)) }
        defer {
            if process.isRunning {
                type("/exit\r")
                let deadline = ProcessInfo.processInfo.systemUptime + 3
                while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(50_000) }
            }
            if process.isRunning { process.terminate() }
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        var screen = Data()
        var trusted = false
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if renewed() { return true }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 500)
            if ready < 0 { if errno == EINTR { continue }; return false }
            if ready > 0 {
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = read(descriptor.fd, &bytes, bytes.count)
                guard count > 0 else { return renewed() }
                screen.append(contentsOf: bytes.prefix(count))
                if screen.count > 64 * 1024 { screen.removeFirst(screen.count - 64 * 1024) }
            }
            // The folder is Nokori's own and empty, so trusting it gives Claude Code nothing. "No, exit" is preselected,
            // and keys sent while the question is still drawing arrive as Esc, which also exits.
            if !trusted, ClaudeRenewal.asksForTrust(String(decoding: screen, as: UTF8.self)) {
                trusted = true
                usleep(1_000_000)
                type("\u{1B}[B")
                usleep(1_000_000)
                type("\r")
            }
        }
        return renewed()
    }
    private static func probeDirectory() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("Nokori AI/ClaudeProbe", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return nil }
        return directory
    }
}
