import Foundation
import Security
import SQLite3
import CommonCrypto
import CryptoKit

struct ClaudeDesktopSession: Sendable {
    let key: String
    let organization: UUID?
}

enum ClaudeDesktopCookieError: Error { case notLoggedIn, permission, unreadable }

enum ClaudeDesktopCookies {
    // Read Electron's original database in place. Never copy a credential database
    // or export decrypted cookies to disk. Claude owns both this database and its key.
    static func read(allowsUI: Bool, directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude"),
        password: (Bool) throws -> Data = readPassword) throws -> ClaudeDesktopSession {
        let candidates = [directory.appendingPathComponent("Network/Cookies"), directory.appendingPathComponent("Cookies")]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ClaudeDesktopCookieError.notLoggedIn
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw ClaudeDesktopCookieError.unreadable
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM meta WHERE key = 'version'", -1, &statement, nil) == SQLITE_OK else {
            throw ClaudeDesktopCookieError.unreadable
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { sqlite3_finalize(statement); throw ClaudeDesktopCookieError.unreadable }
        let version = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)
        statement = nil
        let sql = "SELECT host_key, name, value, encrypted_value, expires_utc FROM cookies WHERE host_key IN ('claude.ai', '.claude.ai') AND name IN ('sessionKey', 'lastActiveOrg') AND path = '/'"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw ClaudeDesktopCookieError.unreadable }
        defer { sqlite3_finalize(statement) }
        func string(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
        struct Row { let host: String; let name: String; let value: String; let encrypted: Data }
        var rows: [Row] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw ClaudeDesktopCookieError.unreadable }
            let expires = sqlite3_column_int64(statement, 4)
            guard expires == 0 || Double(expires) / 1_000_000 - 11_644_473_600 > Date.now.timeIntervalSince1970 else { continue }
            let encrypted = sqlite3_column_blob(statement, 3).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, 3))) } ?? Data()
            rows.append(Row(host: string(0), name: string(1), value: string(2), encrypted: encrypted))
        }
        guard rows.contains(where: { $0.name == "sessionKey" && (!$0.value.isEmpty || !$0.encrypted.isEmpty) }) else {
            throw ClaudeDesktopCookieError.notLoggedIn
        }
        var values: [String: String] = [:]
        var encryptionKey: Data?
        for row in rows {
            let name = row.name
            var value = row.value
            if value.isEmpty && !row.encrypted.isEmpty {
                if encryptionKey == nil { encryptionKey = try deriveKey(password(allowsUI)) }
                value = try decrypt(row.encrypted, key: encryptionKey!, host: row.host, version: version)
            }
            guard !value.isEmpty else { continue }
            // Conflicting sessions must never silently select a different account.
            if let previous = values[name], previous != value { throw ClaudeDesktopCookieError.unreadable }
            values[name] = value
        }
        guard let key = values["sessionKey"], !key.isEmpty,
              key.utf8.allSatisfy({ $0 > 32 && $0 < 127 && $0 != 59 && $0 != 44 }) else {
            throw ClaudeDesktopCookieError.notLoggedIn
        }
        return ClaudeDesktopSession(key: key, organization: values["lastActiveOrg"].flatMap(UUID.init(uuidString:)))
    }

    private static func readPassword(allowsUI: Bool) throws -> Data {
        let result = KeychainAccess.perform(allowsUI: allowsUI) { () -> Data? in
            var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Claude Safe Storage", kSecAttrAccount as String: "Claude Key",
                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            if !allowsUI { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
            var value: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess else { return nil }
            return value as? Data
        }
        guard let password = result ?? nil else { throw ClaudeDesktopCookieError.permission }
        return password
    }

    static func deriveKey(_ password: Data) throws -> Data {
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let status = key.withUnsafeMutableBytes { output in
            password.withUnsafeBytes { secret in
                salt.withUnsafeBytes { salt in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), secret.baseAddress, password.count,
                        salt.baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        output.baseAddress, output.count)
                }
            }
        }
        guard status == kCCSuccess else { throw ClaudeDesktopCookieError.unreadable }
        return key
    }

    // Chromium on macOS uses v10 AES-CBC; v24+ plaintext starts with SHA256(host_key).
    // Reject unknown formats rather than interpreting an undecryptable cookie as a login.
    static func decrypt(_ encrypted: Data, key: Data, host: String, version: Int32) throws -> String {
        guard encrypted.starts(with: Data("v10".utf8)), encrypted.count > 3 else { throw ClaudeDesktopCookieError.unreadable }
        let ciphertext = Data(encrypted.dropFirst(3)), iv = Data(repeating: 32, count: kCCBlockSizeAES128)
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128), count = 0
        let status = output.withUnsafeMutableBytes { output in
            key.withUnsafeBytes { key in
                iv.withUnsafeBytes { iv in
                    ciphertext.withUnsafeBytes { input in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            key.baseAddress, key.count, iv.baseAddress, input.baseAddress, input.count,
                            output.baseAddress, output.count, &count)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw ClaudeDesktopCookieError.unreadable }
        output.count = count
        if version >= 24 {
            let hash = Data(SHA256.hash(data: Data(host.utf8)))
            guard output.starts(with: hash) else { throw ClaudeDesktopCookieError.unreadable }
            output.removeFirst(hash.count)
        }
        guard let value = String(data: output, encoding: .utf8) else { throw ClaudeDesktopCookieError.unreadable }
        return value
    }
}
