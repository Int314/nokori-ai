import Security
import UsageCore

enum ICloud {
    /// A build without the iCloud entitlement (built unsigned) must not touch CloudKit, which then raises an uncatchable exception.
    static var entitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) != nil
    }
    static func sync(enabled: Bool) -> CloudSync? { enabled && entitled ? CloudSync() : nil }
    static func available() async -> Bool { entitled ? await CloudSync.accountAvailable() : false }
}
