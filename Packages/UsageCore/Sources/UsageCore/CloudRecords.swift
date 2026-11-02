import CloudKit
import Foundation

/// Conversion between sync data and CloudKit records. Only `UsageSnapshot`, its latest failure and the display setting are ever stored.
public enum CloudRecords {
    public static let zoneID = CKRecordZone.ID(zoneName: "Usage", ownerName: CKCurrentUserDefaultName)
    static let snapshotType = "UsageSnapshot"
    static let displayType = "DisplaySettings"
    static let displayName = "display"

    public static func snapshotID(_ provider: Provider) -> CKRecord.ID { CKRecord.ID(recordName: provider.rawValue, zoneID: zoneID) }
    public static let displayID = CKRecord.ID(recordName: displayName, zoneID: zoneID)

    public static func record(for snapshot: UsageSnapshot, existing: CKRecord? = nil) throws -> CKRecord {
        let record = existing ?? CKRecord(recordType: snapshotType, recordID: snapshotID(snapshot.provider))
        record["json"] = try JSONEncoder().encode(snapshot)
        record["fetchedAt"] = snapshot.fetchedAt
        record["issue"] = nil
        return record
    }
    /// The latest failed fetch, kept beside the last good snapshot so the iPhone can say why it is old. A good snapshot clears it.
    public static func record(issue: FetchStatus, provider: Provider, existing: CKRecord? = nil) throws -> CKRecord {
        let record = existing ?? CKRecord(recordType: snapshotType, recordID: snapshotID(provider))
        record["issue"] = try JSONEncoder().encode(issue)
        return record
    }
    public static func issue(from record: CKRecord) -> FetchStatus? {
        (record["issue"] as? Data).flatMap { try? JSONDecoder().decode(FetchStatus.self, from: $0) }
    }
    public static func snapshot(from record: CKRecord) -> UsageSnapshot? {
        guard record.recordType == snapshotType, let json = record["json"] as? Data else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: json)
    }
    public static func fetchedAt(of record: CKRecord) -> Date? { record["fetchedAt"] as? Date }
    /// A Mac never overwrites newer data, so a second Mac with a stale view cannot roll the iPhone back.
    public static func shouldWrite(local: Date, remote: Date?) -> Bool { remote.map { local > $0 } ?? true }

    public static func record(for services: DisplayServices, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: displayType, recordID: displayID)
        record["services"] = services.rawValue
        return record
    }
    public static func services(from record: CKRecord) -> DisplayServices? {
        guard record.recordType == displayType, let value = record["services"] as? String else { return nil }
        return DisplayServices(rawValue: value)
    }
}
