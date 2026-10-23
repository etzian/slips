import Foundation
import GRDB
import Testing
@testable import SlipsCore

/// One test per check of plan §5, each with the outcome that fires and the one that does not.
@Suite struct SlipChecksTests {
    let today = CalendarDay(year: 2026, month: 10, day: 23)!
    var context: SlipChecks.Context { SlipChecks.Context(today: today) }

    func slip(_ configure: (inout Slip) -> Void = { _ in }) -> Slip {
        var s = Slip(profileId: UUID(), pdfPath: "x", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        s.total = 2300
        configure(&s)
        return s
    }

    func codes(_ s: Slip, _ c: SlipChecks.Context? = nil) -> [String] {
        SlipChecks.run(s, context: c ?? context).map(\.code)
    }

    @Test func totalMissingBlocks() {
        let checks = SlipChecks.run(slip { $0.total = nil }, context: context)
        #expect(checks.first == Check(code: "total_missing", severity: .blocking))
        #expect(!codes(slip()).contains("total_missing"))
    }

    @Test func sumMismatch() {
        let bad = slip { $0.subtotal = 2000; $0.gst = 100; $0.qst = 200; $0.total = 2400 }
        let check = SlipChecks.run(bad, context: context).first { $0.code == "sum_mismatch" }
        #expect(check?.severity == .warning)
        #expect(check?.values == [.money(2300, currency: "CAD"), .money(2400, currency: "CAD")])
        // Within two cents is rounding.
        #expect(!codes(slip { $0.subtotal = 2000; $0.gst = 100; $0.qst = 200; $0.total = 2302 }).contains("sum_mismatch"))
        #expect(!codes(slip { $0.subtotal = 4400; $0.gst = 220; $0.qst = 439; $0.tip = 759; $0.total = 5818 }).contains("sum_mismatch"))
    }

    @Test func taxRate() {
        #expect(!codes(slip { $0.subtotal = 3798; $0.gst = 190; $0.qst = 379; $0.total = 4367 }).contains("tax_rate"))
        let wrong = SlipChecks.run(slip { $0.subtotal = 2000; $0.gst = 150; $0.qst = 200; $0.total = 2350 }, context: context)
        #expect(wrong.first { $0.code == "tax_rate" }?.severity == .info)
        // Without a subtotal the taxable amount is total − taxes − tip.
        #expect(!codes(slip { $0.gst = 254; $0.qst = 506; $0.total = 5827 }).contains("tax_rate"))
        // Only when both are present.
        #expect(!codes(slip { $0.subtotal = 2000; $0.gst = 999; $0.total = 2999 }).contains("tax_rate"))
    }

    @Test func dateInFutureOrTooOld() {
        #expect(codes(slip { $0.txnDate = CalendarDay(year: 2026, month: 10, day: 24) }).contains("date_future"))
        #expect(codes(slip { $0.txnDate = CalendarDay(year: 2024, month: 10, day: 22) }).contains("date_too_old"))
        #expect(!codes(slip { $0.txnDate = CalendarDay(year: 2024, month: 10, day: 23) }).contains("date_too_old"))
        #expect(!codes(slip { $0.txnDate = today }).contains("date_future"))
        let c = SlipChecks.Context(today: today, maxAgeYears: 6)
        #expect(!codes(slip { $0.txnDate = CalendarDay(year: 2022, month: 1, day: 1) }, c).contains("date_too_old"))
    }

    @Test func unknownCard() {
        var e = Extraction()
        e.cardLast4 = ExtractedField(value: "0042", confidence: 0.95)
        let s = slip { $0.extracted = e.json }
        #expect(SlipChecks.run(s, context: context).contains(Check(code: "card_unknown", severity: .info, values: [.text("0042")])))
        #expect(!codes(s, SlipChecks.Context(today: today, knownLastFours: ["0042"])).contains("card_unknown"))
        #expect(!codes(slip { $0.extracted = e.json; $0.paymentMethodId = UUID() }).contains("card_unknown"))
    }

    @Test func registrationNumbersForBusinessSlips() {
        #expect(codes(slip { $0.kind = .enterprise; $0.supplierGstNo = "100000000 RT0001" }).contains("registration_missing"))
        #expect(!codes(slip { $0.kind = .enterprise; $0.supplierGstNo = "100000000 RT0001"; $0.supplierQstNo = "1000000000 TQ0001" })
            .contains("registration_missing"))
        #expect(!codes(slip { $0.kind = .enterprise; $0.hst = 520; $0.supplierGstNo = "100000000 RT0001" }).contains("registration_missing"))
        #expect(!codes(slip { $0.kind = .personal }).contains("registration_missing"))
    }

    @Test func duplicateAndFileMissing() {
        #expect(codes(slip(), SlipChecks.Context(today: today, duplicateExists: true)).contains("duplicate"))
        #expect(!codes(slip()).contains("duplicate"))
        #expect(codes(slip(), SlipChecks.Context(today: today, fileExists: false)).first == "file_missing")
        #expect(!codes(slip()).contains("file_missing"))
    }

    @Test func mostSevereFirst() {
        let s = slip { $0.total = nil; $0.txnDate = CalendarDay(year: 2027, month: 1, day: 1); $0.kind = .enterprise }
        let severities = SlipChecks.run(s, context: context).map(\.severity)
        #expect(severities == severities.sorted(by: >))
    }
}

@Suite struct ChecksStorageTests {
    @Test func duplicatesFoundInTheDatabase() throws {
        let db = try AppDatabase.inMemory()
        let files = FileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try files.write(Data("pdf".utf8), to: "x")
        let store = SlipStore(database: db, files: files)
        let profile = try db.createProfile(name: "P")
        var first = Slip(profileId: profile.id, pdfPath: "x", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        first.merchant = "Café Fictif #1"
        first.txnDate = CalendarDay(year: 2026, month: 10, day: 20)
        first.total = 575
        try db.writer.write { [first] db in try first.insert(db) }
        var second = first
        second.id = UUID()
        second.merchant = "CAFE FICTIF"
        #expect(try store.checks(for: second, today: CalendarDay(year: 2026, month: 10, day: 23)!).map(\.code).contains("duplicate"))
        #expect(!(try store.checks(for: first, today: CalendarDay(year: 2026, month: 10, day: 23)!).map(\.code).contains("duplicate")))
        second.total = 576
        #expect(!(try store.checks(for: second, today: CalendarDay(year: 2026, month: 10, day: 23)!).map(\.code).contains("duplicate")))
    }

    @Test func draftSaveStoresChecks() throws {
        let db = try AppDatabase.inMemory()
        let files = FileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let store = SlipStore(database: db, files: files)
        let profile = try db.createProfile(name: "P")
        let s = Slip(profileId: profile.id, pdfPath: "missing", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        try db.writer.write { try s.insert($0) }
        try store.saveDraft(s)
        #expect(try store.slip(s.id)?.decodedChecks.map(\.code) == ["file_missing", "total_missing"])
    }
}

@Suite struct DiscardDraftTests {
    @Test func cancelledCaptureLeavesNothingAndFiledSlipsAreRefused() throws {
        let db = try AppDatabase.inMemory()
        let files = FileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let profile = try db.createProfile(name: "P")
        let capture = CaptureStore(database: db, files: files)
        let store = SlipStore(database: db, files: files)

        let draft = try capture.save(pdf: Data("%PDF".utf8), pageCount: 1, profile: profile.id)
        try store.discardDraft(draft.id)
        #expect(try store.slip(draft.id) == nil)
        #expect(!files.exists(draft.pdfPath))
        try store.discardDraft(draft.id) // already gone: no error

        var filed = try capture.save(pdf: Data("%PDF 2".utf8), pageCount: 1, profile: profile.id)
        filed.status = .ready
        try db.writer.write { [filed] in try filed.update($0) }
        #expect(throws: SaveError.notADraft) { try store.discardDraft(filed.id) }
        #expect(files.exists(filed.pdfPath))
    }
}
