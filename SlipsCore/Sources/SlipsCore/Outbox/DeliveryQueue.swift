import Foundation
import GRDB

/// The outbox rows as the screens and the save path see them: counts, manual retry, re-queue after
/// an edit, backlog when a destination is turned on. Delivering is the `Outbox` actor's job.
public struct DeliveryQueue: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public struct Summary: Sendable, Equatable {
        public var pending = 0
        public var inFlight = 0
        public var done = 0
        public var failed = 0
        public var needsAuth = 0
        public var lastErrorCode: String?

        public init() {}

        /// Waiting to leave the phone, whatever the reason.
        public var waiting: Int { pending + inFlight + failed + needsAuth }
    }

    /// Counts per destination of a profile.
    public func observeSummaries(profile: UUID) -> AsyncThrowingStream<[UUID: Summary], any Error> {
        database.observe { db in try Self.summaries(profile: profile, in: db) }
    }

    public func summaries(profile: UUID) throws -> [UUID: Summary] {
        try database.writer.read { db in try Self.summaries(profile: profile, in: db) }
    }

    static func summaries(profile: UUID, in db: Database) throws -> [UUID: Summary] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT d.destination_id, d.status, count(*) AS n, max(d.last_error_code) AS code FROM deliveries d
            JOIN destinations t ON t.id = d.destination_id
            WHERE t.profile_id = ? GROUP BY d.destination_id, d.status
            """, arguments: [profile])
        var result: [UUID: Summary] = [:]
        for row in rows {
            let id: UUID = row["destination_id"]
            let n: Int = row["n"]
            var s = result[id] ?? Summary()
            switch DeliveryStatus(rawValue: row["status"]) {
            case .pending: s.pending = n
            case .inFlight: s.inFlight = n
            case .done: s.done = n
            case .failed: s.failed = n; s.lastErrorCode = row["code"]
            case .needsAuth: s.needsAuth = n; s.lastErrorCode = s.lastErrorCode ?? row["code"]
            case nil: break
            }
            result[id] = s
        }
        return result
    }

    /// Deliveries of one slip, for its detail screen.
    public func deliveries(slip: UUID) throws -> [Delivery] {
        try database.writer.read { db in try Delivery.filter(Column("slip_id") == slip).fetchAll(db) }
    }

    public func observeDeliveries(slip: UUID) -> AsyncThrowingStream<[Delivery], any Error> {
        database.observe { db in try Delivery.filter(Column("slip_id") == slip).fetchAll(db) }
    }

    /// "Retry now": failed and signed-out rows of a destination go back to pending, due now, with a
    /// fresh attempt count; pending rows become due now.
    public func retry(destination: UUID, now: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE deliveries SET status = 'pending', attempts = CASE WHEN status = 'pending' THEN attempts ELSE 0 END,
                    next_attempt_at = ?, updated_at = ?
                WHERE destination_id = ? AND status IN ('pending', 'failed', 'needs_auth')
                """, arguments: [now, now, destination])
        }
    }

    public func retry(slip: UUID, destination: UUID, now: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE deliveries SET status = 'pending', attempts = 0, next_attempt_at = ?, updated_at = ?
                WHERE slip_id = ? AND destination_id = ? AND status IN ('pending', 'failed', 'needs_auth')
                """, arguments: [now, now, slip, destination])
        }
    }

    /// When a destination is turned on, the profile's filed slips it does not have yet are queued.
    @discardableResult
    public func enqueueBacklog(destination: UUID, now: Date = Date()) throws -> Int {
        try database.writer.write { db in
            guard let d = try Destination.fetchOne(db, id: destination), d.enabled, d.type != .library else { return 0 }
            try db.execute(sql: """
                INSERT OR IGNORE INTO deliveries (slip_id, destination_id, status, attempts, next_attempt_at, updated_at)
                SELECT id, ?, 'pending', 0, ?, ? FROM slips WHERE profile_id = ? AND status = 'ready'
                """, arguments: [destination, now, now, d.profileId])
            return db.changesCount
        }
    }

    /// Tokens of a naming rule that depend on the slip's fields or classification.
    static let fieldTokens = ["{year}", "{month}", "{day}", "{date}", "{kind}", "{business}", "{subcategory}",
                              "{merchant}", "{total}", "{currency}", "{payment}"]

    /// After an edit of a filed slip: destinations that keep a JSON sidecar, or name the file from the
    /// slip's fields, get the slip again. The PDF itself never changes after capture.
    static func requeueAfterEdit(old: Slip, new: Slip, now: Date, in db: Database) throws {
        guard old.status == .ready, Self.deliveredFieldsDiffer(old, new) else { return }
        let rows = try Delivery.filter(Column("slip_id") == new.id && Column("status") == DeliveryStatus.done.rawValue).fetchAll(db)
        for var row in rows {
            guard let d = try Destination.fetchOne(db, id: row.destinationId) else { continue }
            let usesFields = fieldTokens.contains { d.namingRule.contains($0) }
            guard d.keepsSidecar || usesFields else { continue }
            row.status = .pending
            row.attempts = 0
            row.nextAttemptAt = now
            row.updatedAt = now
            try row.update(db)
        }
    }

    static func deliveredFieldsDiffer(_ a: Slip, _ b: Slip) -> Bool {
        a.merchant != b.merchant || a.txnDate != b.txnDate || a.currency != b.currency || a.subtotal != b.subtotal
            || a.gst != b.gst || a.qst != b.qst || a.hst != b.hst || a.tip != b.tip || a.total != b.total
            || a.supplierGstNo != b.supplierGstNo || a.supplierQstNo != b.supplierQstNo || a.kind != b.kind
            || a.enterpriseId != b.enterpriseId || a.subcategoryId != b.subcategoryId
            || a.paymentMethodId != b.paymentMethodId || a.notes != b.notes
    }
}

extension Destination {
    /// Config key for "write a JSON sidecar next to the PDF" (`"1"` = on).
    public static let sidecarKey = "sidecar"

    public var keepsSidecar: Bool { config[Self.sidecarKey] == "1" }
}

extension DeliveryQueue {
    /// Deliveries of every profile not yet done, for the App Intent's answer and the offline note.
    public func waitingCount() throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT count(*) FROM deliveries d JOIN destinations t ON t.id = d.destination_id
                WHERE d.status != 'done' AND t.enabled = 1
                """) ?? 0
        }
    }
}
