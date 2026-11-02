import CloudKit
import Foundation

/// Why the iPhone could not read from iCloud, sorted by what the person can do about it.
public enum SyncFailure: Equatable, Sendable {
    case noAccount, offline, busy, other(code: Int)
    public init(_ error: any Error) {
        guard let error = error as? CKError else { self = .other(code: (error as NSError).code); return }
        switch error.code {
        case .notAuthenticated: self = .noAccount
        case .networkUnavailable, .networkFailure: self = .offline
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: self = .busy
        default: self = .other(code: error.code.rawValue)
        }
    }
}

/// The Mac writes, the iPhone and its widgets read. Everything lives in the user's private database.
public actor CloudSync {
    public static let containerID = "iCloud.dev.int314.nokori"
    private static let subscriptionID = CKSubscription.ID("usage-changes")
    // Lazy: creating the container without the iCloud entitlement is what raises, so merely constructing a CloudSync is safe.
    private lazy var database = CKContainer(identifier: CloudSync.containerID).privateCloudDatabase
    private var zoneReady = false
    public init() {}

    /// Callers must have the iCloud entitlement; CloudKit raises an Objective-C exception without it.
    public static func accountAvailable() async -> Bool {
        (try? await CKContainer(identifier: containerID).accountStatus()) == .available
    }

    // MARK: Mac

    public func save(snapshot: UsageSnapshot) async throws {
        try await ensureZone()
        let id = CloudRecords.snapshotID(snapshot.provider)
        var existing = try await record(id)
        for attempt in 0..<2 {
            if let existing, !CloudRecords.shouldWrite(local: snapshot.fetchedAt, remote: CloudRecords.fetchedAt(of: existing)) { return }
            do {
                try await write(CloudRecords.record(for: snapshot, existing: existing))
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                existing = try await record(id)
            }
        }
    }
    public func save(issue: FetchStatus, for provider: Provider) async throws {
        try await ensureZone()
        let id = CloudRecords.snapshotID(provider)
        var existing = try await record(id)
        for attempt in 0..<2 {
            if let existing, CloudRecords.issue(from: existing) == issue { return }
            do {
                try await write(CloudRecords.record(issue: issue, provider: provider, existing: existing))
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                existing = try await record(id)
            }
        }
    }
    public func save(services: DisplayServices) async throws {
        try await ensureZone()
        try await write(CloudRecords.record(for: services, existing: record(CloudRecords.displayID)))
    }

    // MARK: iPhone

    public func fetchAll() async throws -> (snapshots: [UsageSnapshot], issues: [Provider: FetchStatus], services: DisplayServices) {
        let ids = Provider.allCases.map(CloudRecords.snapshotID) + [CloudRecords.displayID]
        let results: [CKRecord.ID: Result<CKRecord, any Error>]
        do { results = try await database.records(for: ids) }
        catch let error as CKError where error.code == .zoneNotFound { return ([], [:], .both) }
        var records: [CKRecord] = []
        for result in results.values {
            switch result {
            case .success(let record): records.append(record)
            case .failure(let error as CKError) where error.code == .unknownItem || error.code == .zoneNotFound: continue
            case .failure(let error): throw error
            }
        }
        let snapshotRecords = Provider.allCases.compactMap { provider in records.first { $0.recordID == CloudRecords.snapshotID(provider) }.map { (provider, $0) } }
        return (snapshotRecords.compactMap { CloudRecords.snapshot(from: $0.1) },
                Dictionary(uniqueKeysWithValues: snapshotRecords.compactMap { provider, record in CloudRecords.issue(from: record).map { (provider, $0) } }),
                records.first { $0.recordID == CloudRecords.displayID }.flatMap(CloudRecords.services(from:)) ?? .both)
    }
    /// Silent pushes for any change in the private database (custom zones only), created once.
    public func subscribeToChanges() async throws {
        do { _ = try await database.subscription(for: CloudSync.subscriptionID); return }
        catch let error as CKError where error.code == .unknownItem {}
        let subscription = CKDatabaseSubscription(subscriptionID: CloudSync.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }

    // MARK: Private

    private func ensureZone() async throws {
        guard !zoneReady else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: CloudRecords.zoneID)], deleting: [])
        zoneReady = true
    }
    private func record(_ id: CKRecord.ID) async throws -> CKRecord? {
        do { return try await database.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }
    private func write(_ record: CKRecord) async throws {
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        for saved in result.saveResults.values { _ = try saved.get() }
    }
}
