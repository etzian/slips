import Foundation
import GRDB

/// The one database. A `DatabasePool` in WAL mode under Application Support in the app, an in-memory
/// queue in tests. Every write goes through `SlipsCore`; screens never import GRDB.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = false
        #endif
        Migrations.register(in: &migrator)
        try migrator.migrate(writer)
    }

    /// The app's database file, `<directory>/slips.sqlite`, created with its directory if missing.
    public static func onDisk(directory: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("slips.sqlite")
        let pool = try DatabasePool(path: url.path, configuration: configuration())
        return try AppDatabase(pool)
    }

    /// An empty in-memory database with the full schema, for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration()))
    }

    static func configuration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.label = "slips"
        return config
    }

    /// Names of the migrations applied, oldest first.
    public func appliedMigrations() throws -> [String] {
        try writer.read { db in
            var migrator = DatabaseMigrator()
            Migrations.register(in: &migrator)
            return try migrator.appliedMigrations(db)
        }
    }
}

// MARK: - Profiles and seeding

extension AppDatabase {
    /// Names given to the seeded destinations; the app passes them translated.
    public struct SeedNames: Sendable {
        public var library: String
        public var icloud: String
        public init(library: String, icloud: String) {
            self.library = library
            self.icloud = icloud
        }
        public static let english = SeedNames(library: "Library", icloud: "iCloud Drive")
    }

    /// Creates a profile with fin's seed sub-categories and the destinations `library` (on) and
    /// `icloud` (off), in one transaction.
    @discardableResult
    public func createProfile(name: String, seedNames: SeedNames = .english, now: Date = Date()) throws -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = Profile(name: trimmed, createdAt: now)
        try writer.write { db in
            try profile.insert(db)
            try Self.seed(profile: profile.id, names: seedNames, in: db)
        }
        return profile
    }

    static func seed(profile: UUID, names: SeedNames, in db: Database) throws {
        var order = 0
        for group in Seed.subcategoryKeys {
            for key in group.keys {
                try Subcategory(profileId: profile, kind: group.kind, nameKey: key, sortOrder: order).insert(db)
                order += 1
            }
        }
        // The library is the source of truth and always on; every other destination starts off.
        try Destination(profileId: profile, type: .library, name: names.library, enabled: true).insert(db)
        try Destination(profileId: profile, type: .icloud, name: names.icloud, enabled: false).insert(db)
    }

    public func profiles() throws -> [Profile] {
        try writer.read { db in try Profile.order(Column("created_at")).fetchAll(db) }
    }
}
