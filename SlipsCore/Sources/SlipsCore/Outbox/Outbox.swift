import Foundation
import GRDB

/// The outbox scheduler (plan §6). Drains due `deliveries` rows for reachable destinations, one at a
/// time per destination and at most three destinations at once. Every state change is written to the
/// database before the next step, so a crash at any point loses nothing and duplicates nothing:
/// `in_flight` rows older than 15 minutes go back to `pending`, and every attempt asks the
/// destination whether the slip is already there before writing it.
public actor Outbox {
    public typealias AdapterProvider = @Sendable (Destination) -> (any DestinationAdapter)?

    /// Delay before attempt n+1 after n failures: 30 s, 2 min, 10 min, 1 h, then every 6 h.
    public static let backoff: [TimeInterval] = [30, 120, 600, 3600, 21_600]
    public static let maxAttempts = 20
    public static let staleInFlight: TimeInterval = 15 * 60
    public static let globalConcurrency = 3

    let database: AppDatabase
    let files: FileStore
    let adapters: AdapterProvider
    let now: @Sendable () -> Date
    let network: @Sendable () -> NetworkConditions

    private var draining = false
    private var drainAgain = false

    public init(database: AppDatabase, files: FileStore, adapters: @escaping AdapterProvider,
                network: @escaping @Sendable () -> NetworkConditions = { .unrestricted },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.files = files
        self.adapters = adapters
        self.network = network
        self.now = now
    }

    public struct DrainReport: Sendable, Equatable {
        public var delivered = 0
        public var alreadyThere = 0
        public var retryLater = 0
        public var failed = 0
        public var needsAuth = 0
        public var skippedDestinations = 0

        public init() {}

        mutating func add(_ other: DrainReport) {
            delivered += other.delivered
            alreadyThere += other.alreadyThere
            retryLater += other.retryLater
            failed += other.failed
            needsAuth += other.needsAuth
            skippedDestinations += other.skippedDestinations
        }
    }

    /// Delivers everything that is due. A call while a drain runs makes that drain go round once more
    /// instead of starting a second one.
    @discardableResult
    public func drain() async -> DrainReport {
        if draining {
            drainAgain = true
            return DrainReport()
        }
        draining = true
        defer { draining = false }
        var total = DrainReport()
        repeat {
            drainAgain = false
            total.add(await drainOnce())
        } while drainAgain
        return total
    }

    /// The earliest moment a pending row becomes due, for the app's next timer.
    public func nextDueDate() throws -> Date? {
        try database.writer.read { db in
            try Date.fetchOne(db, sql: """
                SELECT min(d.next_attempt_at) FROM deliveries d
                JOIN destinations t ON t.id = d.destination_id
                WHERE d.status = 'pending' AND t.enabled = 1
                """)
        }
    }

    // MARK: - One pass

    func drainOnce() async -> DrainReport {
        let start = now()
        do {
            try recoverStaleInFlight(at: start)
        } catch {
            return DrainReport()
        }
        let due: [UUID: [Delivery]]
        let destinations: [UUID: Destination]
        do {
            (due, destinations) = try dueByDestination(at: start)
        } catch {
            return DrainReport()
        }
        let conditions = network()
        var report = DrainReport()
        var work: [(Destination, [Delivery], any DestinationAdapter)] = []
        for (id, rows) in due {
            guard let destination = destinations[id], conditions.allows(destination),
                  let adapter = adapters(destination) else {
                report.skippedDestinations += 1
                continue
            }
            work.append((destination, rows, adapter))
        }
        work.sort { $0.0.name < $1.0.name }

        await withTaskGroup(of: DrainReport.self) { group in
            var next = 0
            func startNext() {
                guard next < work.count else { return }
                let (destination, rows, adapter) = work[next]
                next += 1
                group.addTask { await self.drain(destination, rows: rows, adapter: adapter) }
            }
            for _ in 0..<Self.globalConcurrency { startNext() }
            while let r = await group.next() {
                report.add(r)
                startNext()
            }
        }
        return report
    }

    /// One destination, its rows in order, one at a time.
    func drain(_ destination: Destination, rows: [Delivery], adapter: any DestinationAdapter) async -> DrainReport {
        var report = DrainReport()
        switch await adapter.probe() {
        case .unreachable:
            report.skippedDestinations += 1
            return report
        case .needsAuth:
            report.needsAuth += (try? markNeedsAuth(destination.id)) ?? 0
            return report
        case .reachable:
            break
        }
        for row in rows {
            let outcome = await attempt(row, destination: destination, adapter: adapter)
            switch outcome {
            case .delivered: report.delivered += 1
            case .alreadyThere: report.alreadyThere += 1
            case .retryLater: report.retryLater += 1
            case .failed: report.failed += 1
            case .needsAuth:
                report.needsAuth += 1 + ((try? markNeedsAuth(destination.id)) ?? 0)
                return report
            case .skipped: break
            }
        }
        return report
    }

    enum Outcome { case delivered, alreadyThere, retryLater, failed, needsAuth, skipped }

    func attempt(_ row: Delivery, destination: Destination, adapter: any DestinationAdapter) async -> Outcome {
        // Claim the row; another drain (or process) may have taken it since the selection.
        guard let claimed = try? claim(row) else { return .skipped }
        let item: DeliveryItem
        do {
            item = try makeItem(claimed, destination: destination)
        } catch let error as DeliveryError {
            return (try? record(error, for: claimed)) ?? .skipped
        } catch {
            return (try? record(.permanent("item"), for: claimed)) ?? .skipped
        }
        do {
            if let ref = try await adapter.exists(item) {
                try markDone(claimed, ref: ref, sha: item.sha256)
                return .alreadyThere
            }
            let ref = try await adapter.deliver(item)
            try markDone(claimed, ref: ref, sha: item.sha256)
            return .delivered
        } catch let error as DeliveryError {
            return (try? record(error, for: claimed)) ?? .skipped
        } catch is CancellationError {
            return (try? record(.transient("cancelled"), for: claimed)) ?? .skipped
        } catch {
            return (try? record(.transient("error"), for: claimed)) ?? .skipped
        }
    }

    // MARK: - Database steps

    /// `in_flight` rows untouched for 15 minutes belong to a drain that died: back to `pending`, due now.
    func recoverStaleInFlight(at date: Date) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE deliveries SET status = 'pending', next_attempt_at = ?, updated_at = ?
                WHERE status = 'in_flight' AND updated_at < ?
                """, arguments: [date, date, date.addingTimeInterval(-Self.staleInFlight)])
        }
    }

    /// Pending rows that are due, of ready slips, for enabled destinations, oldest slip first.
    func dueByDestination(at date: Date) throws -> ([UUID: [Delivery]], [UUID: Destination]) {
        try database.writer.read { db in
            let rows = try Delivery.fetchAll(db, sql: """
                SELECT d.* FROM deliveries d
                JOIN destinations t ON t.id = d.destination_id
                JOIN slips s ON s.id = d.slip_id
                WHERE d.status = 'pending' AND t.enabled = 1 AND s.status = 'ready'
                  AND (d.next_attempt_at IS NULL OR d.next_attempt_at <= ?)
                ORDER BY s.captured_at, d.slip_id
                """, arguments: [date])
            let ids = Set(rows.map(\.destinationId))
            let destinations = try Destination.filter(keys: ids).fetchAll(db)
            return (Dictionary(grouping: rows, by: \.destinationId), Dictionary(uniqueKeysWithValues: destinations.map { ($0.id, $0) }))
        }
    }

    func claim(_ row: Delivery) throws -> Delivery? {
        let stamp = now()
        return try database.writer.write { db in
            try db.execute(sql: """
                UPDATE deliveries SET status = 'in_flight', updated_at = ?
                WHERE slip_id = ? AND destination_id = ? AND status = 'pending'
                """, arguments: [stamp, row.slipId, row.destinationId])
            guard db.changesCount == 1 else { return nil }
            return try Delivery.fetchOne(db, key: ["slip_id": row.slipId, "destination_id": row.destinationId])
        }
    }

    /// Reads the slip and checks its file still matches the hash recorded at capture.
    func makeItem(_ row: Delivery, destination: Destination) throws -> DeliveryItem {
        guard let slip = try database.writer.read({ db in try Slip.fetchOne(db, id: row.slipId) }) else {
            throw DeliveryError.permanent("slip_missing")
        }
        let url = files.url(for: slip.pdfPath)
        guard let data = try? Data(contentsOf: url) else { throw DeliveryError.permanent("file_missing") }
        let sha = Hashing.sha256Hex(data)
        guard sha == slip.pdfSha256 else { throw DeliveryError.permanent("hash_mismatch") }
        let labels = try database.writer.read { db in try SlipLabels.resolve(for: slip, in: db) }
        return DeliveryItem(slip: slip, destination: destination, pdfURL: url, sha256: sha, byteCount: data.count,
                            previousRef: row.remoteRef.map(RemoteRef.init), labels: labels)
    }

    func markDone(_ row: Delivery, ref: RemoteRef, sha: String) throws {
        let stamp = now()
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE deliveries SET status = 'done', remote_ref = ?, delivered_sha256 = ?, last_error_code = NULL,
                    next_attempt_at = NULL, updated_at = ?
                WHERE slip_id = ? AND destination_id = ? AND status = 'in_flight'
                """, arguments: [ref.value, sha, stamp, row.slipId, row.destinationId])
        }
    }

    func record(_ error: DeliveryError, for row: Delivery) throws -> Outcome {
        let stamp = now()
        let attempts = row.attempts + 1
        let (status, code, next): (DeliveryStatus, String, Date?)
        let outcome: Outcome
        switch error {
        case .unauthorized:
            (status, code, next) = (.needsAuth, "unauthorized", nil)
            outcome = .needsAuth
        case .permanent(let c):
            (status, code, next) = (.failed, c, nil)
            outcome = .failed
        case .transient(let c) where attempts >= Self.maxAttempts:
            (status, code, next) = (.failed, c, nil)
            outcome = .failed
        case .transient(let c):
            (status, code, next) = (.pending, c, stamp.addingTimeInterval(Self.delay(afterAttempts: attempts)))
            outcome = .retryLater
        }
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE deliveries SET status = ?, attempts = ?, last_error_code = ?, next_attempt_at = ?, updated_at = ?
                WHERE slip_id = ? AND destination_id = ? AND status = 'in_flight'
                """, arguments: [status, attempts, code, next, stamp, row.slipId, row.destinationId])
        }
        return outcome
    }

    /// Stops a destination after a refused sign-in: its pending rows wait in `needs_auth`.
    func markNeedsAuth(_ destination: UUID) throws -> Int {
        let stamp = now()
        return try database.writer.write { db in
            try db.execute(sql: """
                UPDATE deliveries SET status = 'needs_auth', last_error_code = 'unauthorized', updated_at = ?
                WHERE destination_id = ? AND status = 'pending'
                """, arguments: [stamp, destination])
            return db.changesCount
        }
    }

    public static func delay(afterAttempts attempts: Int) -> TimeInterval {
        backoff[min(max(attempts, 1), backoff.count) - 1]
    }
}
