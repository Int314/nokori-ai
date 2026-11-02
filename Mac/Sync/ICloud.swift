import Security
import UsageCore

enum ICloud {
    /// Debug builds are unsigned for iCloud, and CloudKit raises an uncatchable exception when the entitlement is missing.
    static var entitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) != nil
    }
    static func sync(enabled: Bool) -> CloudSync? { enabled && entitled ? CloudSync() : nil }
    static func available() async -> Bool { entitled ? await CloudSync.accountAvailable() : false }
}
