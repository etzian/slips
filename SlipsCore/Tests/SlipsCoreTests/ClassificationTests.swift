import Foundation
import GRDB
import Testing
@testable import SlipsCore

@Suite struct MerchantNameTests {
    @Test func normalisation() {
        #expect(MerchantName.normalize("ÉPICERIE FICTIVE #0042") == "epicerie fictive")
        #expect(MerchantName.normalize("Epicerie Fictive inc.") == "epicerie fictive")
        #expect(MerchantName.normalize("Café  Fictif — succ. 12") == "cafe fictif")
        #expect(MerchantName.normalize("FAKE HARDWARE STORE 0001") == "fake hardware")
        #expect(MerchantName.normalize("Quincaillerie Fictive Ltée") == "quincaillerie fictive")
        #expect(MerchantName.normalize("1234") == "")
    }
}

@Suite struct SuggestionTests {
    let profile = UUID()
    let shop = UUID(), studio = UUID()
    let groceries = UUID(), software = UUID(), transfer = UUID(), dining = UUID()
    let visa = UUID(), debit = UUID()
    let today = CalendarDay(year: 2026, month: 10, day: 23)!

    var reference: ReferenceSnapshot {
        ReferenceSnapshot(
            enterprises: [Enterprise(id: shop, profileId: profile, name: "Shop"), Enterprise(id: studio, profileId: profile, name: "Studio")],
            subcategories: [
                Subcategory(id: groceries, profileId: profile, kind: .personal, nameKey: "personal.groceries"),
                Subcategory(id: dining, profileId: profile, kind: .personal, nameKey: "personal.dining"),
                Subcategory(id: software, profileId: profile, kind: .enterprise, nameKey: "enterprise.software"),
                Subcategory(id: transfer, profileId: profile, kind: .any, nameKey: "any.transfer"),
            ],
            paymentMethods: [
                PaymentMethod(id: visa, profileId: profile, name: "Visa", type: .creditCard, last4: "0042",
                              defaultKind: .enterprise, defaultEnterpriseId: studio),
                PaymentMethod(id: debit, profileId: profile, name: "Debit", type: .debit, last4: "0007", defaultKind: .personal),
            ])
    }

    func h(_ merchant: String, daysAgo: Int, total: Int? = nil, _ kind: Kind?, business: UUID? = nil, sub: UUID? = nil,
           method: UUID? = nil) -> HistoryEntry {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: today.date(in: NamingRule.utc))!
        return HistoryEntry(merchantNorm: MerchantName.normalize(merchant), day: CalendarDay(date, calendar: NamingRule.utc),
                            total: total, kind: kind, enterpriseId: business, subcategoryId: sub, paymentMethodId: method)
    }

    func suggest(card: String? = nil, merchant: String? = "Fake Store", total: Int? = nil, ai: String? = nil,
                 _ history: [HistoryEntry]) -> Suggestion {
        Suggestions.suggest(cardLast4: card, merchant: merchant, total: total, aiSubcategoryKey: ai, reference: reference,
                            history: history, today: today)
    }

    @Test func cardDefaultsWinOverHistory() {
        let s = suggest(card: "0042", [h("Fake Store", daysAgo: 1, .personal, sub: groceries, method: debit)])
        #expect(s.classification.paymentMethodId == visa)
        #expect(s.classification.kind == .enterprise)
        #expect(s.classification.enterpriseId == studio)
        #expect(s.reasons[.kind] == .card("0042"))
        // The merchant's personal sub-category does not fit an enterprise slip, and nothing else does.
        #expect(s.classification.subcategoryId == nil)
    }

    @Test func merchantHistoryMajorityAndRecency() {
        let history = [
            h("Fake Store #1", daysAgo: 400, .personal, sub: dining),
            h("FAKE STORE", daysAgo: 300, .personal, sub: dining),
            h("Fake Store", daysAgo: 5, .personal, sub: groceries),
            h("Other", daysAgo: 1, .enterprise, business: shop, sub: software),
        ]
        let s = suggest(history)
        // Two old dining slips weigh less than one recent groceries slip (half-life 90 days).
        #expect(s.classification.subcategoryId == groceries)
        #expect(s.classification.kind == .personal)
        #expect(s.reasons[.subcategory] == .merchantHistory(3))
    }

    @Test func majorityWinsAtTheSameAge() {
        let history = [
            h("Fake Store", daysAgo: 10, .personal, sub: dining),
            h("Fake Store", daysAgo: 10, .personal, sub: dining),
            h("Fake Store", daysAgo: 10, .personal, sub: groceries),
        ]
        #expect(suggest(history).classification.subcategoryId == dining)
    }

    @Test func tieGoesToTheMostRecent() {
        let history = [h("Fake Store", daysAgo: 3, .personal, sub: dining), h("Fake Store", daysAgo: 2, .personal, sub: groceries)]
        let a = Suggestions.weight(history[0].day, today: today), b = Suggestions.weight(history[1].day, today: today)
        #expect(b > a)
        #expect(suggest(history).classification.subcategoryId == groceries)
    }

    @Test func similarAmountWithTheSameCard() {
        let history = [
            h("Gas A", daysAgo: 20, total: 6000, .enterprise, business: shop, sub: software, method: debit),
            h("Gas B", daysAgo: 30, total: 6500, .enterprise, business: shop, sub: software, method: debit),
            h("Cafe", daysAgo: 1, total: 500, .personal, sub: dining, method: debit),
        ]
        let s = suggest(card: "0007", merchant: "Unknown Gas", total: 6200, history)
        // The card's default kind is personal; the business pick only applies to enterprise slips.
        #expect(s.classification.kind == .personal)
        #expect(s.classification.subcategoryId == dining) // from "last used": software does not fit personal
        let noCard = suggest(merchant: "Unknown Gas", total: 6200, history)
        #expect(noCard.classification.kind == .enterprise)
        #expect(noCard.classification.enterpriseId == shop)
        #expect(noCard.reasons[.kind] == .similarAmount)
    }

    @Test func lastUsedThenAI() {
        let s = suggest(merchant: "New Place", [h("Old Place", daysAgo: 2, .personal, sub: dining, method: debit)])
        #expect(s.classification.kind == .personal)
        #expect(s.reasons[.kind] == .lastUsed)
        #expect(s.classification.paymentMethodId == debit)
        let empty = suggest(card: "0007", merchant: "New Place", ai: "personal.groceries", [])
        #expect(empty.classification.subcategoryId == groceries)
        #expect(empty.reasons[.subcategory] == .ai)
        // An AI key that does not fit the kind is ignored.
        let wrong = suggest(card: "0007", merchant: "New Place", ai: "enterprise.software", [])
        #expect(wrong.classification.subcategoryId == nil)
    }

    @Test func archivedValuesAreNotSuggested() {
        let gone = UUID()
        let s = suggest([h("Fake Store", daysAgo: 1, .enterprise, business: gone, sub: gone, method: gone)])
        #expect(s.classification.kind == .enterprise)
        #expect(s.classification.enterpriseId == nil)
        #expect(s.classification.subcategoryId == nil)
        #expect(s.classification.paymentMethodId == nil)
    }

    @Test func nothingKnown() {
        #expect(suggest(merchant: nil, []).classification == Classification())
    }
}

@Suite struct SlipStoreTests {
    let db: AppDatabase
    let store: SlipStore
    let profile: Profile
    let snapshot: ReferenceSnapshot

    init() throws {
        db = try AppDatabase.inMemory()
        let files = FileStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try files.write(Data("pdf".utf8), to: "x")
        store = SlipStore(database: db, files: files)
        profile = try db.createProfile(name: "P")
        snapshot = try ReferenceData(database: db).snapshot(profile: profile.id)
    }

    func draft(merchant: String = "Épicerie Fictive #12") throws -> Slip {
        var s = Slip(profileId: profile.id, pdfPath: "x", pdfSha256: String(repeating: "a", count: 64), pageCount: 1)
        s.merchant = merchant
        s.total = 1000
        try db.writer.write { [s] db in try s.insert(db) }
        return s
    }

    var groceries: UUID { snapshot.subcategories.first { $0.nameKey == "personal.groceries" }!.id }

    @Test func draftGetsNoDelivery() throws {
        var s = try draft()
        s.notes = "kept"
        try store.saveDraft(s)
        #expect(try store.slip(s.id)?.notes == "kept")
        #expect(try store.slip(s.id)?.status == .draft)
        #expect(try db.writer.read { try Delivery.fetchCount($0) } == 0)
    }

    @Test func readyCreatesDeliveriesForEnabledDestinationsOnly() throws {
        try db.writer.write { db in
            try db.execute(sql: "UPDATE destinations SET enabled = 1 WHERE type = 'icloud'")
            try Destination(profileId: profile.id, type: .webdav, name: "NAS", enabled: false).insert(db)
        }
        var s = try draft()
        s.kind = .personal
        s.subcategoryId = groceries
        try store.markReady(s)
        let deliveries = try db.writer.read { try Delivery.fetchAll($0) }
        #expect(deliveries.count == 1)
        #expect(deliveries.first?.status == .pending)
        #expect(try store.slip(s.id)?.status == .ready)
        // Saving again does not duplicate.
        try store.markReady(s)
        #expect(try db.writer.read { try Delivery.fetchCount($0) } == 1)
    }

    @Test func readyUpdatesMerchantMemoryAndSuggestsNextTime() throws {
        var s = try draft()
        s.kind = .personal
        s.subcategoryId = groceries
        try store.markReady(s)
        try store.markReady(s)
        let memory = try db.writer.read { try MerchantMemory.fetchOne($0) }
        #expect(memory?.merchantNorm == "epicerie fictive")
        #expect(memory?.uses == 2)
        let next = try draft(merchant: "EPICERIE FICTIVE #99")
        let suggestion = try store.suggestion(for: next)
        #expect(suggestion.classification == Classification(kind: .personal, subcategoryId: groceries))
        #expect(suggestion.reasons[.subcategory] == .merchantHistory(1))
    }

    @Test func readyRefusedWhenIncompleteOrBlocked() throws {
        var s = try draft()
        #expect(throws: SaveError.classificationIncomplete) { try store.markReady(s) }
        s.kind = .enterprise
        s.subcategoryId = groceries
        #expect(throws: SaveError.classificationIncomplete) { try store.markReady(s) }
        s.kind = .personal
        s.total = nil
        #expect(throws: SaveError.blockingCheck("total_missing")) { try store.markReady(s) }
        #expect(try store.slip(s.id)?.status == .draft)
    }

    @Test func businessClearedForNonBusinessKind() throws {
        let shop = try ReferenceData(database: db).addEnterprise(profile: profile.id, name: "Shop")
        var s = try draft()
        s.kind = .personal
        s.enterpriseId = shop.id
        s.subcategoryId = groceries
        try store.markReady(s)
        #expect(try store.slip(s.id)?.enterpriseId == nil)
    }
}
