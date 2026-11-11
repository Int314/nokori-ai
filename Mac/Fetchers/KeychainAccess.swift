import Foundation
import Security

enum KeychainAccess {
    private static let lock = NSLock()

    // Legacy keychains can ignore the query's no-UI flag. Share the process-wide gate
    // between CLI credentials and Claude app cookies, and restore it after each read.
    static func perform<T>(allowsUI: Bool, _ operation: () throws -> T) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        var allowed: DarwinBoolean = true
        guard SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess else { return nil }
        if !allowsUI, SecKeychainSetUserInteractionAllowed(false) != errSecSuccess { return nil }
        defer { if !allowsUI { SecKeychainSetUserInteractionAllowed(allowed.boolValue) } }
        return try operation()
    }
}
