import Foundation
import GRDB
import Testing
@testable import SlipsCore

@Suite struct EraserTests {
    @Test func eraseLeavesNoFileOrRow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase.onDisk(directory: dir)
        let files = FileStore(root: dir)
        let profile = try db.createProfile(name: "P")
        let capture = CaptureStore(database: db, files: files)
        var slip = try capture.save(pdf: Data("%PDF".utf8), pageCount: 1, profile: profile.id)
        slip.merchant = "Fake"
        try db.writer.write { [slip] in try slip.update($0) }
        try ReferenceData(database: db).addEnterprise(profile: profile.id, name: "Shop")
        let nas = Destination(profileId: profile.id, type: .webdav, name: "NAS", enabled: true)
        try db.writer.write { db in
            try nas.insert(db)
            try Delivery(slipId: slip.id, destinationId: nas.id).insert(db)
            try MerchantMemory(profileId: profile.id, merchantNorm: "fake").insert(db)
        }

        let erased = try Eraser(database: db, files: files).eraseAll()
        #expect(erased.contains(nas.id))
        let counts = try db.writer.read { db in
            try ["profiles", "enterprises", "subcategories", "payment_methods", "slips", "merchant_memory", "destinations",
                 "deliveries"].map { try Int.fetchOne(db, sql: "SELECT count(*) FROM \($0)")! }
        }
        #expect(counts.allSatisfy { $0 == 0 })
        #expect(try db.writer.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM slips_fts WHERE slips_fts MATCH 'fake'") } == 0)
        #expect(!FileManager.default.fileExists(atPath: files.url(for: "Slips").path))
        // The app starts over with a fresh profile.
        try db.createProfile(name: "Again")
        #expect(try db.profiles().count == 1)
    }
}
