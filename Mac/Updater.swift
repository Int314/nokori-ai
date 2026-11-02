import Sparkle

/// Sparkle checks the feed in `Info.plist` once a day and offers what it finds. Usage comes from endpoints the
/// services can change without notice, so a fix has to reach people without them watching Releases.
@MainActor enum Updater {
    static let controller: SPUStandardUpdaterController = {
        #if DEBUG
        // A development build must never replace itself with a release.
        let starts = false
        #else
        let starts = true
        #endif
        return SPUStandardUpdaterController(startingUpdater: starts, updaterDelegate: nil, userDriverDelegate: nil)
    }()
}
