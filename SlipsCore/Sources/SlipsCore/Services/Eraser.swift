import Foundation
import GRDB

/// "Erase all data on this iPhone": every row and every slip file. Copies already delivered to
/// destinations are not touched (they are the user's, wherever they went). Secrets are the app's job
/// (Keychain), with the destination ids this returns.
public struct Eraser: Sendable {
    public let database: AppDatabase
    public let files: FileStore

    public init(database: AppDatabase, files: FileStore) {
        self.database = database
        self.files = files
    }

    /// Erases and returns the ids of the destinations that existed, for their Keychain items.
    @discardableResult
    public func eraseAll() throws -> [UUID] {
        let destinations = try database.writer.write { db -> [UUID] in
            let ids = try UUID.fetchAll(db, sql: "SELECT id FROM destinations")
            for table in ["deliveries", "merchant_memory", "slips", "destinations", "payment_methods", "subcategories",
                          "enterprises", "profiles"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            try db.execute(sql: "INSERT INTO slips_fts(slips_fts) VALUES ('rebuild')")
            return ids
        }
        let slips = files.url(for: "Slips")
        if FileManager.default.fileExists(atPath: slips.path) {
            try FileManager.default.removeItem(at: slips)
        }
        // Reclaim the space and leave nothing readable in free pages.
        try database.writer.vacuum()
        return destinations
    }
}
