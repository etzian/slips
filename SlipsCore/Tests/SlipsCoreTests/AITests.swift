import Foundation
import GRDB
import Testing
@testable import SlipsCore

/// A scripted assistant for tests: returns `reading`, or throws.
struct FakeAssistant: ExtractionAssistant {
    var id = "fake"
    var reading: AIExtraction
    var failure: (any Error)?

    func extract(_ input: AssistantInput) async throws -> AIExtraction {
        if let failure { throw failure }
        return reading
    }
}

func field<V>(_ v: V, _ c: Double = 0.9) -> ExtractedField<V> { ExtractedField(value: v, confidence: c) }

@Suite struct AIMergeTests {
    /// A draft as the parser left it: total read with confidence `totalConfidence`, no date.
    func parsed(total: Int?, totalConfidence: Double = 0.9, merchant: String? = "Fake Store") -> Slip {
        var e = Extraction()
        e.total = total.map { field($0, totalConfidence) }
        e.merchant = merchant.map { field($0, 0.8) }
        var s = Slip(profileId: UUID(), pdfPath: "x", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        s.apply(e, ocrText: "")
        return s
    }

    @Test func fillsOnlyGaps() {
        var ai = AIExtraction()
        ai.total = field(9999)
        ai.date = field(CalendarDay(year: 2026, month: 10, day: 20)!)
        ai.merchant = field("Other Name")
        let (slip, filled) = AIMerge.merge(ai, into: parsed(total: 1234))
        #expect(slip.total == 1234)                 // the parser was sure
        #expect(slip.merchant == "Fake Store")      // ditto
        #expect(slip.txnDate?.iso == "2026-10-20")  // the parser had nothing
        #expect(filled == ["date"])
    }

    @Test func replacesALowConfidenceReading() {
        var ai = AIExtraction()
        ai.total = field(1035)
        let (slip, filled) = AIMerge.merge(ai, into: parsed(total: 1085, totalConfidence: 0.3))
        #expect(slip.total == 1035)
        #expect(filled == ["total"])
    }

    @Test func neverOverwritesWhatTheUserTyped() {
        var draft = parsed(total: 1085, totalConfidence: 0.3, merchant: nil)
        draft.total = 1100            // typed by the user
        draft.merchant = "Typed name" // the parser had none
        var ai = AIExtraction()
        ai.total = field(1035)
        ai.merchant = field("Model name")
        let (slip, filled) = AIMerge.merge(ai, into: draft)
        #expect(slip.total == 1100)
        #expect(slip.merchant == "Typed name")
        #expect(filled.isEmpty)
    }

    @Test func sanitizedDropsWhatAnAssistantMayNotSay() {
        var ai = AIExtraction()
        ai.subcategoryKey = field("personal.casino")
        ai.currency = field("dollars")
        ai.total = field(-5)
        ai.gst = field(50)
        let clean = AIMerge.sanitized(ai)
        #expect(clean.subcategoryKey == nil)
        #expect(clean.currency == nil)
        #expect(clean.total == nil)
        #expect(clean.gst?.value == 50)
        var ok = AIExtraction()
        ok.subcategoryKey = field("personal.groceries")
        #expect(AIMerge.sanitized(ok).subcategoryKey?.value == "personal.groceries")
    }
}

@Suite struct AIDisagreementTests {
    let today = CalendarDay(year: 2026, month: 10, day: 23)!

    func codes(_ slip: Slip, _ ai: AIExtraction) -> [String] {
        SlipChecks.run(slip, context: SlipChecks.Context(today: today, ai: ai)).map(\.code)
    }

    var slip: Slip {
        var s = Slip(profileId: UUID(), pdfPath: "x", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        s.total = 2300
        s.gst = 100
        s.qst = 200
        s.merchant = "Épicerie Fictive #12"
        s.txnDate = CalendarDay(year: 2026, month: 10, day: 20)
        return s
    }

    @Test func total() {
        var ai = AIExtraction()
        ai.total = field(2900)
        let check = SlipChecks.run(slip, context: .init(today: today, ai: ai)).first { $0.code == "ai_disagrees_total" }
        #expect(check?.severity == .warning)
        #expect(check?.values == [.money(2900, currency: "CAD")])
        ai.total = field(2301)
        #expect(!codes(slip, ai).contains("ai_disagrees_total"))
    }

    @Test func date() {
        var ai = AIExtraction()
        ai.date = field(CalendarDay(year: 2026, month: 10, day: 2)!)
        #expect(codes(slip, ai).contains("ai_disagrees_date"))
        ai.date = field(CalendarDay(year: 2026, month: 10, day: 20)!)
        #expect(!codes(slip, ai).contains("ai_disagrees_date"))
    }

    @Test func merchant() {
        var ai = AIExtraction()
        ai.merchant = field("Quincaillerie Autre")
        #expect(codes(slip, ai).contains("ai_disagrees_merchant"))
        ai.merchant = field("EPICERIE FICTIVE")
        #expect(!codes(slip, ai).contains("ai_disagrees_merchant"))
        ai.merchant = field("Épicerie Fictive inc. — succursale 12")
        #expect(!codes(slip, ai).contains("ai_disagrees_merchant"))
    }

    @Test func taxes() {
        var ai = AIExtraction()
        ai.gst = field(115)
        #expect(codes(slip, ai).contains("ai_disagrees_taxes"))
        ai.gst = field(101)
        #expect(!codes(slip, ai).contains("ai_disagrees_taxes"))
    }

    @Test func nothingWithoutAnAssistant() {
        #expect(!codes(slip, AIExtraction()).contains { $0.hasPrefix("ai_") })
        #expect(!SlipChecks.run(slip, context: .init(today: today)).contains { $0.code.hasPrefix("ai_") })
    }
}

@Suite struct RecordAITests {
    @Test func storedMergedAndChecked() async throws {
        let db = try AppDatabase.inMemory()
        let files = FileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let profile = try db.createProfile(name: "P")
        let draft = try CaptureStore(database: db, files: files).save(pdf: Data("%PDF".utf8), pageCount: 1, profile: profile.id)
        let store = SlipStore(database: db, files: files)

        var reading = AIExtraction()
        reading.total = field(1150)
        reading.date = field(CalendarDay(year: 2026, month: 10, day: 20)!)
        reading.subcategoryKey = field("personal.groceries")
        let assistant = FakeAssistant(reading: reading)
        let result = try await assistant.extract(AssistantInput(ocrText: "TOTAL 11,50", localeIdentifier: "fr_CA"))
        let saved = try #require(try store.recordAI(result, assistant: assistant.id, model: "test", for: draft.id))

        #expect(saved.total == 1150)
        #expect(saved.aiResult?.filled.sorted() == ["date", "total"])
        #expect(saved.aiResult?.assistant == "fake")
        #expect(saved.aiResult?.extraction.subcategoryKey?.value == "personal.groceries")
        #expect(!saved.decodedChecks.contains { $0.code == "total_missing" })
        let reloaded = try #require(try store.slip(draft.id))
        #expect(reloaded.aiResult == saved.aiResult)

        // A filed slip keeps its values; the reading only raises checks.
        var filed = reloaded
        filed.status = .ready
        filed.total = 1200
        try await db.writer.write { [filed] in try filed.update($0) }
        let after = try #require(try store.recordAI(result, assistant: "fake", for: draft.id))
        #expect(after.total == 1200)
        #expect(after.decodedChecks.contains { $0.code == "ai_disagrees_total" })
    }

    @Test func failingAssistantThrows() async {
        struct Down: Error {}
        let assistant = FakeAssistant(reading: AIExtraction(), failure: Down())
        await #expect(throws: Down.self) { try await assistant.extract(AssistantInput(ocrText: "", localeIdentifier: "en_CA")) }
    }
}
