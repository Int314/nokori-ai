import Foundation
import CryptoKit
import UsageCore

actor ClaudeDesktopFetcher: Fetcher {
    typealias ReadSession = @Sendable (Bool) throws -> ClaudeDesktopSession
    private let readSession: ReadSession
    private let session: URLSession
    private var lastKeyHash: Data?
    private var lastOrganization: UUID?
    init(session: URLSession? = nil, readSession: @escaping ReadSession = { try ClaudeDesktopCookies.read(allowsUI: $0) }) {
        self.readSession = readSession
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        }
    }
    func fetch(userInitiated: Bool, manualPath: String?) async -> FetchResult {
        let login: ClaudeDesktopSession
        do {
            login = try await Task.detached(priority: .utility) { [readSession] in try readSession(userInitiated) }.value
        } catch ClaudeDesktopCookieError.notLoggedIn { return .failure(.claude, .notLoggedIn) }
        catch ClaudeDesktopCookieError.permission { return .failure(.claude, .needsKeychainPermission) }
        catch { return .failure(.claude, .failed(.unexpected)) }
        do {
            let organizations = try await get("organizations", key: login.key)
            let organization = try ClaudeWebParser.organization(data: organizations, preferred: login.organization)
            let usage = try await get("organizations/\(organization.uuid.uuidString.lowercased())/usage", key: login.key)
            let snapshot = try ClaudeWebParser.usage(data: usage, organization: organization, fetchedAt: .now)
            let hash = Data(SHA256.hash(data: Data(login.key.utf8)))
            let changed = hash != lastKeyHash || organization.uuid != lastOrganization
            lastKeyHash = hash
            lastOrganization = organization.uuid
            return FetchResult(snapshot: snapshot, resetsHistory: changed)
        } catch let failure as RequestFailure {
            return .failure(.claude, failure.status, retryAfter: failure.retryAfter)
        } catch is URLError { return .failure(.claude, .failed(.network)) }
        catch { return .failure(.claude, .failed(.unexpected)) }
    }
    private struct RequestFailure: Error {
        let status: FetchStatus
        var retryAfter: TimeInterval?
    }
    private func get(_ path: String, key: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://claude.ai/api/\(path)")!)
        request.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NokoriAI/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw FetchFailure.unexpected }
        switch response.statusCode {
        case 200: return data
        case 401: throw RequestFailure(status: .notLoggedIn)
        // A 403 can be a Cloudflare challenge, so do not tell the user to replace their login.
        case 403: throw RequestFailure(status: .failed(.unexpected))
        case 429: throw RequestFailure(status: .failed(.rateLimited),
            retryAfter: UsagePolicy.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: .now))
        default: throw RequestFailure(status: .failed(.unexpected))
        }
    }
    // Cookie headers must never follow a redirect to a different site or a sign-in page.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
