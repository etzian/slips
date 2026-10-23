import Foundation
import GRDB
import Testing
@testable import SlipsCore

@Suite struct MigrationTests {
    @Test func migratesFromEmpty() throws {
        let db = try AppDatabase.inMemory()
        #expect(try db.appliedMigrations() == ["v1_initial"])
        let tables = try db.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
        for t in ["deliveries", "destinations", "enterprises", "merchant_memory", "payment_methods",
                  "profiles", "slips", "subcategories"] {
            #expect(tables.contains(t), "missing table \(t)")
        }
    }

    @Test func plannedIndexesExist() throws {
        let db = try AppDatabase.inMemory()
        let indexes = try db.writer.read { db in
            try ["deliveries", "slips", "merchant_memory"].map { try db.indexes(on: $0).map(\.columns) }
        }
        #expect(indexes[0].contains(["status", "next_attempt_at"]))
        #expect(indexes[1].contains(["profile_id", "txn_date"]))
        #expect(indexes[2].contains(["profile_id", "merchant_norm"]))
    }

    @Test func onDiskPoolUsesWAL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase.onDisk(directory: dir)
        let mode = try db.writer.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")
        #expect(try db.appliedMigrations() == ["v1_initial"])
    }
}

@Suite struct ConstraintTests {
    let db: AppDatabase
    let profile: Profile

    init() throws {
        db = try AppDatabase.inMemory()
        profile = try db.createProfile(name: "Test")
    }

    private func rejects(_ block: (Database) throws -> Void) -> Bool {
        do {
            try db.writer.write(block)
            return false
        } catch is DatabaseError {
            return true
        } catch {
            return false
        }
    }

    @Test func enumColumnsRejectUnknownValues() {
        #expect(rejects { db in
            try db.execute(sql: "UPDATE profiles SET mode = 'cloud'")
        })
        #expect(rejects { db in
            try db.execute(sql: "UPDATE subcategories SET kind = 'business'")
        })
        #expect(rejects { db in
            try db.execute(sql: "UPDATE destinations SET type = 'ftp'")
        })
    }

    @Test func lastFourMustBeFourDigits() throws {
        #expect(rejects { db in
            try PaymentMethod(profileId: profile.id, name: "Card", type: .creditCard, last4: "12a4").insert(db)
        })
        #expect(rejects { db in
            try PaymentMethod(profileId: profile.id, name: "Card", type: .creditCard, last4: "123").insert(db)
        })
        try db.writer.write { db in
            try PaymentMethod(profileId: profile.id, name: "Card", type: .creditCard, last4: "0042").insert(db)
        }
    }

    @Test func blankNamesRejected() {
        #expect(rejects { db in try Enterprise(profileId: profile.id, name: "   ").insert(db) })
        #expect(rejects { db in try Profile(name: "").insert(db) })
    }

    @Test func foreignKeysEnforced() {
        #expect(rejects { db in try Enterprise(profileId: UUID(), name: "Orphan").insert(db) })
        #expect(rejects { db in try Delivery(slipId: UUID(), destinationId: UUID()).insert(db) })
    }

    @Test func slipStatusAndHashChecked() throws {
        var slip = Slip(profileId: profile.id, pdfPath: "x", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        try db.writer.write { db in try slip.insert(db) }
        #expect(rejects { db in try db.execute(sql: "UPDATE slips SET status = 'sent'") })
        #expect(rejects { db in try db.execute(sql: "UPDATE slips SET page_count = 0") })
        slip.id = UUID()
        slip.pdfSha256 = "short"
        let bad = slip
        #expect(rejects { db in try bad.insert(db) })
    }

    @Test func deliveryIsUniquePerSlipAndDestination() throws {
        let slip = Slip(profileId: profile.id, pdfPath: "x", pdfSha256: String(repeating: "b", count: 64), pageCount: 1)
        let dest = try db.writer.read { try Destination.fetchOne($0)! }
        try db.writer.write { db in
            try slip.insert(db)
            try Delivery(slipId: slip.id, destinationId: dest.id).insert(db)
        }
        #expect(rejects { db in try Delivery(slipId: slip.id, destinationId: dest.id).insert(db) })
        #expect(rejects { db in try db.execute(sql: "UPDATE deliveries SET status = 'sent'") })
    }

    @Test func deletingAProfileCascades() throws {
        let slip = Slip(profileId: profile.id, pdfPath: "x", pdfSha256: String(repeating: "c", count: 64), pageCount: 1)
        try db.writer.write { db in
            let e = Enterprise(profileId: profile.id, name: "Shop")
            try e.insert(db)
            var s = slip
            s.kind = .enterprise
            s.enterpriseId = e.id
            try s.insert(db)
            let dest = try Destination.fetchOne(db)!
            try Delivery(slipId: s.id, destinationId: dest.id).insert(db)
            _ = try Profile.deleteOne(db, id: profile.id)
        }
        let counts = try db.writer.read { db in
            try ["slips", "enterprises", "subcategories", "destinations", "deliveries"].map {
                try Int.fetchOne(db, sql: "SELECT count(*) FROM \($0)")!
            }
        }
        #expect(counts.allSatisfy { $0 == 0 })
    }
}

@Suite struct SeedTests {
    @Test func newProfileGetsFinKeysAndDestinations() throws {
        let db = try AppDatabase.inMemory()
        let p = try db.createProfile(name: "  Home  ", seedNames: .init(library: "Bibliothèque", icloud: "iCloud Drive"))
        #expect(p.name == "Home")
        let (subs, dests) = try db.writer.read { db in
            (try Subcategory.filter(Column("profile_id") == p.id).order(Column("sort_order")).fetchAll(db),
             try Destination.filter(Column("profile_id") == p.id).fetchAll(db))
        }
        #expect(subs.compactMap(\.nameKey) == Seed.allKeys)
        #expect(subs.count == 27)
        #expect(subs.first { $0.nameKey == "any.transfer" }?.kind == .any)
        #expect(subs.filter { $0.kind == .enterprise }.count == 10)
        let library = try #require(dests.first { $0.type == .library })
        let icloud = try #require(dests.first { $0.type == .icloud })
        #expect(library.enabled && library.name == "Bibliothèque")
        #expect(!icloud.enabled)
        #expect(dests.count == 2)
    }

    @Test func seedKeysFollowFinsFormat() {
        for key in Seed.allKeys {
            let parts = key.split(separator: ".")
            #expect(parts.count == 2)
            #expect(SubcategoryKind(rawValue: String(parts[0])) != nil)
        }
        #expect(Set(Seed.allKeys).count == Seed.allKeys.count)
    }

    @Test func twoProfilesKeepSeparateSeeds() throws {
        let db = try AppDatabase.inMemory()
        try db.createProfile(name: "A")
        try db.createProfile(name: "B")
        #expect(try db.writer.read { try Subcategory.fetchCount($0) } == 54)
        #expect(try db.profiles().map(\.name) == ["A", "B"])
    }
}

@Suite struct RecordTests {
    @Test func slipRoundTripsEveryColumn() throws {
        let db = try AppDatabase.inMemory()
        let p = try db.createProfile(name: "P")
        var slip = Slip(profileId: p.id, pdfPath: FileStore.pdfPath(profile: p.id, slip: UUID()),
                        pdfSha256: String(repeating: "d", count: 64), pageCount: 2)
        slip.merchant = "Fake Hardware 0001"
        slip.txnDate = CalendarDay(year: 2026, month: 10, day: 20)
        slip.subtotal = 10_000
        slip.gst = 500
        slip.qst = 998
        slip.total = 11_498
        slip.kind = .personal
        let saved = slip
        try db.writer.write { db in try saved.insert(db) }
        let loaded = try db.writer.read { try Slip.fetchOne($0, id: saved.id) }
        #expect(loaded?.merchant == slip.merchant)
        #expect(loaded?.txnDate?.iso == "2026-10-20")
        #expect(loaded?.money(loaded?.total) == Money(minorUnits: 11_498, currency: "CAD"))
        #expect(loaded?.kind == .personal)
        let raw = try db.writer.read { try String.fetchOne($0, sql: "SELECT txn_date FROM slips") }
        #expect(raw == "2026-10-20")
    }

    @Test func destinationConfigIsJSON() throws {
        let db = try AppDatabase.inMemory()
        let p = try db.createProfile(name: "P")
        let d = Destination(profileId: p.id, type: .webdav, name: "NAS", config: ["base_url": "https://nas.local/dav"])
        try db.writer.write { try d.insert($0) }
        let raw = try db.writer.read { try String.fetchOne($0, sql: "SELECT config FROM destinations WHERE type = 'webdav'") }
        #expect(raw?.contains("nas.local") == true)
        #expect(try db.writer.read { try Destination.fetchOne($0, id: d.id) }?.config["base_url"] == "https://nas.local/dav")
    }

    @Test func calendarDayValidates() {
        #expect(CalendarDay(iso: "2026-02-29") == nil)
        #expect(CalendarDay(iso: "2024-02-29") != nil)
        #expect(CalendarDay(iso: "2026-13-01") == nil)
        #expect(CalendarDay(iso: "26-10-20") == nil)
        #expect(CalendarDay(year: 2026, month: 1, day: 2)! < CalendarDay(year: 2026, month: 10, day: 1)!)
    }

    @Test func moneyDecimal() {
        #expect(Money(minorUnits: 1234, currency: "CAD").decimal == Decimal(string: "12.34"))
    }
}

@Suite struct FileStoreTests {
    @Test func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileStore(root: root)
        let profile = UUID(), slip = UUID()
        let data = Data("%PDF-1.7 synthetic".utf8)
        let path = try store.writePDF(data, profile: profile, slip: slip)
        #expect(path == "Slips/\(profile.uuidString.lowercased())/\(slip.uuidString.lowercased())/slip.pdf")
        #expect(try store.read(path) == data)
        // Overwrite is atomic and replaces.
        try store.write(Data("v2".utf8), to: path)
        #expect(try store.read(path) == Data("v2".utf8))
        #expect(try store.slipFolders().map { [$0.profile, $0.slip] } == [[profile, slip]])
        try store.removeSlip(profile: profile, slip: slip)
        #expect(!store.exists(path))
        try store.removeSlip(profile: profile, slip: slip)
    }
}
