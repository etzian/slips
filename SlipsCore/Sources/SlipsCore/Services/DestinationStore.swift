import Foundation
import GRDB

public enum DestinationError: Error, Equatable, Sendable {
    case blankName
    case unknownTokens([String])
    /// The library is the slip itself: always on, never removed.
    case libraryIsPermanent
    case notFound
}

/// Destinations of a profile: list, add, edit, turn on and off, remove.
public struct DestinationStore: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func observe(profile: UUID) -> AsyncThrowingStream<[Destination], any Error> {
        database.observe { db in try Self.list(profile: profile, in: db) }
    }

    public func list(profile: UUID) throws -> [Destination] {
        try database.writer.read { db in try Self.list(profile: profile, in: db) }
    }

    static func list(profile: UUID, in db: Database) throws -> [Destination] {
        // Library first, then by name.
        try Destination.filter(Column("profile_id") == profile)
            .order(Column("type") != DestinationType.library.rawValue, Column("name").collating(.localizedCaseInsensitiveCompare))
            .fetchAll(db)
    }

    /// Validates and saves; turning a destination on queues the profile's filed slips it lacks.
    public func save(_ destination: Destination, now: Date = Date()) throws {
        var d = destination
        d.name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.name.isEmpty else { throw DestinationError.blankName }
        d.namingRule = d.namingRule.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.namingRule.isEmpty { d.namingRule = Destination.defaultNamingRule }
        let unknown = NamingRule(d.namingRule).unknownTokens
        guard unknown.isEmpty else { throw DestinationError.unknownTokens(unknown) }
        if d.type == .library { d.enabled = true }
        let saved = d
        try database.writer.write { db in
            let wasEnabled = try Destination.fetchOne(db, id: saved.id)?.enabled ?? false
            try saved.save(db)
            if saved.enabled && !wasEnabled && saved.type != .library {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO deliveries (slip_id, destination_id, status, attempts, next_attempt_at, updated_at)
                    SELECT id, ?, 'pending', 0, ?, ? FROM slips WHERE profile_id = ? AND status = 'ready'
                    """, arguments: [saved.id, now, now, saved.profileId])
            }
        }
    }

    public func setEnabled(_ id: UUID, _ enabled: Bool, now: Date = Date()) throws {
        guard var d = try database.writer.read({ db in try Destination.fetchOne(db, id: id) }) else { throw DestinationError.notFound }
        if d.type == .library && !enabled { throw DestinationError.libraryIsPermanent }
        d.enabled = enabled
        try save(d, now: now)
    }

    /// Removes a destination and its outbox rows. Copies already delivered stay where they are.
    public func remove(_ id: UUID) throws {
        try database.writer.write { db in
            guard let d = try Destination.fetchOne(db, id: id) else { throw DestinationError.notFound }
            guard d.type != .library else { throw DestinationError.libraryIsPermanent }
            try d.delete(db)
        }
    }
}
