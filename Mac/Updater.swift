import Foundation
import Sparkle

/// Sparkle checks the feed in `Info.plist` once a day and offers what it finds. Usage comes from endpoints the
/// services can change without notice, so a fix has to reach people without them watching Releases.
@MainActor enum Updater {
    /// Only this project's own releases have a feed (project.yml), so a Debug build or someone's own build never
    /// replaces itself with one of them.
    static let enabled = !((Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "").isEmpty
    static let controller = SPUStandardUpdaterController(startingUpdater: enabled, updaterDelegate: nil, userDriverDelegate: nil)
}
