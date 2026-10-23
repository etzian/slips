import Foundation
import GRDB

public enum SaveError: Error, Equatable, Sendable {
    /// A blocking check is open (total missing, file missing…).
    case blockingCheck(String)
    /// Kind and sub-category are needed to file the slip; a business slip also needs its business.
    case classificationIncomplete
}

/// Reading and saving slips after capture.
public struct SlipStore: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func slip(_ id: UUID) throws -> Slip? {
        try database.writer.read { db in try Slip.fetchOne(db, id: id) }
    }

    public func observeSlip(_ id: UUID) -> AsyncThrowingStream<Slip?, any Error> {
        database.observe { db in try Slip.fetchOne(db, id: id) }
    }

    /// Pre-fill for the review screen.
    public func suggestion(for slip: Slip) throws -> Classification {
        try database.writer.read { db in
            let reference = try ReferenceData.snapshot(profile: slip.profileId, in: db)
            let norm = slip.merchant.map(MerchantName.normalize) ?? ""
            let memory = norm.isEmpty ? nil : try MerchantMemory
                .filter(Column("profile_id") == slip.profileId && Column("merchant_norm") == norm).fetchOne(db)
            let lastUsed = try MerchantMemory.filter(Column("profile_id") == slip.profileId)
                .order(Column("last_used_at").desc).fetchOne(db)
            return Suggestions.suggest(cardLast4: slip.extraction?.cardLast4?.value, merchant: slip.merchant,
                                       reference: reference, memory: memory, lastUsed: lastUsed)
        }
    }

    /// Saves the fields without filing: a draft stays a draft and gets no delivery.
    public func saveDraft(_ slip: Slip, now: Date = Date()) throws {
        var s = slip
        s.updatedAt = now
        try database.writer.write { db in try s.update(db) }
    }

    /// Files the slip: status `ready`, merchant memory updated, one pending delivery per enabled
    /// destination of its profile (the library is the slip itself, so it gets none). One transaction.
    public func markReady(_ slip: Slip, now: Date = Date()) throws {
        if let blocking = slip.decodedChecks.first(where: { $0.severity == .blocking }) {
            throw SaveError.blockingCheck(blocking.code)
        }
        guard slip.kind != nil, slip.subcategoryId != nil, slip.kind != .enterprise || slip.enterpriseId != nil else {
            throw SaveError.classificationIncomplete
        }
        var s = slip
        if s.kind != .enterprise { s.enterpriseId = nil }
        s.status = .ready
        s.updatedAt = now
        let saved = s
        try database.writer.write { db in
            try saved.update(db)
            try Self.remember(saved, now: now, in: db)
            let destinations = try Destination
                .filter(Column("profile_id") == saved.profileId && Column("enabled") == true && Column("type") != DestinationType.library.rawValue)
                .fetchAll(db)
            for d in destinations {
                let exists = try Delivery.filter(Column("slip_id") == saved.id && Column("destination_id") == d.id).fetchCount(db) > 0
                if !exists {
                    try Delivery(slipId: saved.id, destinationId: d.id, nextAttemptAt: now, updatedAt: now).insert(db)
                }
            }
        }
    }

    static func remember(_ slip: Slip, now: Date, in db: Database) throws {
        guard let merchant = slip.merchant else { return }
        let norm = MerchantName.normalize(merchant)
        guard !norm.isEmpty else { return }
        var memory = try MerchantMemory.filter(Column("profile_id") == slip.profileId && Column("merchant_norm") == norm).fetchOne(db)
            ?? MerchantMemory(profileId: slip.profileId, merchantNorm: norm, uses: 0, lastUsedAt: now)
        memory.kind = slip.kind
        memory.enterpriseId = slip.enterpriseId
        memory.subcategoryId = slip.subcategoryId
        memory.paymentMethodId = slip.paymentMethodId
        memory.uses += 1
        memory.lastUsedAt = now
        try memory.save(db)
    }
}
