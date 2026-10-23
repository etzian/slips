import Foundation
import GRDB

/// Why a reference-data change was refused. The app maps each case to a translated message.
public enum ValidationError: Error, Equatable, Sendable {
    case blankName
    /// A last four must be exactly four digits.
    case invalidLastFour
    /// A currency is a three-letter ISO 4217 code.
    case invalidCurrency
    /// fin never archives the transfer keys (`any.transfer`, `any.card_payment`).
    case archiveRefused
    case notFound
}

/// What happened when the user removed an item: deleted when nothing pointed at it, archived otherwise.
public enum RemovalOutcome: Equatable, Sendable {
    case deleted, archived
}

/// Profiles, businesses, sub-categories and payment methods, with the validation rules of fin.
public struct ReferenceData: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    static func cleanName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.blankName }
        return trimmed
    }

    // MARK: Profiles

    @discardableResult
    public func createProfile(name: String, seedNames: AppDatabase.SeedNames = .english) throws -> Profile {
        try database.createProfile(name: try Self.cleanName(name), seedNames: seedNames)
    }

    public func renameProfile(_ id: UUID, to name: String) throws {
        let clean = try Self.cleanName(name)
        try database.writer.write { db in
            guard var p = try Profile.fetchOne(db, id: id) else { throw ValidationError.notFound }
            p.name = clean
            try p.update(db)
        }
    }

    public func observeProfiles() -> AsyncThrowingStream<[Profile], any Error> {
        database.observe { db in try Profile.order(Column("created_at")).fetchAll(db) }
    }

    // MARK: Businesses

    @discardableResult
    public func addEnterprise(profile: UUID, name: String) throws -> Enterprise {
        let e = Enterprise(profileId: profile, name: try Self.cleanName(name))
        try database.writer.write { db in try e.insert(db) }
        return e
    }

    public func renameEnterprise(_ id: UUID, to name: String) throws {
        let clean = try Self.cleanName(name)
        try database.writer.write { db in
            guard var e = try Enterprise.fetchOne(db, id: id) else { throw ValidationError.notFound }
            e.name = clean
            try e.update(db)
        }
    }

    /// Deletes a business nothing points at; archives it otherwise.
    @discardableResult
    public func removeEnterprise(_ id: UUID, now: Date = Date()) throws -> RemovalOutcome {
        try database.writer.write { db in
            guard var e = try Enterprise.fetchOne(db, id: id) else { throw ValidationError.notFound }
            let used = try Self.count(db, "SELECT count(*) FROM slips WHERE enterprise_id = ?", id)
                + Self.count(db, "SELECT count(*) FROM payment_methods WHERE default_enterprise_id = ?", id)
                + Self.count(db, "SELECT count(*) FROM merchant_memory WHERE enterprise_id = ?", id)
            if used == 0 {
                try e.delete(db)
                return .deleted
            }
            e.archivedAt = now
            try e.update(db)
            return .archived
        }
    }

    public func unarchiveEnterprise(_ id: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE enterprises SET archived_at = NULL WHERE id = ?", arguments: [id])
        }
    }

    public func observeEnterprises(profile: UUID) -> AsyncThrowingStream<[Enterprise], any Error> {
        database.observe { db in
            try Enterprise.filter(Column("profile_id") == profile)
                .order(Column("archived_at") != nil, Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
        }
    }

    // MARK: Sub-categories

    @discardableResult
    public func addSubcategory(profile: UUID, kind: SubcategoryKind, name: String) throws -> Subcategory {
        let clean = try Self.cleanName(name)
        return try database.writer.write { db in
            let next = try Int.fetchOne(db, sql: "SELECT coalesce(max(sort_order), -1) + 1 FROM subcategories WHERE profile_id = ?",
                                        arguments: [profile]) ?? 0
            let s = Subcategory(profileId: profile, kind: kind, customName: clean, sortOrder: next)
            try s.insert(db)
            return s
        }
    }

    /// Sets the user's own name; a blank name on a seeded row goes back to the translated name.
    public func renameSubcategory(_ id: UUID, to name: String) throws {
        try database.writer.write { db in
            guard var s = try Subcategory.fetchOne(db, id: id) else { throw ValidationError.notFound }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                guard s.nameKey != nil else { throw ValidationError.blankName }
                s.customName = nil
            } else {
                s.customName = trimmed
            }
            try s.update(db)
        }
    }

    /// Deletes an unused custom sub-category, archives a used or seeded one; refuses the transfer keys.
    @discardableResult
    public func removeSubcategory(_ id: UUID, now: Date = Date()) throws -> RemovalOutcome {
        try database.writer.write { db in
            guard var s = try Subcategory.fetchOne(db, id: id) else { throw ValidationError.notFound }
            if let key = s.nameKey, Seed.transferKeys.contains(key) { throw ValidationError.archiveRefused }
            let used = try Self.count(db, "SELECT count(*) FROM slips WHERE subcategory_id = ?", id)
                + Self.count(db, "SELECT count(*) FROM merchant_memory WHERE subcategory_id = ?", id)
            // Seeded keys stay so a later link to fin still maps by key.
            if used == 0 && s.nameKey == nil {
                try s.delete(db)
                return .deleted
            }
            s.archivedAt = now
            try s.update(db)
            return .archived
        }
    }

    public func unarchiveSubcategory(_ id: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE subcategories SET archived_at = NULL WHERE id = ?", arguments: [id])
        }
    }

    public func observeSubcategories(profile: UUID) -> AsyncThrowingStream<[Subcategory], any Error> {
        database.observe { db in
            try Subcategory.filter(Column("profile_id") == profile).order(Column("sort_order")).fetchAll(db)
        }
    }

    // MARK: Payment methods

    /// Validates and inserts or updates a payment method.
    public func savePaymentMethod(_ method: PaymentMethod) throws {
        var m = method
        m.name = try Self.cleanName(m.name)
        if let l4 = m.last4?.trimmingCharacters(in: .whitespaces), !l4.isEmpty {
            guard l4.count == 4, l4.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw ValidationError.invalidLastFour }
            m.last4 = l4
        } else {
            m.last4 = nil
        }
        m.currency = m.currency.trimmingCharacters(in: .whitespaces).uppercased()
        guard m.currency.count == 3, m.currency.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw ValidationError.invalidCurrency
        }
        if m.defaultKind != .enterprise { m.defaultEnterpriseId = nil }
        let saved = m
        try database.writer.write { db in try saved.save(db) }
    }

    @discardableResult
    public func removePaymentMethod(_ id: UUID, now: Date = Date()) throws -> RemovalOutcome {
        try database.writer.write { db in
            guard var m = try PaymentMethod.fetchOne(db, id: id) else { throw ValidationError.notFound }
            let used = try Self.count(db, "SELECT count(*) FROM slips WHERE payment_method_id = ?", id)
                + Self.count(db, "SELECT count(*) FROM merchant_memory WHERE payment_method_id = ?", id)
            if used == 0 {
                try m.delete(db)
                return .deleted
            }
            m.archivedAt = now
            try m.update(db)
            return .archived
        }
    }

    public func unarchivePaymentMethod(_ id: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE payment_methods SET archived_at = NULL WHERE id = ?", arguments: [id])
        }
    }

    public func observePaymentMethods(profile: UUID) -> AsyncThrowingStream<[PaymentMethod], any Error> {
        database.observe { db in
            try PaymentMethod.filter(Column("profile_id") == profile)
                .order(Column("archived_at") != nil, Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
        }
    }

    // MARK: Reads for pickers

    /// Everything a picker needs for one profile, active rows only.
    public func snapshot(profile: UUID) throws -> ReferenceSnapshot {
        try database.writer.read { db in try Self.snapshot(profile: profile, in: db) }
    }

    static func snapshot(profile: UUID, in db: Database) throws -> ReferenceSnapshot {
        ReferenceSnapshot(
            enterprises: try Enterprise.filter(Column("profile_id") == profile && Column("archived_at") == nil)
                .order(Column("name")).fetchAll(db),
            subcategories: try Subcategory.filter(Column("profile_id") == profile && Column("archived_at") == nil)
                .order(Column("sort_order")).fetchAll(db),
            paymentMethods: try PaymentMethod.filter(Column("profile_id") == profile && Column("archived_at") == nil)
                .order(Column("name")).fetchAll(db)
        )
    }

    static func count(_ db: Database, _ sql: String, _ id: UUID) throws -> Int {
        try Int.fetchOne(db, sql: sql, arguments: [id]) ?? 0
    }
}

/// Active reference rows of a profile, for pickers and suggestions.
public struct ReferenceSnapshot: Sendable, Equatable {
    public var enterprises: [Enterprise]
    public var subcategories: [Subcategory]
    public var paymentMethods: [PaymentMethod]

    public init(enterprises: [Enterprise] = [], subcategories: [Subcategory] = [], paymentMethods: [PaymentMethod] = []) {
        self.enterprises = enterprises
        self.subcategories = subcategories
        self.paymentMethods = paymentMethods
    }

    /// Sub-categories usable for `kind`: that kind's plus the `any` ones.
    public func subcategories(for kind: Kind) -> [Subcategory] {
        subcategories.filter { $0.kind == SubcategoryKind(kind) || $0.kind == .any }
    }
}
