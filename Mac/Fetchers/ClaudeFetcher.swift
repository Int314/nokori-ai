import Foundation
import Security
import UsageCore

actor ClaudeFetcher: Fetcher {
    private var credentials: ClaudeCredentials?
    // An ephemeral session prevents authenticated responses being written to a disk cache.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    func fetch(userInitiated: Bool, manualPath: String?) async -> FetchResult {
        if credentials?.isExpired(now: .now) == true { credentials = nil }
        if credentials == nil, let failure = await loadCredentials(userInitiated: userInitiated) { return failure }
        guard let loaded = credentials else { return .failure(.claude, .notLoggedIn) }
        guard loaded.hasProfileScope else { self.credentials = nil; return .failure(.claude, .notLoggedIn) }
        if loaded.isExpired(now: .now) {
            self.credentials = nil
            guard await renewSignIn() else { return .failure(.claude, .expired) }
            if let failure = await loadCredentials(userInitiated: userInitiated) { return failure }
        }
        guard let credentials, !credentials.isExpired(now: .now) else { self.credentials = nil; return .failure(.claude, .expired) }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NokoriAI/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .failure(.claude, .failed(.unexpected)) }
            switch response.statusCode {
            case 200:
                do { return FetchResult(snapshot: try ClaudeUsageParser.parse(data: data, subscriptionType: credentials.subscriptionType, rateLimitTier: credentials.rateLimitTier, fetchedAt: .now)) }
                catch { return .failure(.claude, .failed(.unexpected)) }
            case 401: self.credentials = nil; return .failure(.claude, .expired)
            case 403: self.credentials = nil; return .failure(.claude, .notLoggedIn)
            case 429: return .failure(.claude, .failed(.rateLimited), retryAfter: UsagePolicy.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: .now))
            default: return .failure(.claude, .failed(.unexpected))
            }
        } catch { return .failure(.claude, .failed(.network)) }
    }
    /// Fills `credentials`, or says why it could not.
    private func loadCredentials(userInitiated: Bool) async -> FetchResult? {
        if Self.securityCanRead(),
           let data = await Task.detached(priority: .utility, operation: { Self.readWithSecurity(path: "/usr/bin/security", timeout: 3) }).value {
            credentials = ClaudeCredentials.parse(data: data)
            if credentials != nil, let modified = Self.keychainModification() { UserDefaults.standard.set(modified, forKey: Self.readAtKey) }
            if credentials != nil { return nil }
        }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecReturnData as String: true,
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if !userInitiated { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?
        let status = Self.readKeychain(query, allowsUI: userInitiated, result: &result)
        let data: Data
        switch status {
        case errSecSuccess:
            guard let item = result as? [String: Any], let value = item[kSecValueData as String] as? Data else { return .failure(.claude, .notLoggedIn) }
            if let modified = item[kSecAttrModificationDate as String] as? Date { UserDefaults.standard.set(modified, forKey: Self.readAtKey) }
            data = value
        case errSecItemNotFound:
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
            guard let value = try? Data(contentsOf: url) else { return .failure(.claude, .notLoggedIn) }
            data = value
        default:
            let lastRead = UserDefaults.standard.object(forKey: Self.readAtKey) as? Date
            return .failure(.claude, KeychainState.status(lastReadModification: lastRead, currentModification: Self.keychainModification()))
        }
        credentials = ClaudeCredentials.parse(data: data)
        return credentials == nil ? .failure(.claude, .notLoggedIn) : nil
    }
    private var lastRenewal: Date?
    /// True when Claude Code wrote a new sign-in. A sign-in kept in `.credentials.json` instead of the keychain is not watched.
    private func renewSignIn() async -> Bool {
        guard ClaudeRenewal.shouldTry(lastAttempt: lastRenewal, now: .now), let path = ClaudeCLI.detectedPath() else { return false }
        lastRenewal = .now
        let before = Self.keychainModification()
        return await Task.detached(priority: .utility) {
            ClaudeCLI.renewSignIn(path: path) { Self.keychainModification().map { $0 != before } ?? false }
        }.value
    }
    private static let service = "Claude Code-credentials"
    /// Reading the item's ACL needs no permission. Claude Code recreates the item on every token renewal,
    /// which drops this app from the ACL but keeps `/usr/bin/security`, the tool Claude Code writes it with.
    nonisolated private static func securityCanRead() -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnRef as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard readKeychain(query, allowsUI: false, result: &result) == errSecSuccess, let result, CFGetTypeID(result) == SecKeychainItemGetTypeID() else { return false }
        var access: SecAccess?
        guard SecKeychainItemCopyAccess(result as! SecKeychainItem, &access) == errSecSuccess, let access,
              let entries = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as? [SecACL] else { return false }
        return KeychainState.securityCanRead(decryptApplications: entries.map { entry in
            var applications: CFArray?, description: CFString?, prompt = SecKeychainPromptSelector()
            guard SecACLCopyContents(entry, &applications, &description, &prompt) == errSecSuccess else { return [] }
            return (applications as? [SecTrustedApplication])?.map { application in
                var data: CFData?
                guard SecTrustedApplicationCopyData(application, &data) == errSecSuccess, let data else { return "" }
                return String(decoding: data as Data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            }
        })
    }
    /// `security` ignores the no-UI flags, so call this only after `securityCanRead()`. The timeout is a backstop.
    nonisolated static func readWithSecurity(path: String, timeout: TimeInterval) -> Data? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }
        try? output.fileHandleForWriting.close()
        defer { try? output.fileHandleForReading.close() }
        // The output is far smaller than the pipe buffer, so the process never blocks on writing it.
        guard exited.wait(timeout: .now() + timeout) == .success else {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            return nil
        }
        guard process.terminationStatus == 0, var data = try? output.fileHandleForReading.readToEnd() else { return nil }
        while data.last == 10 || data.last == 13 { data.removeLast() }
        return data.isEmpty ? nil : data
    }
    /// Modification date of the keychain item at the last successful read. Not a secret.
    private static let readAtKey = "claudeKeychainReadAt"
    /// Attributes only, so no permission dialog and the token is not read.
    nonisolated private static func keychainModification() -> Date? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard readKeychain(query, allowsUI: false, result: &result) == errSecSuccess else { return nil }
        return (result as? [String: Any])?[kSecAttrModificationDate as String] as? Date
    }
    // Legacy file-based keychains can ignore kSecUseAuthenticationUIFail. Serialize the
    // process-wide interaction flag and restore its previous value after every read.
    private static let keychainLock = NSLock()
    nonisolated private static func readKeychain(_ query: [String: Any], allowsUI: Bool, result: inout CFTypeRef?) -> OSStatus {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        var wasAllowed: DarwinBoolean = true
        let status = SecKeychainGetUserInteractionAllowed(&wasAllowed)
        guard status == errSecSuccess else { return status }
        if !allowsUI {
            let status = SecKeychainSetUserInteractionAllowed(false)
            guard status == errSecSuccess else { return status }
        }
        defer { if !allowsUI { SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue) } }
        return SecItemCopyMatching(query as CFDictionary, &result)
    }
    nonisolated static func hasLogin() -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = readKeychain(query, allowsUI: false, result: &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed || FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json").path)
    }
}
