import CoreServices
import Foundation
import UsageCore

/// Notices Claude Code and Codex writing their session logs, so fetches follow actual use. Only the changed
/// folder's path is seen, never a file's contents. The Claude desktop app's Code tab writes to the same place.
final class ActivityWatcher {
    private var stream: FSEventStreamRef?
    private let folders: [(provider: Provider, path: String)]
    private let onActivity: (Provider) -> Void
    init?(onActivity: @escaping (Provider) -> Void) {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let claude = (environment["CLAUDE_CONFIG_DIR"] ?? "\(home)/.claude") + "/projects"
        let codex = (environment["CODEX_HOME"] ?? "\(home)/.codex") + "/sessions"
        folders = [(.claude, claude), (.codex, codex)].filter { FileManager.default.fileExists(atPath: $0.1) }
        guard !folders.isEmpty else { return nil }
        self.onActivity = onActivity
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ActivityWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            for folder in watcher.folders where changed.contains(where: { $0.hasPrefix(folder.path) }) { watcher.onActivity(folder.provider) }
        }
        // Ten seconds of latency folds a burst of writes into one notice; nothing here needs it sooner.
        guard let stream = FSEventStreamCreate(nil, callback, &context, folders.map(\.path) as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 10,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }
    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
