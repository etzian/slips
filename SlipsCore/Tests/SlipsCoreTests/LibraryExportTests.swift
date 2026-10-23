import Foundation
import GRDB
import Testing
@testable import SlipsCore

@Suite struct LibraryQueryTests {
    let h: OutboxHarness
    let query: LibraryQuery

    init() throws {
        h = try OutboxHarness()
        query = LibraryQuery(database: h.db)
    }

    @discardableResult
    func slip(_ merchant: String, day: CalendarDay?, notes: String? = nil, ocr: String? = nil, kind: Kind? = nil,
              status: SlipStatus = .ready, checks: [Check] = []) throws -> Slip {
        var s = try h.readySlip([], merchant: merchant)
        s.txnDate = day
        s.notes = notes
        s.ocrText = ocr
        s.kind = kind
        s.status = status
        s.setChecks(checks)
        let saved = s
        try h.db.writer.write { try saved.update($0) }
        return saved
    }

    func search(_ text: String) throws -> [String?] {
        var f = LibraryFilter()
        f.search = text
        return try query.items(profile: h.profile.id, filter: f).map(\.slip.merchant)
    }

    @Test func ftsFindsMerchantNotesAndOCRWithoutAccents() throws {
        try slip("Épicerie Fictive", day: CalendarDay(year: 2026, month: 10, day: 20))
        try slip("Fake Hardware", day: CalendarDay(year: 2026, month: 10, day: 19), notes: "vis pour la terrasse")
        try slip("Bistro Fictif", day: CalendarDay(year: 2026, month: 9, day: 1), ocr: "POURBOIRE 7,59\nTOTAL 58,18")
        #expect(try search("epicerie") == ["Épicerie Fictive"])
        #expect(try search("ÉPIC") == ["Épicerie Fictive"])
        #expect(try search("terrasse") == ["Fake Hardware"])
        #expect(try search("pourboire") == ["Bistro Fictif"])
        #expect(try search("fict") == ["Épicerie Fictive", "Bistro Fictif"])
        #expect(try search("fictive bistro").isEmpty)
        #expect(try search("\"unbalanced OR NEAR(") .isEmpty)
        #expect(try search("   ").count == 3)
    }

    @Test func ftsFollowsEditsAndDeletes() throws {
        let s = try slip("Old Name", day: nil)
        #expect(try search("old") == ["Old Name"])
        try h.db.writer.write { db in try db.execute(sql: "UPDATE slips SET merchant = 'New Name' WHERE id = ?", arguments: [s.id]) }
        #expect(try search("old").isEmpty)
        #expect(try search("new") == ["New Name"])
        _ = try h.db.writer.write { db in try Slip.deleteOne(db, id: s.id) }
        #expect(try search("new").isEmpty)
    }

    @Test func filtersAndMonths() throws {
        try slip("A", day: CalendarDay(year: 2026, month: 10, day: 20), kind: .personal)
        try slip("B", day: CalendarDay(year: 2026, month: 10, day: 2), kind: .enterprise,
                 checks: [Check(code: "sum_mismatch", severity: .warning)])
        try slip("C", day: CalendarDay(year: 2026, month: 9, day: 30), kind: .personal, status: .draft,
                 checks: [Check(code: "tax_rate", severity: .info)])
        var f = LibraryFilter()
        f.kind = .personal
        #expect(try query.items(profile: h.profile.id, filter: f).map(\.slip.merchant) == ["A", "C"])
        f = LibraryFilter()
        f.status = .draft
        #expect(try query.items(profile: h.profile.id, filter: f).map(\.slip.merchant) == ["C"])
        f = LibraryFilter()
        f.withWarnings = true
        #expect(try query.items(profile: h.profile.id, filter: f).map(\.slip.merchant) == ["B"])
        f = LibraryFilter()
        f.from = CalendarDay(year: 2026, month: 10, day: 1)
        f.to = CalendarDay(year: 2026, month: 10, day: 19)
        #expect(try query.items(profile: h.profile.id, filter: f).map(\.slip.merchant) == ["B"])
        #expect(f.isActive && !LibraryFilter().isActive)

        let months = LibraryQuery.months(try query.items(profile: h.profile.id, filter: LibraryFilter()))
        #expect(months.map(\.id) == [202_610, 202_609])
        #expect(months[0].items.map(\.slip.merchant) == ["A", "B"])
    }

    @Test func deliveryStateFilter() async throws {
        let nas = try h.destination("NAS")
        let a = try h.readySlip([nas], merchant: "Sent")
        try h.readySlip([nas], merchant: "Waiting")
        try h.readySlip([], merchant: "Local")
        try await h.db.writer.write { db in
            try db.execute(sql: "UPDATE deliveries SET status = 'done' WHERE slip_id = ?", arguments: [a.id])
        }
        let all = try query.items(profile: h.profile.id, filter: LibraryFilter())
        let states = Dictionary(uniqueKeysWithValues: all.map { ($0.slip.merchant!, $0.delivery) })
        #expect(states == ["Sent": .delivered, "Waiting": .waiting, "Local": .localOnly])
        try await h.db.writer.write { db in try db.execute(sql: "UPDATE deliveries SET status = 'failed' WHERE status = 'pending'") }
        var f = LibraryFilter()
        f.delivery = .problem
        #expect(try query.items(profile: h.profile.id, filter: f).map(\.slip.merchant) == ["Waiting"])
    }

    @Test func ftsQueryEscaping() {
        #expect(LibraryQuery.ftsQuery("café  fictif") == "\"café\"* \"fictif\"*")
        #expect(LibraryQuery.ftsQuery("a\"b") == "\"a\"* \"b\"*")
        #expect(LibraryQuery.ftsQuery(" - ") == nil)
    }
}

@Suite struct ExportTests {
    @Test func csvEscaping() {
        #expect(Exporter.csvField("plain") == "plain")
        #expect(Exporter.csvField("a,b") == "\"a,b\"")
        #expect(Exporter.csvField("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(Exporter.csvField("line\nbreak") == "\"line\nbreak\"")
        #expect(Exporter.csvField(" padded") == "\" padded\"")
        #expect(Exporter.csvField("=SUM(A1)") == "'=SUM(A1)")
        #expect(Exporter.csvField("@cmd") == "'@cmd")
        #expect(Exporter.csvField("-2.00") == "-2.00")
        #expect(Exporter.csvField("") == "")
    }

    func exported() throws -> (OutboxHarness, Exporter, [LibraryEntry], [Exporter.Row]) {
        let h = try OutboxHarness()
        let shop = try ReferenceData(database: h.db).addEnterprise(profile: h.profile.id, name: "Shop, Inc")
        for (merchant, total) in [("Café \"Fictif\"", 575), ("Café \"Fictif\"", 575), ("Fake Hardware", 4367)] {
            var s = try h.readySlip([], merchant: merchant)
            s.txnDate = CalendarDay(year: 2026, month: 10, day: 20)
            s.total = total
            s.kind = .enterprise
            s.enterpriseId = shop.id
            s.notes = "line1\nline2"
            let saved = s
            try h.db.writer.write { try saved.update($0) }
        }
        let exporter = Exporter(database: h.db, files: h.files)
        let items = try LibraryQuery(database: h.db).items(profile: h.profile.id, filter: LibraryFilter())
        return (h, exporter, items, try exporter.rows(items))
    }

    @Test func rowsAndCSV() throws {
        let (_, _, _, rows) = try exported()
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.business == "Shop, Inc" && $0.kind == "enterprise" && $0.date == "2026-10-20" })
        #expect(Set(rows.map(\.total)) == ["5.75", "43.67"])
        let csv = String(decoding: Exporter.csv(rows), as: UTF8.self)
        #expect(csv.hasPrefix("\u{FEFF}id,date,merchant,"))
        #expect(csv.contains("\"Café \"\"Fictif\"\"\""))
        #expect(csv.contains("\"Shop, Inc\""))
        #expect(csv.contains("\"line1\nline2\""))
        #expect(csv.hasSuffix("\r\n"))
        #expect(csv.components(separatedBy: "\r\n").count == 5) // header, 3 rows, trailing empty
    }

    @Test func jsonRoundTrips() throws {
        let (_, _, _, rows) = try exported()
        let decoded = try JSONDecoder().decode([Exporter.Row].self, from: try Exporter.json(rows))
        #expect(decoded == rows)
        #expect(String(decoding: try Exporter.json(rows), as: UTF8.self).contains("\"pdf_file\""))
    }

    @Test func zipManifestHasUniqueNames() throws {
        let (h, exporter, items, rows) = try exported()
        let manifest = Exporter.manifest(rows)
        #expect(manifest.count == 4)
        #expect(Set(manifest.map { $0.lowercased() }).count == 4)
        #expect(manifest.last == "slips.csv")
        #expect(manifest.contains("Shop, Inc/2026/2026-10-20_Café -Fictif-_5.75.pdf"))

        let archive = try exporter.zip(items, rows: rows)
        let entries = try ZipReader.entries(archive)
        #expect(entries.map(\.name) == manifest)
        let first = try #require(entries.first)
        #expect(first.data == (try h.files.read(items[0].slip.pdfPath)))
        #expect(entries.last?.data == Exporter.csv(rows))
    }

    @Test func zipIsReadableByUnzip() throws {
        var w = ZipWriter()
        try w.add("a/é.txt", contents: Data("hello".utf8))
        try w.add("b.txt", contents: Data())
        #expect(throws: ZipWriter.ZipError.duplicateName("b.txt")) { try w.add("b.txt", contents: Data()) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).zip")
        try w.finish().write(to: url)
        let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
        guard FileManager.default.isExecutableFile(atPath: unzip.path) else { return }
        let p = Process()
        p.executableURL = unzip
        p.arguments = ["-tq", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }

    @Test func crc32() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}

/// Reads back what `ZipWriter` writes (stored entries), for the tests.
enum ZipReader {
    struct Entry { let name: String; let data: Data }

    static func entries(_ zip: Data) throws -> [Entry] {
        let b = [UInt8](zip)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var result: [Entry] = []
        var o = 0
        while o + 30 <= b.count, u32(o) == 0x0403_4b50 {
            let size = u32(o + 18), nameLength = u16(o + 26), extra = u16(o + 28)
            let name = String(decoding: b[(o + 30)..<(o + 30 + nameLength)], as: UTF8.self)
            let start = o + 30 + nameLength + extra
            let data = Data(b[start..<(start + size)])
            #expect(CRC32.checksum(data) == UInt32(u32(o + 14)))
            result.append(Entry(name: name, data: data))
            o = start + size
        }
        return result
    }
}
